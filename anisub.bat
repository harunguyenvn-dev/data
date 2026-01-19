@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul

:: --- CẤU HÌNH & DATA ---
set "USER_HOME=%USERPROFILE%"
set "CONFIG_DIR=%USER_HOME%\.config\anisub_cli"
set "CONFIG_FILE=%CONFIG_DIR%\config.cfg"
set "HISTORY_FILE=%CONFIG_DIR%\history.log"
set "FAVORITES_FILE=%CONFIG_DIR%\favorites.txt"
set "TEMP_JSON=%TEMP%\anisub_temp.json"
set "TEMP_LIST=%TEMP%\anisub_list.txt"

:: File Local Data
set "SCRIPT_DIR=%~dp0"
set "LOCAL_DATA_FILE=%SCRIPT_DIR%assets\aniw_export_2026-01-14.csv"

:: --- MẶC ĐỊNH ---
set "DEFAULT_PLAYER=mpv"
set "DEFAULT_DOWNLOAD_DIR=%USER_HOME%\Downloads\anime"
set "PLAYER="
set "DOWNLOAD_DIR="

:: Khởi tạo cấu hình khi chạy
call :ensure_config_dir
call :load_config

:: Kiểm tra công cụ cần thiết
call :check_dependencies
if errorlevel 1 goto :eof

:MAIN_MENU
cls
echo =======================================================
echo               ANISUB CLI (WINDOWS EDITION)
echo =======================================================
echo [1] Tim kiem Anime (KKPhim API)
echo [2] Xem tu Local Anidata
echo [3] Lich su xem
echo [4] Danh sach yeu thich
echo [5] Cai dat
echo [6] Thoat
echo =======================================================
set /p "OPT=Chon chuc nang (1-6): "

if "%OPT%"=="1" goto :SEARCH_API
if "%OPT%"=="2" goto :LOCAL_ANIDATA
if "%OPT%"=="3" goto :HISTORY_MENU
if "%OPT%"=="4" goto :FAVORITES_MENU
if "%OPT%"=="5" goto :SETTINGS_MENU
if "%OPT%"=="6" goto :eof
goto :MAIN_MENU

:: --- CHỨC NĂNG TÌM KIẾM API ---
:SEARCH_API
set /p "KEYWORD=Nhap ten anime can tim: "
if "%KEYWORD%"=="" goto :MAIN_MENU

:: URL Encode đơn giản (thay khoảng trắng bằng %20)
set "KEYWORD_ENC=%KEYWORD: =%20%"
echo Dang tim kiem...

:: Gọi API và lưu vào file tạm
curl -s "https://phimapi.com/v1/api/tim-kiem?keyword=%KEYWORD_ENC%&limit=20" > "%TEMP_JSON%"

:: Kiểm tra status
for /f "tokens=*" %%a in ('jq -r ".status" "%TEMP_JSON%"') do set "API_STATUS=%%a"
if "%API_STATUS%" neq "success" (
    echo Khong tim thay phim hoac loi API.
    pause
    goto :MAIN_MENU
)

:: Xử lý dữ liệu tìm kiếm bằng jq và đưa vào fzf
:: Format hiển thị: Name (Year)|Slug
jq -r ".data.items[] | \"\(.name) (\(.year))^|^\(.slug)\"" "%TEMP_JSON%" > "%TEMP_LIST%"

set "SELECTED_ANIME="
for /f "delims=" %%i in ('type "%TEMP_LIST%" ^| fzf --prompt="Ket qua > " --delimiter="|" --with-nth=1') do set "SELECTED_ANIME=%%i"

if "%SELECTED_ANIME%"=="" goto :MAIN_MENU

:: Tách lấy tên và slug
for /f "tokens=1,2 delims=|" %%a in ("%SELECTED_ANIME%") do (
    set "ANIME_NAME=%%a"
    set "ANIME_SLUG=%%b"
)

echo Dang tai danh sach tap phim...
curl -s "https://phimapi.com/phim/%ANIME_SLUG%" > "%TEMP_JSON%"

