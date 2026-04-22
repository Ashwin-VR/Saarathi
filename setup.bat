@echo off
REM ============================================================
REM Accident App — One-shot setup + build script for Windows
REM Run: setup.bat
REM ============================================================

echo.
echo ========================================
echo   Emergency SOS App — Build Setup
echo ========================================
echo.

REM Check Flutter
where flutter >nul 2>&1
if ERRORLEVEL 1 (
    echo [ERROR] Flutter not found.
    echo         Install from https://docs.flutter.dev/get-started/install
    pause & exit /b 1
)
echo [OK] Flutter found.

REM Check Java
where java >nul 2>&1
if ERRORLEVEL 1 (
    echo [ERROR] Java not found. Install JDK 17+ from https://adoptium.net
    pause & exit /b 1
)
echo [OK] Java found.

REM Write local.properties
echo [INFO] Writing android\local.properties...
echo sdk.dir=%LOCALAPPDATA%\Android\Sdk> android\local.properties
for /f "delims=" %%i in ('where flutter') do set FLUTTER_PATH=%%i
for %%i in ("%FLUTTER_PATH%") do set FLUTTER_DIR=%%~dpi..
echo flutter.sdk=%FLUTTER_DIR%>> android\local.properties
echo flutter.versionCode=1>> android\local.properties
echo flutter.versionName=1.0.0>> android\local.properties
echo [OK] local.properties written.

REM Get packages
echo [INFO] Running flutter pub get...
call flutter pub get
echo [OK] Packages downloaded.

REM Build APK
echo.
echo [INFO] Building debug APK...
call flutter build apk --debug
if ERRORLEVEL 1 (
    echo [ERROR] Build failed. Run "flutter doctor" for diagnostics.
    pause & exit /b 1
)

set APK=build\app\outputs\flutter-apk\app-debug.apk
echo [OK] APK built: %APK%

REM Install via ADB
echo.
where adb >nul 2>&1
if ERRORLEVEL 1 (
    echo [WARN] ADB not found in PATH.
    echo        Add %LOCALAPPDATA%\Android\Sdk\platform-tools to PATH
    goto :done
)

adb devices | findstr /i "device" >nul 2>&1
if ERRORLEVEL 1 (
    echo [WARN] No device connected.
    echo        Connect phone with USB Debugging enabled and run:
    echo        adb install %APK%
    goto :done
)

echo [INFO] Installing APK on connected device...
adb install -r %APK%
echo [OK] Installed!

:done
echo.
echo ========================================
echo   Done! See README.md for more help.
echo ========================================
pause
