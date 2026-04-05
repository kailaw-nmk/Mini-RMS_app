@echo off
echo ========================================
echo  TailCall - Build + Install to Device
echo ========================================
echo.

cd /d C:\AI-dev\Mini-RMS_app\app

echo [1/4] flutter clean...
call C:\dev\flutter\bin\flutter clean

echo.
echo [2/4] flutter pub get...
call C:\dev\flutter\bin\flutter pub get

echo.
echo [3/4] flutter build apk --debug...
call C:\dev\flutter\bin\flutter build apk --debug

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo BUILD FAILED
    pause
    exit /b 1
)

echo.
echo [4/4] Installing to connected device...
adb install -r build\app\outputs\flutter-apk\app-debug.apk

if %ERRORLEVEL% EQU 0 (
    echo.
    echo ========================================
    echo  INSTALL SUCCESS - Launching app...
    echo ========================================
    adb shell am start -n com.tailcall.tailcall/.MainActivity
) else (
    echo.
    echo  INSTALL FAILED - Is device connected?
    echo  Run: adb devices
)

pause
