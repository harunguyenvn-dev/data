@echo off
setlocal EnableDelayedExpansion
title Anisub CLI - Windows Edition
chcp 65001 >nul

:: --- CONFIGURATION ---
set "CONFIG_DIR=%USERPROFILE%\.config\anisub_cli"
set "CONFIG_FILE=%CONFIG_DIR%\config.cfg"
set "HISTORY_FILE=%CONFIG_DIR%\history.log"
set "FAVORITES_FILE=%CONFIG_DIR%\favorites.txt"

:: Thư mục lưu dữ liệu tạm
set "TEMP_DIR=%TEMP%\anisub_temp"
if not exist "%TEMP_DIR%" mkdir "%TEMP_DIR%"

:: --- DEFAULTS ---
set "DEFAULT_PLAYER=mpv"
set "DEFAULT_DOWNLOAD_DIR=%USERPROFILE%\Downloads\anime"

:: --- INITIALIZATION ---
call :check_dependencies
if errorlevel 1 goto :eof
call :load_config

:main_menu
cls
echo ==============================================
echo             ANISUB CLI (WINDOWS)
echo ==============================================
echo [1] Tim kiem Anime (KKPhim API)
echo [2] Lich su xem
echo [3] Danh sach yeu thich
echo [4] Cai dat
echo [Q] Thoat
echo ==============================================
set "main_opt="
set /p "main_opt=Chon chuc nang (1,2,3,4,Q): "

if /i "%main_opt%"=="1" goto :search_kkphim
if /i "%main_opt%"=="2" goto :show_history
if /i "%main_opt%"=="3" goto :show_favorites
if /i "%main_opt%"=="4" goto :show_settings
if /i "%main_opt%"=="Q" goto :eof
goto :main_menu

:: --- 1. SEARCH FUNCTION ---
:search_kkphim
cls
echo [TIM KIEM ANIME]
set /p "keyword=Nhap ten anime (Bo trong de quay lai): "
if "%keyword%"=="" goto :main_menu

echo Dang tim kiem "%keyword%"...
:: Encode URI (Basic text replace space with %20)
set "safe_keyword=%keyword: =%20%"
set "api_url=https://phimapi.com/v1/api/tim-kiem?keyword=!safe_keyword!&limit=50"

curl -s "%api_url%" > "%TEMP_DIR%\search_result.json"

:: Kiem tra status
jq -r ".status" "%TEMP_DIR%\search_result.json" > "%TEMP_DIR%\status.tmp"
set /p status=<"%TEMP_DIR%\status.tmp"
if not "!status!"=="success" (
    echo Khong tim thay phim hoac loi API.
    pause
    goto :main_menu
)

:: Lay danh sach phim de hien thi trong fzf
jq -r ".data.items[] | \"\(.name) (\(.year)) | \(.slug)\"" "%TEMP_DIR%\search_result.json" > "%TEMP_DIR%\fzf_list.txt"

:: Hien thi FZF
set "selected="
for /f "delims=" %%i in ('type "%TEMP_DIR%\fzf_list.txt" ^| fzf --prompt="Ket qua > "') do set "selected=%%i"

if "%selected%"=="" goto :main_menu

:: Tach lay ten va slug (dung delimiters |)
for /f "tokens=1,2 delims=|" %%a in ("%selected%") do (
    set "anime_name=%%a"
    set "anime_slug=%%b"
)
:: Trim space (xoa khoang trang du thua)
set "anime_name=%anime_name:~0,-1%"
set "anime_slug=%anime_slug:~1%"

goto :get_episodes

:: --- 2. GET EPISODES & PLAY MENU ---
:get_episodes
echo Dang tai danh sach tap cho: !anime_name!...
curl -s "https://phimapi.com/phim/!anime_slug!" > "%TEMP_DIR%\episodes.json"

jq -r ".status" "%TEMP_DIR%\episodes.json" > "%TEMP_DIR%\status_ep.tmp"
set /p status_ep=<"%TEMP_DIR%\status_ep.tmp"

if "!status_ep!"=="false" (
    echo Loi lay danh sach tap.
    pause
    goto :main_menu
)

