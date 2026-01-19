@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul

:: --- CONFIGURATION & DATA FILES ---
set "CONFIG_DIR=%USERPROFILE%\.config\anisub_cli"
set "CONFIG_FILE=%CONFIG_DIR%\config.cfg"
set "HISTORY_FILE=%CONFIG_DIR%\history.log"
set "FAVORITES_FILE=%CONFIG_DIR%\favorites.txt"

:: Local Data File
set "SCRIPT_DIR=%~dp0"
set "LOCAL_DATA_FILE=%SCRIPT_DIR%assets\aniw_export_2026-01-14.csv"

:: --- DEFAULTS ---
set "DEFAULT_PLAYER=mpv"
set "DEFAULT_DOWNLOAD_DIR=%USERPROFILE%\Downloads\anime"
set "PLAYER="
set "DOWNLOAD_DIR="

:: --- INITIALIZATION ---
call :LoadConfig
call :CheckDependencies

:: --- MAIN LOOP ---
:MainMenu
cls
echo =======================================================
echo               ANISUB CLI (Windows Edition)
echo =======================================================
echo.
echo [1] 🔎 Tim kiem Anime (KKPhim API)
echo [2] 📂 Xem tu Local Anidata
echo [3] 📜 Lich su xem
echo [4] ⭐ Danh sach yeu thich
echo [5] ⚙️ Cai dat
echo [6] 🚪 Thoat
echo.

set "menu_choice="
set /p "menu_choice=Chon tac vu [1-6]: "

if "%menu_choice%"=="1" goto :SearchKKPhim
if "%menu_choice%"=="2" goto :LocalAni
if "%menu_choice%"=="3" goto :History
if "%menu_choice%"=="4" goto :Favorites
if "%menu_choice%"=="5" goto :Settings
if "%menu_choice%"=="6" exit
goto :MainMenu

:: --- FUNCTIONS ---

:CheckDependencies
    set "MISSING=0"
    for %%c in (ffmpeg curl fzf jq yt-dlp mpv) do (
        where %%c >nul 2>nul
        if !errorlevel! neq 0 (
            echo [LOI] Khong tim thay lenh: %%c
            set "MISSING=1"
        )
    )
    if %MISSING%==1 (
        echo.
        echo Vui long cai dat cac cong cu tren (Scoop hoac Chocolatey) va them vao PATH.
        pause
        exit
    )
exit /b

:LoadConfig
    if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
    if not exist "%CONFIG_FILE%" (
        echo PLAYER=%DEFAULT_PLAYER%> "%CONFIG_FILE%"
        echo DOWNLOAD_DIR=%DEFAULT_DOWNLOAD_DIR%>> "%CONFIG_FILE%"
    )
    
    :: Read Config manually since Windows can't source files directly easily
    for /f "tokens=1,2 delims==" %%a in (%CONFIG_FILE%) do (
        if "%%a"=="PLAYER" set "PLAYER=%%b"
        if "%%a"=="DOWNLOAD_DIR" set "DOWNLOAD_DIR=%%b"
    )
    
    if not defined PLAYER set "PLAYER=%DEFAULT_PLAYER%"
    if not defined DOWNLOAD_DIR set "DOWNLOAD_DIR=%DEFAULT_DOWNLOAD_DIR%"
    
    if not exist "%DOWNLOAD_DIR%" mkdir "%DOWNLOAD_DIR%"
    if not exist "%DOWNLOAD_DIR%\cut" mkdir "%DOWNLOAD_DIR%\cut"
    if not exist "%DOWNLOAD_DIR%\merged" mkdir "%DOWNLOAD_DIR%\merged"
    if not exist "%HISTORY_FILE%" type nul > "%HISTORY_FILE%"
    if not exist "%FAVORITES_FILE%" type nul > "%FAVORITES_FILE%"
exit /b

:SaveConfig
    (
        echo PLAYER=%PLAYER%
        echo DOWNLOAD_DIR=%DOWNLOAD_DIR%
    ) > "%CONFIG_FILE%"
    echo Cau hinh da duoc luu.
    timeout /t 1 >nul
exit /b

:AddToHistory
    :: %1 = name, %2 = episode, %3 = link
    set "aname=%~1"
    set "aep=%~2"
    set "alink=%~3"
    set "temp_hist=%HISTORY_FILE%.tmp"
    
    :: Simple logic: Just append. Deduplication is hard in Batch without grep -v
    :: You might need uniq.exe from git bash tools to deduplicate.
    
    :: Get date time
    for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
    set "curr_time=%datetime:~0,4%-%datetime:~4,2%-%datetime:~6,2% %datetime:~8,2%:%datetime:~10,2%:%datetime:~12,2%"
    
    echo %curr_time%^|%aname%^|%aep%^|%alink% >> "%HISTORY_FILE%"
exit /b

:PlayStream
    :: %1 = url, %2 = title
    echo Dang mo trinh phat...
    start "" /b "%PLAYER%" "%~1" --force-window --title="Anisub: %~2"
    :: Saving the process check approach is hard in pure batch. We assume it launches.