:: Lấy danh sách tập: TapName|Link
jq -r ".episodes[0].server_data[] | \"\(.name)^|^\(.link_m3u8)\"" "%TEMP_JSON%" > "%TEMP_LIST%"

:: Menu chọn tập và hành động
:EPISODE_LOOP_API
set "SELECTED_EP="
for /f "delims=" %%i in ('type "%TEMP_LIST%" ^| fzf --prompt="Chon tap > " --delimiter="|" --with-nth=1') do set "SELECTED_EP=%%i"

if "%SELECTED_EP%"=="" goto :MAIN_MENU

for /f "tokens=1,2 delims=|" %%a in ("%SELECTED_EP%") do (
    set "EP_NAME=%%a"
    set "EP_LINK=%%b"
)

:: Lưu lịch sử
call :add_to_history "%ANIME_NAME%" "%EP_NAME%" "%EP_LINK%"
call :manage_playing "%ANIME_NAME%" "%EP_NAME%" "%EP_LINK%" "%TEMP_LIST%" "%ANIME_SLUG%"

goto :MAIN_MENU

:: --- CHỨC NĂNG LOCAL ---
:LOCAL_ANIDATA
echo Dang kiem tra du lieu: %LOCAL_DATA_FILE%
if not exist "%LOCAL_DATA_FILE%" (
    echo File du lieu khong ton tai. Dang tai xuong...
    if not exist "%SCRIPT_DIR%assets" mkdir "%SCRIPT_DIR%assets"
    curl -L "https://raw.githubusercontent.com/NiyakiPham/anisub/refs/heads/main/assets/aniw_export_2026-01-14.csv" -o "%LOCAL_DATA_FILE%"
    if not exist "%LOCAL_DATA_FILE%" (
        echo Loi tai du lieu.
        pause
        goto :MAIN_MENU
    )
    echo Da tai du lieu.
)

:: Tạo danh sách anime từ CSV (giả lập awk bằng powershell cho nhanh và ổn định)
powershell -Command "Import-Csv -Path '%LOCAL_DATA_FILE%' -Header Col1,Col2,Col3,Col4,Col5 | Select-Object -ExpandProperty Col1 | Select-Object -Unique | Out-File -Encoding utf8 '%TEMP_LIST%'"

set "SEL_LOCAL="
for /f "delims=" %%i in ('type "%TEMP_LIST%" ^| fzf --prompt="[Local] Chon Anime: "') do set "SEL_LOCAL=%%i"
if "%SEL_LOCAL%"=="" goto :MAIN_MENU

:: Lọc tập phim của anime đã chọn
powershell -Command "Import-Csv -Path '%LOCAL_DATA_FILE%' -Header Name,Ep,Date,Link,Extra | Where-Object { $_.Name -eq '%SEL_LOCAL%' } | ForEach-Object { \"Tap \" + $_.Ep + \"|\" + $_.Link } | Out-File -Encoding utf8 '%TEMP_LIST%'"

set "SEL_EP_LOCAL="
for /f "delims=" %%i in ('type "%TEMP_LIST%" ^| fzf --prompt="Chon tap > " --delimiter="|" --with-nth=1') do set "SEL_EP_LOCAL=%%i"

if "%SEL_EP_LOCAL%"=="" goto :MAIN_MENU

for /f "tokens=1,2 delims=|" %%a in ("%SEL_EP_LOCAL%") do (
    set "LEP_NAME=%%a"
    set "LEP_LINK=%%b"
)
:: Trim khoảng trắng trong link nếu có
set "LEP_LINK=%LEP_LINK: =%"

call :add_to_history "%SEL_LOCAL% (Local)" "%LEP_NAME%" "%LEP_LINK%"
call :manage_playing "%SEL_LOCAL%" "%LEP_NAME%" "%LEP_LINK%" "%TEMP_LIST%" "local_file"

goto :MAIN_MENU


