@echo off
echo ========================================
echo  TailCall - Quick Build (no clean)
echo ========================================
echo.

cd /d C:\AI-dev\Mini-RMS_app\app

echo Building APK (debug, incremental)...
call C:\dev\flutter\bin\flutter build apk --debug

if %ERRORLEVEL% EQU 0 (
    echo.
    echo BUILD SUCCESS - Installing...
    adb install -r build\app\outputs\flutter-apk\app-debug.apk
    if %ERRORLEVEL% EQU 0 (
        echo INSTALLED - Launching...
        adb shell am start -n com.tailcall.tailcall/.MainActivity
    ) else (
        echo INSTALL FAILED - Is device connected?
    )
) else (
    echo BUILD FAILED
)

pause
