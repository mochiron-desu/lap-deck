@echo off
setlocal
title LapDeck OpenSSH Server Setup
echo ============================================================
echo   LapDeck Windows OpenSSH Server - One-Click Installer
echo ============================================================
echo.
echo Requesting Administrator privileges to install and configure OpenSSH...
echo If prompted by Windows User Account Control (UAC), click YES.
echo.

set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%install_openssh.ps1"

powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"\"%PS_SCRIPT%\"\"'"

if %ERRORLEVEL% equ 0 (
    echo [✓] Elevated installation window launched. Follow prompt in the new window.
) else (
    echo [!] Failed to launch elevated PowerShell. Please right-click install_openssh.ps1 and select 'Run with PowerShell'.
)
pause