exit /b

:: --- FEATURES ---

:SearchKKPhim
    cls
    echo === TIM KIEM KKPHIM ===
    set "keyword="
    set /p "keyword=Nhap ten anime: "
    if "%keyword%"=="" goto :MainMenu

    :: URL Encode spaces
    set "encoded_keyword=%keyword: =%20%"

    echo Dang tim kiem...
    set "search_tmp=%TEMP%\ani_search.json"
    curl -s "https://phimapi.com/v1/api/tim-kiem?keyword=%encoded_keyword%&limit=20" > "%search_tmp%"

    :: Check status with jq
    for /f %%s in ('jq -r ".status" "%search_tmp%"') do set "status=%%s"
    if not "%status%"=="success" (
        echo Khong tim thay ket qua.
        timeout /t 2 >nul
        goto :MainMenu
    )

    :: Generate FZF input using JQ formatting: Name (Year)|Slug
    set "fzf_in=%TEMP%\fzf_search.txt"
    jq -r ".data.items[] | \"\(.name) (\(.year))|\(.slug)\"" "%search_tmp%" > "%fzf_in%"

    for /f "delims=" %%i in ('type "%fzf_in%" ^| fzf --prompt="Ket qua > " --delimiter="|" --with-nth=1') do set "selected=%%i"

    if "%selected%"=="" goto :MainMenu

    for /f "tokens=1,2 delims=|" %%a in ("%selected%") do (
        set "sel_name=%%a"
        set "sel_slug=%%b"
    )

    call :EpisodeMenu "%sel_name%" "%sel_slug%"
goto :MainMenu

:EpisodeMenu
    :: %1 = Anime Name, %2 = Slug
    set "e_name=%~1"
    set "e_slug=%~2"

    echo Dang lay danh sach tap phim...
    set "eps_tmp=%TEMP%\ani_episodes.json"
    curl -s "https://phimapi.com/phim/%e_slug%" > "%eps_tmp%"
    
    for /f %%s in ('jq -r ".status" "%eps_tmp%"') do set "estatus=%%s"
    if "%estatus%"=="false" (
        echo Loi khi lay tap phim.
        timeout /t 2 >nul
        goto :MainMenu
    )

    :: Extract episodes list: TapName|Link
    set "fzf_eps=%TEMP%\fzf_eps.txt"
    jq -r ".episodes[0].server_data[] | \"\(.name)|\(.link_m3u8)\"" "%eps_tmp%" > "%fzf_eps%"
    
    :LoopEps
    for /f "delims=" %%j in ('type "%fzf_eps%" ^| fzf --prompt="Chon tap phim > " --delimiter="|" --with-nth=1') do set "ep_selected=%%j"
    if "%ep_selected%"=="" goto :MainMenu

    for /f "tokens=1,2 delims=|" %%x in ("%ep_selected%") do (
        set "ep_name=%%x"
        set "ep_link=%%y"
    )

    :: Actions Menu for Selected Episode
    :ActionLoop
    cls
    echo.
    echo --- %e_name% - Tap %ep_name% ---
    echo [1] Phat (Play)
    echo [2] Tai xuong (Download)
    echo [3] Cat Video
    echo [4] Ghep Video
    echo [5] Them vao Yeu thich
    echo [6] Chon tap khac
    echo [0] Quay lai Menu chinh
    echo.

    set "act_choice="
    set /p "act_choice=Lua chon: "

    if "%act_choice%"=="1" (
        call :AddToHistory "%e_name%" "%ep_name%" "%ep_link%"
        call :PlayStream "%ep_link%" "%e_name% - Tap %ep_name%"
        goto :ActionLoop
    )
    if "%act_choice%"=="2" (
        start "" yt-dlp "%ep_link%" -o "%DOWNLOAD_DIR%\%e_slug%\Episode_%ep_name%.mp4"
        echo Da bat cua so tai xuong...
        timeout /t 2 >nul
        goto :ActionLoop
    )
    if "%act_choice%"=="3" (
        call :CutVideo "%ep_link%"
        goto :ActionLoop
    )
    if "%act_choice%"=="4" (
        call :MergeVideo
        goto :ActionLoop
    )
    if "%act_choice%"=="5" (
        echo %e_name%^|%e_slug% >> "%FAVORITES_FILE%"
        echo Da them vao yeu thich.
        timeout /t 1 >nul
        goto :ActionLoop
    )
    if "%act_choice%"=="6" goto :LoopEps
    if "%act_choice%"=="0" goto :MainMenu

goto :MainMenu


