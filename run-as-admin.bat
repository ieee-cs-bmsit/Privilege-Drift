@echo off
REM Privilege Drift - Run with Administrator Privileges
REM This script launches the PowerShell analysis with elevated permissions

echo ====================================================================
echo   Privilege Drift - Running with Administrator Privileges
echo ====================================================================
echo.

REM Check if already running as administrator
net session >nul 2>&1
if %errorLevel% == 0 (
    echo Already running as Administrator...
    goto :run
) else (
    echo Requesting Administrator privileges...
    echo.
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c cd /d ""%~dp0"" && run-as-admin.bat elevated' -Verb RunAs"
    exit
)

:run
cd /d "%~dp0"
if "%1"=="elevated" (
    echo.
    echo Running Privilege Drift analysis...
    echo.
    powershell.exe -ExecutionPolicy Bypass -File ".\run-analysis.ps1" %2 %3 %4 %5
    echo.
    echo ====================================================================
    echo   Analysis complete! Press any key to exit...
    echo ====================================================================
    pause >nul
) else (
    powershell.exe -ExecutionPolicy Bypass -File ".\run-analysis.ps1" %1 %2 %3 %4 %5
)
