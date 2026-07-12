@echo off
setlocal enabledelayedexpansion
title CAT-INSTALLER-JDK 0.1 (CFA-PROOF SAFE MODE)

set "PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"

:: ============================================================
:: AUTO-ELEVATION CHECK
:: ============================================================
>nul 2>&1 net session
if errorlevel 1 (
    echo.
    echo ============================================
    echo   CAT-INSTALLER-JDK 0.1 REQUIRES ADMIN
    echo ============================================
    echo.
    echo Relaunching with Administrator privileges...
    "%PS%" -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

echo ============================================
echo        CAT-INSTALLER-JDK 0.1 (SAFE MODE)
echo   Temurin OpenJDK 21 LTS for Windows 11
echo        Built for Catsan Dev Environments
echo ============================================
echo.

REM ---- Detect architecture ----
echo Detecting system architecture...
set "ARCH=x64"
if /i "%PROCESSOR_ARCHITECTURE%"=="ARM64" set "ARCH=aarch64"
echo Architecture: %ARCH%
echo.

REM ---- Resolve latest MSI URL from Adoptium API ----
set "JDK_VERSION=21"
set "DL_DIR=%ProgramData%\CAT-Installer-JDK"
if not exist "%DL_DIR%" mkdir "%DL_DIR%"
set "API_JSON=%DL_DIR%\adoptium-api.json"
set "API_URL=https://api.adoptium.net/v3/assets/latest/%JDK_VERSION%/hotspot?architecture=%ARCH%&image_type=jdk&os=windows&package_type=msi"

echo Resolving latest OpenJDK %JDK_VERSION% download URL...
curl.exe -fsSL -o "%API_JSON%" "%API_URL%"
if errorlevel 1 (
    echo ERROR: Could not reach Adoptium API.
    pause
    goto end
)

set "DOWNLOAD_URL="
set "MSI_NAME="
for /f "usebackq delims=" %%L in (`findstr /c:"OpenJDK21U-jdk_%ARCH%_windows_hotspot_" "%API_JSON%" ^| findstr /c:"link" ^| findstr /c:".msi" ^| findstr /v /i ".json .sha256 .sig zip"`) do (
    if not defined DOWNLOAD_URL (
        for /f "tokens=1,* delims=:" %%A in ("%%L") do (
            set "URL_PART=%%B"
            set "URL_PART=!URL_PART:~2!"
            for /f "delims=," %%U in ("!URL_PART!") do set "DOWNLOAD_URL=%%U"
            set "DOWNLOAD_URL=!DOWNLOAD_URL:"=!"
        )
    )
)
for /f "usebackq delims=" %%L in (`findstr /c:"OpenJDK21U-jdk_%ARCH%_windows_hotspot_" "%API_JSON%" ^| findstr /c:"name" ^| findstr /c:".msi" ^| findstr /v /i ".json .sha256 .sig zip"`) do (
    if not defined MSI_NAME (
        for /f "tokens=1,* delims=:" %%A in ("%%L") do (
            set "NAME_PART=%%B"
            set "NAME_PART=!NAME_PART:~2!"
            for /f "delims=," %%N in ("!NAME_PART!") do set "MSI_NAME=%%N"
            set "MSI_NAME=!MSI_NAME:"=!"
        )
    )
)

if not defined DOWNLOAD_URL (
    echo ERROR: Could not parse download URL from Adoptium API.
    pause
    goto end
)

if not defined MSI_NAME (
    for %%F in ("!DOWNLOAD_URL!") do set "MSI_NAME=%%~nxF"
)

echo Downloading OpenJDK %JDK_VERSION% LTS...
echo URL: !DOWNLOAD_URL!
echo.

set "TARGET_MSI=%DL_DIR%\%MSI_NAME%"

echo Saving installer to:
echo %TARGET_MSI%
echo.

REM ---- Download (curl first, then PowerShell, then certutil) ----
echo Downloading... this may take a few minutes.
curl.exe -fsSL --retry 3 -L -o "%TARGET_MSI%" "!DOWNLOAD_URL!"
if errorlevel 1 (
    echo curl download failed. Trying PowerShell...
    "%PS%" -NoProfile -ExecutionPolicy Bypass -Command "try { $ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '!DOWNLOAD_URL!' -OutFile '%TARGET_MSI%' -UseBasicParsing; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
    if errorlevel 1 (
        echo PowerShell download failed. Trying certutil...
        certutil -urlcache -split -f "!DOWNLOAD_URL!" "%TARGET_MSI%"
        if errorlevel 1 (
            echo ERROR: Download failed.
            pause
            goto end
        )
    )
)

if not exist "%TARGET_MSI%" (
    echo ERROR: Download file not found after download.
    pause
    goto end
)
echo Download complete.
echo.

REM ---- Install silently with JAVA_HOME + PATH features ----
echo Installing OpenJDK %JDK_VERSION% LTS...
msiexec /i "%TARGET_MSI%" ADDLOCAL=FeatureMain,FeatureEnvironment,FeatureJavaHome /qn /norestart
if errorlevel 1 (
    echo ERROR: Installation failed.
    pause
    goto end
)
echo Installation complete.
echo.

REM ---- Locate installation directory from registry ----
set "JDK_PATH="
for /f "delims=" %%K in ('reg query "HKLM\SOFTWARE\JavaSoft\JDK" 2^>nul ^| findstr /r /i "HKEY.*\\21\.[0-9]"') do (
    for /f "tokens=2,*" %%A in ('reg query "%%K" /v JavaHome 2^>nul') do set "JDK_PATH=%%B"
)

REM Fallback: default Adoptium install directory
if not defined JDK_PATH (
    for /f "delims=" %%D in ('dir /b /ad /o-n "C:\Program Files\Eclipse Adoptium\jdk-21*" 2^>nul') do (
        set "JDK_PATH=C:\Program Files\Eclipse Adoptium\%%D"
        goto jdk_found
    )
)
:jdk_found

if not defined JDK_PATH (
    echo ERROR: Could not locate JDK installation path.
    pause
    goto end
)

REM Trim leading whitespace from registry value
for /f "tokens=* delims= " %%P in ("!JDK_PATH!") do set "JDK_PATH=%%P"

echo JDK installed at:
echo !JDK_PATH!
echo.

REM ---- Verify installation ----
echo Verifying Java installation...
"!JDK_PATH!\bin\java.exe" -version
if errorlevel 1 (
    echo ERROR: Java verification failed.
    pause
    goto end
)
echo.

echo ============================================
echo   CAT-INSTALLER-JDK 0.1 COMPLETE!
echo   Java 21 LTS is now installed.
echo   JAVA_HOME and PATH were set by the installer.
echo   Open a NEW terminal to use Java.
echo ============================================

REM ---- Cleanup ----
del /f /q "%TARGET_MSI%" "%API_JSON%" >nul 2>&1

:end
echo.
pause
endlocal
