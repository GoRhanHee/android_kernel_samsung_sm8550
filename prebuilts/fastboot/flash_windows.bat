@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PLATFORM_TOOLS_CACHE=%SCRIPT_DIR%.platform-tools"
if not defined FASTBOOT set "FASTBOOT="
set "TOOL_ARCHIVE=%TEMP%\gorhanhee-platform-tools-%RANDOM%.zip"
set "GH_TOOL_ROOT=%PLATFORM_TOOLS_CACHE%"
set "GH_TOOL_ARCHIVE=%TOOL_ARCHIVE%"

if exist "%SCRIPT_DIR%platform-tools\fastboot.exe" set "FASTBOOT=%SCRIPT_DIR%platform-tools\fastboot.exe"
if not defined FASTBOOT if exist "%PLATFORM_TOOLS_CACHE%\platform-tools\fastboot.exe" set "FASTBOOT=%PLATFORM_TOOLS_CACHE%\platform-tools\fastboot.exe"
if not defined FASTBOOT for /f "delims=" %%F in ('where fastboot 2^>nul') do if not defined FASTBOOT set "FASTBOOT=%%F"

if not defined FASTBOOT call :install_platform_tools
if errorlevel 1 exit /b 1

call :flash_image boot boot.img
if errorlevel 1 exit /b 1
call :flash_image vendor_boot vendor_boot.img
if errorlevel 1 exit /b 1
call :flash_image vendor_dlkm vendor_dlkm.img
if errorlevel 1 exit /b 1
call :flash_image system_dlkm system_dlkm.img
if errorlevel 1 exit /b 1

echo All images flashed successfully; rebooting Android...
"%FASTBOOT%" reboot
if errorlevel 1 (
    echo [ERROR] Images were flashed, but the final reboot command failed.
    exit /b 1
)
exit /b 0

:install_platform_tools
echo fastboot was not found; downloading official Android platform-tools...
where powershell >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PowerShell is required to install platform-tools automatically.
    echo Install Android platform-tools manually and add fastboot.exe to PATH.
    exit /b 1
)
if not exist "%PLATFORM_TOOLS_CACHE%" mkdir "%PLATFORM_TOOLS_CACHE%"
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; $url = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'; $root = $env:GH_TOOL_ROOT; $archive = $env:GH_TOOL_ARCHIVE; New-Item -ItemType Directory -Force -Path $root | Out-Null; Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive; Expand-Archive -LiteralPath $archive -DestinationPath $root -Force; Remove-Item -LiteralPath $archive -Force"
if errorlevel 1 (
    echo [ERROR] Could not download or extract Android platform-tools.
    if exist "%TOOL_ARCHIVE%" del /q "%TOOL_ARCHIVE%"
    exit /b 1
)
if not exist "%PLATFORM_TOOLS_CACHE%\platform-tools\fastboot.exe" (
    echo [ERROR] fastboot.exe was not found after installing platform-tools.
    exit /b 1
)
set "FASTBOOT=%PLATFORM_TOOLS_CACHE%\platform-tools\fastboot.exe"
exit /b 0

:flash_image
set "PARTITION=%~1"
set "IMAGE=%~2"
if not exist "%SCRIPT_DIR%%IMAGE%" (
    echo [ERROR] Required image is missing: %IMAGE%
    exit /b 1
)
for %%A in ("%SCRIPT_DIR%%IMAGE%") do if %%~zA==0 (
    echo [ERROR] Required image is empty: %IMAGE%
    exit /b 1
)
echo Flashing %PARTITION%...
"%FASTBOOT%" flash "%PARTITION%" "%SCRIPT_DIR%%IMAGE%"
if errorlevel 1 (
    echo [ERROR] fastboot failed while flashing %PARTITION%.
    exit /b 1
)
exit /b 0