:: Tao danh sach tap (Lay server dau tien)
jq -r ".episodes[0].server_data[] | \"\(.name) | \(.link_m3u8)\"" "%TEMP_DIR%\episodes.json" > "%TEMP_DIR%\ep_list.txt"

:select_episode
set "selected_ep="
for /f "delims=" %%j in ('type "%TEMP_DIR%\ep_list.txt" ^| fzf --prompt="Chon tap phim > "') do set "selected_ep=%%j"

if "%selected_ep%"=="" goto :main_menu

:: Tach lay ten tap va link
for /f "tokens=1,2 delims=|" %%x in ("%selected_ep%") do (
    set "ep_name=%%x"
    set "ep_link=%%y"
)
set "ep_name=%ep_name:~0,-1%"
set "ep_link=%ep_link:~1%"

:: Luu lich su
call :add_history "!anime_name!" "!ep_name!" "!ep_link!"
call :play_actions "!anime_name!" "!ep_name!" "!ep_link!"

goto :select_episode


:: --- PLAY & ACTIONS HANDLER ---
:play_actions
set "curr_anime=%~1"
set "curr_ep=%~2"
set "curr_link=%~3"

:: Chay trinh phat (Khong cho terminal de khong bi treo)
start "" "!PLAYER!" "!curr_link!" --force-window --title="Anisub: !curr_anime! - Tap !curr_ep!"

:action_loop
cls
echo Dang phat: !curr_anime! - Tap !curr_ep!
echo ------------------------------------------
echo [1] Tai tap phim nay
echo [2] Cat video (ffmpeg)
echo [3] Them vao yeu thich
echo [4] Quay lai chon tap khac
echo ------------------------------------------
set /p "act=Chon tac vu (de trong de quay lai menu chinh): "

if "%act%"=="" goto :eof
if "%act%"=="4" goto :eof
if "%act%"=="1" call :download_video "!curr_link!" "!curr_anime! - Tap !curr_ep!"
if "%act%"=="2" call :cut_video "!curr_link!"
if "%act%"=="3" call :add_favorite "!curr_anime!" "!anime_slug!"

goto :action_loop

:: --- FEATURES FUNCTIONS ---

:download_video
set "dl_url=%~1"
set "dl_name=%~2"
:: Lam sach ten file (xoa ky tu dac biet)
set "dl_name=!dl_name::=-!"
set "dl_name=!dl_name:/=_!"
set "dl_folder=!DOWNLOAD_DIR!\!dl_name!"

if not exist "!dl_folder!" mkdir "!dl_folder!"

echo Dang tai xuong: !dl_name!...
:: Uu tien yt-dlp neu co, khong thi ffmpeg
where yt-dlp >nul 2>nul
if %errorlevel% equ 0 (
    start cmd /k yt-dlp "!dl_url!" -o "!dl_folder!\!dl_name!.mp4"
) else (
    start cmd /k ffmpeg -i "!dl_url!" -c copy -bsf:a aac_adtstoasc "!dl_folder!\!dl_name!.mp4"
)
exit /b

:cut_video
set "vid_url=%~1"
set "cut_dir=!DOWNLOAD_DIR!\cut"
if not exist "!cut_dir!" mkdir "!cut_dir!"

echo === CAT VIDEO (DANG M02 RE-ENCODE) ===
set /p "start_time=Thoi gian bat dau (00:00:00): "
set /p "end_time=Thoi gian ket thuc (00:00:00): "
set "out_file=cut_%random%.mp4"

echo Dang xu ly... Vui long doi cuaso ffmpeg...
start cmd /k ffmpeg -i "!vid_url!" -ss !start_time! -to !end_time! -c:v libx264 -preset fast -crf 23 -c:a aac "!cut_dir!\!out_file!"
exit /b

:add_favorite
set "fav_name=%~1"
set "fav_slug=%~2"
echo !fav_name!^|!fav_slug!>> "%FAVORITES_FILE%"
echo Da them vao yeu thich.
timeout /t 1 >nul
exit /b

