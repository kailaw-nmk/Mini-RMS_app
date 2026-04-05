@echo off
echo ========================================
echo  TailCall - Build + Publish APK
echo ========================================
echo.

set APP_DIR=C:\AI-dev\Mini-RMS_app\app
set APK_DIR=C:\AI-dev\Mini-RMS_app\server\apk
set FLUTTER=C:\dev\flutter\bin\flutter

cd /d %APP_DIR%

echo [1/4] flutter pub get...
call %FLUTTER% pub get

echo.
echo [2/4] flutter build apk --debug...
call %FLUTTER% build apk --debug

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo BUILD FAILED
    pause
    exit /b 1
)

echo.
echo [3/4] Copying APK to server/apk/...
set APK_SRC=%APP_DIR%\build\app\outputs\flutter-apk\app-debug.apk

rem Generate filename with date
for /f "tokens=1-3 delims=/" %%a in ('echo %date:~0,10%') do set DATESTAMP=%%a%%b%%c
for /f "tokens=1-2 delims=:" %%a in ('echo %time:~0,5%') do set TIMESTAMP=%%a%%b
set TIMESTAMP=%TIMESTAMP: =0%
set APK_NAME=tailcall_debug_%DATESTAMP%_%TIMESTAMP%.apk

copy /y "%APK_SRC%" "%APK_DIR%\%APK_NAME%"

echo.
echo [4/4] Done!
echo ========================================
echo  APK: %APK_NAME%
echo  URL: https://tailcall.remotecomfy-uone.jp
echo ========================================
echo.
echo  ※ start-apk-server.bat でサーバーを起動してください
echo  ※ start-tunnel.bat でCloudflare Tunnelを起動してください

pause
