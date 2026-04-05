@echo off
echo ========================================
echo  TailCall - APK Build (Debug)
echo ========================================
echo.

set APP_DIR=C:\AI-dev\Mini-RMS_app\app
set APK_DIR=C:\AI-dev\Mini-RMS_app\server\apk
set FLUTTER=C:\dev\flutter\bin\flutter

cd /d %APP_DIR%

echo [1/3] flutter clean...
call %FLUTTER% clean

echo.
echo [2/3] flutter pub get...
call %FLUTTER% pub get

echo.
echo [3/3] flutter build apk --debug...
call %FLUTTER% build apk --debug

if %ERRORLEVEL% EQU 0 (
    echo.
    echo Copying APK to server/apk/...
    copy /y "%APP_DIR%\build\app\outputs\flutter-apk\app-debug.apk" "%APK_DIR%\tailcall_debug_latest.apk"
    echo.
    echo ========================================
    echo  BUILD SUCCESS
    echo  APK: server\apk\tailcall_debug_latest.apk
    echo ========================================
) else (
    echo.
    echo ========================================
    echo  BUILD FAILED (exit code %ERRORLEVEL%)
    echo ========================================
)

pause