:: --- MENU QUẢN LÝ PLAYER ---
:manage_playing
set "MP_NAME=%~1"
set "MP_EP=%~2"
set "MP_LINK=%~3"
set "MP_LIST=%~4"
set "MP_SLUG=%~5"

:: Bắt đầu phát
start "" "%PLAYER%" "%MP_LINK%" --title="Anisub: %MP_NAME% - %MP_EP%"

:CONTROL_LOOP
cls
echo Dang phat: %MP_NAME% - Tap %MP_EP%
echo (Trinh phat dang chay cua so rieng)
echo.
echo [1] Phat tap tiep theo (Neu co trong danh sach)
echo [2] Chon tap khac trong danh sach
echo [3] Tai xuong tap nay
echo [4] Cat Video (1 lan)
echo [5] Ghep Video (Merge)
echo [6] Them vao Yeu Thich
echo [0] Quay lai Menu chinh
echo.
set /p "ACT=Chon hanh dong: "

if "%ACT%"=="1" (
    :: Logic tự tìm tập kế tiếp hơi phức tạp trong batch, 
    :: ta sẽ mở lại list cho user chọn nhanh
    goto :RESELECT_IN_CONTROL
)
if "%ACT%"=="2" goto :RESELECT_IN_CONTROL
if "%ACT%"=="3" (
    echo Dang tai xuong nen...
    start /b "" call :download_video "%MP_LINK%" "%MP_NAME% - %MP_EP%"
    timeout /t 2 >nul
    goto :CONTROL_LOOP
)
if "%ACT%"=="4" (
    call :cut_video_logic "%MP_LINK%"
    goto :CONTROL_LOOP
)
if "%ACT%"=="5" (
    call :merge_video_logic
    goto :CONTROL_LOOP
)
if "%ACT%"=="6" (
    call :add_favorite "%MP_NAME%" "%MP_SLUG%"
    goto :CONTROL_LOOP
)
if "%ACT%"=="0" exit /b 0

goto :CONTROL_LOOP

:RESELECT_IN_CONTROL
set "NEW_SEL="
for /f "delims=" %%i in ('type "%MP_LIST%" ^| fzf --prompt="Chon tap khac: " --delimiter="|" --with-nth=1') do set "NEW_SEL=%%i"
if "%NEW_SEL%"=="" goto :CONTROL_LOOP
for /f "tokens=1,2 delims=|" %%a in ("%NEW_SEL%") do (
    set "MP_EP=%%a"
    set "MP_LINK=%%b"
)
call :add_to_history "%MP_NAME%" "%MP_EP%" "%MP_LINK%"
start "" "%PLAYER%" "%MP_LINK%" --title="Anisub: %MP_NAME% - %MP_EP%"
goto :CONTROL_LOOP


:: --- LỊCH SỬ & YÊU THÍCH ---
:HISTORY_MENU
if not exist "%HISTORY_FILE%" (
    echo Lich su trong.
    pause
    goto :MAIN_MENU
)
:: Đảo ngược file (để xem cái mới nhất) và chọn
set "HIST_SEL="
powershell -Command "Get-Content '%HISTORY_FILE%' | Select-Object -Last 50 | [Collections.ArrayList]::new() | ForEach-Object { $a=$_; } { [void]$_.Insert(0,$a) } { $_ } | Out-File -Encoding utf8 '%TEMP_LIST%'"
for /f "delims=" %%i in ('type "%TEMP_LIST%" ^| fzf --prompt="Lich su > " --delimiter="|" --with-nth=1,2,3') do set "HIST_SEL=%%i"

if "%HIST_SEL%"=="" goto :MAIN_MENU
for /f "tokens=1,2,3,4 delims=|" %%a in ("%HIST_SEL%") do (
    set "H_NAME=%%b"
    set "H_EP=%%c"
    set "H_LINK=%%d"
)
echo Phat lai: %H_NAME% - %H_EP%
start "" "%PLAYER%" "%H_LINK%" --title="Anisub: %H_NAME%"
goto :MAIN_MENU

