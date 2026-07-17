@echo off
:: Check for administrative privileges
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo ====================================================
    echo ERROR: You must run this script as an Administrator!
    echo Right-click the file and select 'Run as administrator'.
    echo ====================================================
    pause
    exit /b
)

echo ====================================================
echo Starting System Maintenance ^& Optimization Script
echo ====================================================
echo.

:: 1. Software Updates
echo [STEP 1/6] Upgrading all applications via WinGet...
winget upgrade --all
echo.

:: 2. Network Interface Reset
echo [STEP 2/6] Releasing and renewing IP configurations...
ipconfig /release
ipconfig /renew
echo.

:: 3. DNS and IP Stack Reset
echo [STEP 3/6] Flushing DNS and resetting IP stack/Winsock...
ipconfig /flushdns
netsh winsock reset
netsh int ip reset
echo.

:: 4. System File Checker
echo [STEP 4/6] Scanning system files for corruption (SFC)...
sfc /scannow
echo.

:: 5. Deployment Image Servicing and Management
echo [STEP 5/6] Repairing Windows Image health (DISM)...
DISM /Online /Cleanup-Image /RestoreHealth
echo.

:: 6. Check Disk (Automated for next reboot)
echo [STEP 6/6] Scheduling Check Disk (chkdsk)...
echo Y | chkdsk /r
echo.
echo ====================================================
echo Maintenance Tasks Complete!
echo Note: A disk check has been scheduled for your next reboot.
echo Please restart your computer to finish the process.
echo ====================================================
pause