:show_favorites
if not exist "%FAVORITES_FILE%" (
    echo Danh sach yeu thich trong.
    pause
    goto :main_menu
)
set "sel_fav="
for /f "delims=" %%k in ('type "%FAVORITES_FILE%" ^| fzf --prompt="Yeu thich > "') do set "sel_fav=%%k"
if "%sel_fav%"=="" goto :main_menu

for /f "tokens=1,2 delims=|" %%m in ("%sel_fav%") do (
    set "anime_name=%%m"
    set "anime_slug=%%n"
)
goto :get_episodes

:show_history
if not exist "%HISTORY_FILE%" (
    echo Lich su trong.
    pause
    goto :main_menu
)
:: Windows khong co 'tac', nen doc truc tiep tu tren xuong (cu -> moi)
set "sel_hist="
for /f "delims=" %%h in ('type "%HISTORY_FILE%" ^| fzf --prompt="Lich su > "') do set "sel_hist=%%h"
if "%sel_hist%"=="" goto :main_menu

for /f "tokens=1,2,3,4 delims=|" %%a in ("%sel_hist%") do (
    set "h_name=%%b"
    set "h_ep=%%c"
    set "h_link=%%d"
)
:: Clean link (xoa khoang trang du neu co)
set "h_link=%h_link: =%"
call :play_actions "!h_name!" "!h_ep!" "!h_link!"
goto :main_menu

:add_history
set "log_time=%date% %time%"
set "line=!log_time!|%~1|%~2|%~3"
echo !line!>> "%HISTORY_FILE%"
exit /b


:: --- CONFIGURATION & DEPENDENCY CHECKS ---
:check_dependencies
set "missing="
where ffmpeg >nul 2>nul || set "missing=!missing! ffmpeg"
where curl >nul 2>nul || set "missing=!missing! curl"
where fzf >nul 2>nul || set "missing=!missing! fzf"
where jq >nul 2>nul || set "missing=!missing! jq"

if not "!missing!"=="" (
    cls
    echo [ERROR] Thieu cac cong cu can thiet de chay script:
    echo ----------------------------------------------------
    echo Cac phan mem bi thieu: !missing!
    echo ----------------------------------------------------
    echo [Giai phap] Cai dat bang Scoop (Recommended):
    echo     scoop install ffmpeg curl fzf jq yt-dlp mpv
    echo.
    echo Hoac cai dat thu cong va them vao PATH cua Windows.
    echo Script se thoat.
    pause
    exit /b 1
)
exit /b 0

:load_config
if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if not exist "%CONFIG_FILE%" (
    echo PLAYER=%DEFAULT_PLAYER%> "%CONFIG_FILE%"
    echo DOWNLOAD_DIR=%DEFAULT_DOWNLOAD_DIR%>> "%CONFIG_FILE%"
)
for /f "tokens=1,2 delims==" %%A in (%CONFIG_FILE%) do (
    set "%%A=%%B"
)
if not exist "!DOWNLOAD_DIR!" mkdir "!DOWNLOAD_DIR!"
exit /b

:show_settings
cls
echo [CAI DAT]
echo 1. Trinh phat video hien tai: !PLAYER!
echo 2. Thu muc tai xuong hien tai: !DOWNLOAD_DIR!
echo 3. Quay lai
echo.
set /p "sett=Chon muc can thay doi (1,2,3): "
if "%sett%"=="1" (
    set /p "new_player=Nhap lenh/ten trinh phat (vd: vlc, mpv): "
    set "PLAYER=!new_player!"
    call :save_config
    goto :show_settings
)
if "%sett%"=="2" (
    set /p "new_dir=Nhap duong dan folder tai xuong: "
    set "DOWNLOAD_DIR=!new_dir!"
    if not exist "!DOWNLOAD_DIR!" mkdir "!DOWNLOAD_DIR!"
    call :save_config
    goto :show_settings
)
if "%sett%"=="3" goto :main_menu
goto :show_settings

:save_config
(
echo PLAYER=!PLAYER!
echo DOWNLOAD_DIR=!DOWNLOAD_DIR!
) > "%CONFIG_FILE%"
echo Da luu cau hinh!
timeout /t 1 >nul
exit /b