:LocalAni
    cls
    echo [Local Mode] Data file: %LOCAL_DATA_FILE%
    if not exist "%LOCAL_DATA_FILE%" (
        echo File du lieu khong ton tai.
        echo Dang tai tu GitHub...
        curl -L "https://raw.githubusercontent.com/NiyakiPham/anisub/main/assets/aniw_export_2026-01-14.csv" -o "%LOCAL_DATA_FILE%" --create-dirs
        if not exist "%LOCAL_DATA_FILE%" (
             echo Loi tai file.
             pause
             goto :MainMenu
        )
    )

    echo Parsing local data... (Might take a sec)
    :: Basic CSV parsing assuming "Name",...,"Episodes(Link|Name)" format is complex
    :: For Demo purpose, we use a simple parsing method if CSV format is standard.
    :: Since Batch handles CSV badly, we rely on string search or simpler methods.
    
    echo Tinh nang Local Parsing rat han che tren Batch thuan. 
    echo Ban nen dung chuc nang Online.
    pause
    goto :MainMenu
exit /b


:History
    cls
    if not exist "%HISTORY_FILE%" ( echo History trong. & timeout /t 2 & goto :MainMenu )
    
    echo === LICH SU ===
    :: Format history for FZF to show nicely
    for /f "delims=" %%h in ('type "%HISTORY_FILE%" ^| fzf --prompt="Lich su (Enter de xem): " --delimiter="|" --with-nth=1,2,3') do set "h_sel=%%h"
    
    if "%h_sel%"=="" goto :MainMenu
    
    for /f "tokens=1-4 delims=|" %%a in ("%h_sel%") do (
        set "h_name=%%b"
        set "h_ep=%%c"
        set "h_link=%%d"
    )
    
    call :PlayStream "%h_link%" "%h_name% - Tap %h_ep%"
goto :MainMenu

:Favorites
    cls
    if not exist "%FAVORITES_FILE%" ( echo Yeu thich trong. & timeout /t 2 & goto :MainMenu )
    
    for /f "delims=" %%f in ('type "%FAVORITES_FILE%" ^| fzf --prompt="Yeu thich: " --delimiter="|" --with-nth=1') do set "fav_sel=%%f"
    if "%fav_sel%"=="" goto :MainMenu

    for /f "tokens=1,2 delims=|" %%a in ("%fav_sel%") do (
        set "f_name=%%a"
        set "f_slug=%%b"
    )
    call :EpisodeMenu "%f_name%" "%f_slug%"
goto :MainMenu

:CutVideo
    cls
    echo === CAT VIDEO ===
    set "in_url=%~1"
    
    set /p "start_t=Thoi gian bat dau (00:10:30): "
    set /p "end_t=Thoi gian ket thuc (00:11:00): "
    
    :: Generate simple timestamp for filename
    set "timestamp=%TIME::=%"
    set "timestamp=%timestamp: =0%"
    set "timestamp=%timestamp:~0,6%"
    
    set "out_file=%DOWNLOAD_DIR%\cut\cut_%timestamp%.mp4"
    
    echo Dang xu ly...
    ffmpeg -i "%in_url%" -ss %start_t% -to %end_t% -c:v libx264 -preset fast -crf 23 -c:a aac "%out_file%" -hide_banner -loglevel error
    
    echo Xong: %out_file%
    pause
exit /b

:MergeVideo
    cls
    echo === GHEP VIDEO ===
    set "cut_path=%DOWNLOAD_DIR%\cut"
    if not exist "%cut_path%" ( echo Thu muc trong. & timeout /t 2 & exit /b )
    
    echo Chuyen vao: %cut_path%
    pushd "%cut_path%"
    
    :: List mp4 files into fzf -m
    :: Batch is tricky with multiselect FZF output. 
    :: Workaround: We ask user to merge ALL in folder or input specific names is too hard.
    echo Hien tai Batch chi ho tro ghep tat ca file .mp4 co trong thu muc Cut theo ten Alphabet.
    echo An bat ky phim nao de bat dau ghep...
    pause >nul
    
    (for %%i in (*.mp4) do @echo file '%%i') > mylist.txt
    
    set "timestamp=%TIME::=%"
    set "timestamp=%timestamp: =0%"
    set "merged_file=%DOWNLOAD_DIR%\merged\merged_%timestamp%.mp4"
    
    ffmpeg -f concat -safe 0 -i mylist.txt -c copy "%merged_file%" -hide_banner -loglevel error
    
    del mylist.txt
    popd
    echo Xong: %merged_file%
    pause
exit /b

:Settings
    cls
    echo === CAI DAT ===
    echo Hien tai:
    echo 1. Trinh phat: %PLAYER%
    echo 2. Thu muc tai: %DOWNLOAD_DIR%
    echo.
    echo Nhap '1' de doi Player, '2' de doi Folder, Enter de quay lai.
    set /p "s_opt=Lua chon: "
    
    if "%s_opt%"=="1" (
        set /p "p_new=Nhap lenh/duong dan file exe trinh phat: "
        if not "!p_new!"=="" (
             set "PLAYER=!p_new!"
             call :SaveConfig
        )
    )
    if "%s_opt%"=="2" (
        set /p "d_new=Nhap duong dan folder tuyet doi: "
        if not "!d_new!"=="" (
             set "DOWNLOAD_DIR=!d_new!"
             call :SaveConfig
        )
    )
goto :MainMenu
