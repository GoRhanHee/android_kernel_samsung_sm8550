@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "SCRIPT_DIR=%~dp0"
set "PLATFORM_TOOLS_CACHE=%SCRIPT_DIR%.platform-tools"
set "REQUESTED_FASTBOOT=%FASTBOOT%"
set "FASTBOOT="
set "TOOL_ARCHIVE=%TEMP%\gorhanhee-platform-tools-%RANDOM%.zip"
set "GH_TOOL_ROOT=%PLATFORM_TOOLS_CACHE%"
set "GH_TOOL_ARCHIVE=%TOOL_ARCHIVE%"
set "RESULT=1"
set "ANDROID_SERIAL="

if defined REQUESTED_FASTBOOT if exist "%REQUESTED_FASTBOOT%" set "FASTBOOT=%REQUESTED_FASTBOOT%"
if defined REQUESTED_FASTBOOT if not defined FASTBOOT for /f "delims=" %%F in ('where "%REQUESTED_FASTBOOT%" 2^>nul') do if not defined FASTBOOT set "FASTBOOT=%%F"
if not defined FASTBOOT if exist "%SCRIPT_DIR%platform-tools\fastboot.exe" set "FASTBOOT=%SCRIPT_DIR%platform-tools\fastboot.exe"
if not defined FASTBOOT if exist "%PLATFORM_TOOLS_CACHE%\platform-tools\fastboot.exe" set "FASTBOOT=%PLATFORM_TOOLS_CACHE%\platform-tools\fastboot.exe"
if not defined FASTBOOT for /f "delims=" %%F in ('where fastboot.exe 2^>nul') do if not defined FASTBOOT set "FASTBOOT=%%F"

if defined FASTBOOT goto tools_ready
echo [INFO] fastboot was not found.
:download_prompt
set "ANSWER="
set /p "ANSWER=Download official Android platform-tools now? [Y/N] then press Enter: "
if /I "%ANSWER%"=="Y" goto download_approved
if /I "%ANSWER%"=="N" goto cancelled
echo [ERROR] Enter Y or N, then press Enter.
goto download_prompt

:download_approved
call :install_platform_tools
if errorlevel 1 goto failed

:tools_ready
if not defined FASTBOOT (
    echo [ERROR] fastboot is unavailable.
    goto failed
)

call :verify_images
if errorlevel 1 goto failed

set /a FASTBOOT_DEVICE_COUNT=0
echo [INFO] Checking for a fastboot device...
"%FASTBOOT%" devices
if errorlevel 1 goto failed
for /f "tokens=1" %%D in ('"%FASTBOOT%" devices 2^>nul') do set /a FASTBOOT_DEVICE_COUNT+=1
if !FASTBOOT_DEVICE_COUNT! EQU 0 (
    echo [ERROR] No fastboot device detected. Boot the phone into fastbootd first.
    goto failed
)
if !FASTBOOT_DEVICE_COUNT! GTR 1 (
    echo [ERROR] Multiple fastboot devices detected. Disconnect all but the target device.
    goto failed
)
set "FASTBOOT_USERSPACE="
for /f "tokens=1,2 delims=: " %%A in ('"%FASTBOOT%" getvar is-userspace 2^>^&1') do if /I "%%A"=="is-userspace" set "FASTBOOT_USERSPACE=%%B"
if /I not "%FASTBOOT_USERSPACE%"=="yes" (
    echo [ERROR] The device is not in fastbootd. Refusing to flash.
    echo [ERROR] Enter fastbootd and run this file again.
    goto failed
)

echo.
echo [INFO] fastboot: "%FASTBOOT%"
echo [INFO] image folder: "%SCRIPT_DIR%"
echo [INFO] device must already be in fastbootd.
echo [WARNING] This writes only boot, vendor_boot, vendor_dlkm, and system_dlkm.
:flash_prompt
set "ANSWER="
set /p "ANSWER=Continue flashing? [Y/N] then press Enter: "
if /I "%ANSWER%"=="Y" goto flash_approved
if /I "%ANSWER%"=="N" goto cancelled
echo [ERROR] Enter Y or N, then press Enter.
goto flash_prompt

:flash_approved
call :flash_image boot boot.img
if errorlevel 1 goto failed
call :flash_image vendor_boot vendor_boot.img
if errorlevel 1 goto failed
call :flash_image vendor_dlkm vendor_dlkm.img
if errorlevel 1 goto failed
call :flash_image system_dlkm system_dlkm.img
if errorlevel 1 goto failed