:FAVORITES_MENU
if not exist "%FAVORITES_FILE%" (
    echo Chua co Anime yeu thich.
    pause
    goto :MAIN_MENU
)
set "FAV_SEL="
for /f "delims=" %%i in ('type "%FAVORITES_FILE%" ^| fzf --prompt="Yeu thich > " --delimiter="|" --with-nth=1') do set "FAV_SEL=%%i"
if "%FAV_SEL%"=="" goto :MAIN_MENU

for /f "tokens=1,2 delims=|" %%a in ("%FAV_SEL%") do (
    set "F_NAME=%%a"
    set "F_SLUG=%%b"
)
:: Load lại tập phim từ slug yêu thích
echo Dang lay du lieu cho: %F_NAME%...
curl -s "https://phimapi.com/phim/%F_SLUG%" > "%TEMP_JSON%"
jq -r ".episodes[0].server_data[] | \"\(.name)^|^\(.link_m3u8)\"" "%TEMP_JSON%" > "%TEMP_LIST%"
call :manage_playing "%F_NAME%" "Tap Fav" "" "%TEMP_LIST%" "%F_SLUG%"
goto :MAIN_MENU

:add_favorite
set "FNAME=%~1"
set "FSLUG=%~2"
findstr /C:"|%FSLUG%" "%FAVORITES_FILE%" >nul
if %errorlevel%==0 (
    echo Anime nay da co trong Yeu Thich.
) else (
    echo %FNAME%^|%FSLUG%>> "%FAVORITES_FILE%"
    echo Da them vao Yeu Thich.
)
timeout /t 1 >nul
exit /b

:: --- DOWNLOAD & CUTTING ---
:download_video
set "DL_URL=%~1"
set "DL_NAME=%~2"
set "SAFE_NAME=%DL_NAME:/=-%"
set "SAFE_NAME=%SAFE_NAME:\=-%"
set "SAFE_NAME=%SAFE_NAME::=-%"

:: Tạo thư mục tải
set "DL_PATH=%DOWNLOAD_DIR%\%SAFE_NAME%"
if not exist "%DL_PATH%" mkdir "%DL_PATH%"

echo [DOWNLOAD] Bat dau tai: %SAFE_NAME%...
where yt-dlp >nul 2>&1
if %errorlevel%==0 (
    yt-dlp "%DL_URL%" -o "%DL_PATH%\%SAFE_NAME%.mp4"
) else (
    ffmpeg -i "%DL_URL%" -c copy -bsf:a aac_adtstoasc "%DL_PATH%\%SAFE_NAME%.mp4"
)
echo [DOWNLOAD] Hoan tat.
exit /b

:cut_video_logic
set "CUT_LINK=%~1"
set "CUT_DIR=%DOWNLOAD_DIR%\cut"
if not exist "%CUT_DIR%" mkdir "%CUT_DIR%"

echo === CHE DO CAT VIDEO ===
echo Nhap thoi gian bat dau (VD: 00:10:30)
set /p "START_TIME=> "
echo Nhap thoi gian ket thuc (VD: 00:11:00)
set /p "END_TIME=> "

set "OUT_NAME=cut_%random%.mp4"
echo Dang xu ly...
ffmpeg -i "%CUT_LINK%" -ss "%START_TIME%" -to "%END_TIME%" -c:v libx264 -preset fast -crf 23 -c:a aac "%CUT_DIR%\%OUT_NAME%" -y -hide_banner -loglevel error

echo Xong. File tai: %CUT_DIR%\%OUT_NAME%
pause
exit /b

:merge_video_logic
set "CUT_DIR=%DOWNLOAD_DIR%\cut"
set "MERGE_DIR=%DOWNLOAD_DIR%\merged"
if not exist "%MERGE_DIR%" mkdir "%MERGE_DIR%"

:: Tạo file list.txt cho ffmpeg
set "LIST_TXT=%CUT_DIR%\files.txt"
if exist "%LIST_TXT%" del "%LIST_TXT%"

