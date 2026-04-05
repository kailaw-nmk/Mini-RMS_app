@echo off
echo ========================================
echo  TailCall - Run All Tests
echo ========================================
echo.

echo [1/2] Server unit tests...
cd /d C:\AI-dev\Mini-RMS_app\server
call npm test
echo.

echo [2/2] Flutter unit tests...
cd /d C:\AI-dev\Mini-RMS_app\app
call C:\dev\flutter\bin\flutter test
echo.

echo ========================================
echo  Tests Complete
echo ========================================

pause