echo.
:reboot_prompt
set "ANSWER="
set /p "ANSWER=Reboot Android now? [Y/N] then press Enter: "
if /I "%ANSWER%"=="N" goto flashed_no_reboot
if /I "%ANSWER%"=="Y" goto reboot_approved
echo [ERROR] Enter Y or N, then press Enter.
goto reboot_prompt

:reboot_approved
"%FASTBOOT%" reboot
if errorlevel 1 (
    echo [ERROR] Images were flashed, but reboot failed.
    goto failed
)

:flashed_no_reboot
echo All requested images were flashed successfully.
set "RESULT=0"
goto done

:cancelled
echo [INFO] Cancelled. No image was flashed by this run.
set "RESULT=2"
goto done

:failed
echo [ERROR] The operation stopped before completion.
set "RESULT=1"

:done
echo.
if "%RESULT%"=="0" (
    echo Finished.
) else (
    echo Exit code: %RESULT%
)
pause
exit /b %RESULT%

:verify_images
call :check_image boot.img
if errorlevel 1 exit /b 1
call :check_image vendor_boot.img
if errorlevel 1 exit /b 1
call :check_image vendor_dlkm.img
if errorlevel 1 exit /b 1
call :check_image system_dlkm.img
if errorlevel 1 exit /b 1
exit /b 0

:check_image
if not exist "%SCRIPT_DIR%%~1" (
    echo [ERROR] Required image is missing: %~1
    exit /b 1
)
for %%A in ("%SCRIPT_DIR%%~1") do if %%~zA==0 (
    echo [ERROR] Required image is empty: %~1
    exit /b 1
)
if /I "%~1"=="boot.img" for %%A in ("%SCRIPT_DIR%%~1") do if %%~zA LSS 1048576 (
    echo [ERROR] boot.img is suspiciously small; refusing to flash it.
    exit /b 1
)
if /I "%~1"=="vendor_boot.img" for %%A in ("%SCRIPT_DIR%%~1") do if %%~zA LSS 1048576 (
    echo [ERROR] vendor_boot.img is suspiciously small; refusing to flash it.
    exit /b 1
)
exit /b 0

:install_platform_tools
echo [INFO] Downloading official Android platform-tools...
if not exist "%PLATFORM_TOOLS_CACHE%" mkdir "%PLATFORM_TOOLS_CACHE%"

where powershell >nul 2>&1
if not errorlevel 1 goto install_with_powershell

where curl.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PowerShell or curl.exe is required to install platform-tools.
    exit /b 1
)
where tar.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] tar.exe is required when PowerShell is unavailable.
    exit /b 1
)
curl.exe --fail --location --retry 3 --output "%TOOL_ARCHIVE%" "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"
if errorlevel 1 (
    echo [ERROR] Could not download Android platform-tools with curl.exe.
    if exist "%TOOL_ARCHIVE%" del /q "%TOOL_ARCHIVE%"
    exit /b 1
)
tar.exe -xf "%TOOL_ARCHIVE%" -C "%PLATFORM_TOOLS_CACHE%"
if errorlevel 1 (
    echo [ERROR] Could not extract Android platform-tools with tar.exe.
    if exist "%TOOL_ARCHIVE%" del /q "%TOOL_ARCHIVE%"
    exit /b 1
)
if exist "%TOOL_ARCHIVE%" del /q "%TOOL_ARCHIVE%"
goto verify_platform_tools

:install_with_powershell
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
  "$ErrorActionPreference = 'Stop'; $url = 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip'; $root = $env:GH_TOOL_ROOT; $archive = $env:GH_TOOL_ARCHIVE; New-Item -ItemType Directory -Force -Path $root | Out-Null; Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $archive; Expand-Archive -LiteralPath $archive -DestinationPath $root -Force; Remove-Item -LiteralPath $archive -Force"
if errorlevel 1 (
    echo [ERROR] Could not download or extract Android platform-tools with PowerShell.
    if exist "%TOOL_ARCHIVE%" del /q "%TOOL_ARCHIVE%"
    exit /b 1
)

:verify_platform_tools
if not exist "%PLATFORM_TOOLS_CACHE%\platform-tools\fastboot.exe" (
    echo [ERROR] fastboot.exe was not found after installing platform-tools.
    exit /b 1
)
set "FASTBOOT=%PLATFORM_TOOLS_CACHE%\platform-tools\fastboot.exe"
exit /b 0

:flash_image
set "PARTITION=%~1"
set "IMAGE=%~2"
echo Flashing %PARTITION%...
"%FASTBOOT%" flash "%PARTITION%" "%SCRIPT_DIR%%IMAGE%"
if errorlevel 1 (
    echo [ERROR] fastboot failed while flashing %PARTITION%.
    exit /b 1
)
exit /b 0