echo Chon cac file can ghep trong %CUT_DIR%:
echo (Giai phap: Tat ca file .mp4 trong folder 'cut' se duoc ghep lai theo ten)
echo An Enter de ghep toan bo, hoac Ctrl+C de huy.
pause

dir /b /on "%CUT_DIR%\*.mp4" > "%TEMP_LIST%"
for /f "tokens=*" %%F in (%TEMP_LIST%) do (
    echo file '%CUT_DIR%\%%F'>> "%LIST_TXT%"
)

set "OUT_NAME=merged_%random%.mp4"
echo Dang ghep video...
ffmpeg -f concat -safe 0 -i "%LIST_TXT%" -c copy "%MERGE_DIR%\%OUT_NAME%" -y -hide_banner -loglevel error
echo Hoan tat: %MERGE_DIR%\%OUT_NAME%
pause
exit /b

:: --- TIỆN ÍCH ---
:add_to_history
:: Arg 1: Name, Arg 2: Ep, Arg 3: Link
for /f "tokens=2 delims==" %%I in ('wmic os get localdatetime /value') do set datetime=%%I
set "TIMESTAMP=%datetime:~0,4%-%datetime:~4,2%-%datetime:~6,2% %datetime:~8,2%:%datetime:~10,2%:%datetime:~12,2%"
echo %TIMESTAMP%^|%~1^|%~2^|%~3>> "%HISTORY_FILE%"
exit /b

:check_dependencies
set "MISSING=0"
where ffmpeg >nul 2>&1 || (echo Thieu ffmpeg & set MISSING=1)
where yt-dlp >nul 2>&1 || (echo Thieu yt-dlp & set MISSING=1)
where jq >nul 2>&1 || (echo Thieu jq & set MISSING=1)
where fzf >nul 2>&1 || (echo Thieu fzf & set MISSING=1)
where curl >nul 2>&1 || (echo Thieu curl & set MISSING=1)
if "%MISSING%"=="1" (
    echo.
    echo LOI: Vui long cai dat cac cong cu tren (Googling: install ffmpeg/jq/fzf windows)
    echo Goc y: Su dung 'Scoop' hoac 'Chocolatey' de cai dat de dang.
    pause
    exit /b 1
)
exit /b 0

:ensure_config_dir
if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if not exist "%HISTORY_FILE%" type nul > "%HISTORY_FILE%"
if not exist "%FAVORITES_FILE%" type nul > "%FAVORITES_FILE%"
exit /b

:load_config
if not exist "%CONFIG_FILE%" (
    echo PLAYER=%DEFAULT_PLAYER%> "%CONFIG_FILE%"
    echo DOWNLOAD_DIR=%DEFAULT_DOWNLOAD_DIR%>> "%CONFIG_FILE%"
)
for /f "tokens=1,2 delims==" %%a in (%CONFIG_FILE%) do (
    set "%%a=%%b"
)
if not exist "%DOWNLOAD_DIR%" mkdir "%DOWNLOAD_DIR%"
exit /b

:SETTINGS_MENU
cls
echo === CAI DAT ===
echo [1] Doi trinh phat (Hien tai: %PLAYER%)
echo [2] Doi thu muc tai (Hien tai: %DOWNLOAD_DIR%)
echo [0] Quay lai
set /p "SET_OPT=Chon: "
if "%SET_OPT%"=="1" (
    set /p "PLAYER=Nhap ten lenh trinh phat moi (vd: vlc): "
    goto :SAVE_CFG
)
if "%SET_OPT%"=="2" (
    set /p "DOWNLOAD_DIR=Nhap duong dan (tuyet doi): "
    goto :SAVE_CFG
)
if "%SET_OPT%"=="0" goto :MAIN_MENU
goto :SETTINGS_MENU

:SAVE_CFG
echo PLAYER=%PLAYER%> "%CONFIG_FILE%"
echo DOWNLOAD_DIR=%DOWNLOAD_DIR%>> "%CONFIG_FILE%"
echo Da luu cau hinh.
timeout /t 1 >nul
goto :SETTINGS_MENU
