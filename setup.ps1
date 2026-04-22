# ============================================================
# Accident App — Windows Setup Script (PowerShell)
# Run: Right-click -> "Run with PowerShell"  OR
#      powershell -ExecutionPolicy Bypass -File setup.ps1
# ============================================================

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Emergency SOS App — Windows Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── Helper functions ──────────────────────────────────────────────────────────
function Info($msg)    { Write-Host "[INFO] $msg" -ForegroundColor Green }
function Warn($msg)    { Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Fail($msg)    { Write-Host "[ERROR] $msg" -ForegroundColor Red; exit 1 }
function Success($msg) { Write-Host "[OK] $msg" -ForegroundColor Green }

# ── 1. Check Flutter ──────────────────────────────────────────────────────────
Info "Checking Flutter..."
try {
    $flutterVer = & flutter --version 2>&1 | Select-Object -First 1
    Success "Flutter: $flutterVer"
} catch {
    Fail "Flutter not found. Install from https://docs.flutter.dev/get-started/install/windows"
}

# ── 2. Check Java ─────────────────────────────────────────────────────────────
Info "Checking Java..."
try {
    $javaVer = & java -version 2>&1 | Select-Object -First 1
    Success "Java: $javaVer"
} catch {
    Fail "Java not found. Install JDK 17+ from https://adoptium.net"
}

# ── 3. Download real gradle-wrapper.jar ──────────────────────────────────────
$wrapperJar = "android\gradle\wrapper\gradle-wrapper.jar"
$jarSize = if (Test-Path $wrapperJar) { (Get-Item $wrapperJar).Length } else { 0 }

if ($jarSize -lt 10000) {
    Info "Downloading real gradle-wrapper.jar..."
    $urls = @(
        "https://github.com/gradle/gradle/raw/v8.3.0/gradle/wrapper/gradle-wrapper.jar",
        "https://raw.githubusercontent.com/gradle/gradle/v8.3.0/gradle/wrapper/gradle-wrapper.jar"
    )
    $downloaded = $false
    foreach ($url in $urls) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $wrapperJar -TimeoutSec 30
            $newSize = (Get-Item $wrapperJar).Length
            if ($newSize -gt 10000) {
                Success "gradle-wrapper.jar downloaded ($newSize bytes)"
                $downloaded = $true
                break
            }
        } catch {
            Warn "Failed from $url : $_"
        }
    }
    if (-not $downloaded) {
        Fail @"
Could not download gradle-wrapper.jar automatically.
Please download it manually:
  1. Open: https://github.com/gradle/gradle/raw/v8.3.0/gradle/wrapper/gradle-wrapper.jar
  2. Save to: $(Resolve-Path $wrapperJar)
  3. Re-run this script
"@
    }
} else {
    Success "gradle-wrapper.jar already present ($jarSize bytes)"
}

# ── 4. Write local.properties ─────────────────────────────────────────────────
Info "Detecting SDK paths..."

# Flutter SDK path
$flutterPath = (Get-Command flutter).Source | Split-Path | Split-Path

# Android SDK path (try common locations)
$androidSdkPaths = @(
    "$env:LOCALAPPDATA\Android\Sdk",
    "$env:USERPROFILE\AppData\Local\Android\Sdk",
    "C:\Android\sdk",
    "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk"
)
$androidSdk = $androidSdkPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $androidSdk) {
    Warn "Android SDK not found at common paths."
    Warn "You can find it in Android Studio: File > Project Structure > SDK Location"
    $androidSdk = Read-Host "Enter Android SDK path (or press Enter to skip)"
    if (-not $androidSdk) { $androidSdk = "C:\Users\$env:USERNAME\AppData\Local\Android\Sdk" }
}

$localProps = @"
sdk.dir=$($androidSdk.Replace('\', '\\'))
flutter.sdk=$($flutterPath.Replace('\', '\\'))
flutter.versionCode=1
flutter.versionName=1.0.0
"@
$localProps | Out-File -FilePath "android\local.properties" -Encoding ascii
Success "local.properties written"
Write-Host "  sdk.dir=$androidSdk"
Write-Host "  flutter.sdk=$flutterPath"

# ── 5. Flutter pub get ────────────────────────────────────────────────────────
Info "Running flutter pub get..."
& flutter pub get
if ($LASTEXITCODE -ne 0) { Fail "flutter pub get failed" }
Success "Packages downloaded"

# ── 6. Build APK ──────────────────────────────────────────────────────────────
Write-Host ""
Info "Building debug APK (first build takes 3-8 minutes)..."
& flutter build apk --debug
if ($LASTEXITCODE -ne 0) { Fail "flutter build apk failed. Run 'flutter doctor' for diagnostics." }

$apkPath = "build\app\outputs\flutter-apk\app-debug.apk"
if (Test-Path $apkPath) {
    $apkSize = [math]::Round((Get-Item $apkPath).Length / 1MB, 1)
    Success "APK built! Size: ${apkSize}MB"
    Success "Path: $apkPath"
} else {
    Fail "APK not found after build."
}

# ── 7. Install via ADB ────────────────────────────────────────────────────────
Write-Host ""
Info "Checking for connected Android device..."
try {
    $adbOutput = & adb devices 2>&1
    $devices = $adbOutput | Where-Object { $_ -match "device$" }
    
    if ($devices) {
        Info "Device found! Installing APK..."
        & adb install -r $apkPath
        if ($LASTEXITCODE -eq 0) {
            Success "APK installed on device!"
            Info "Launching app..."
            & adb shell am start -n com.example.accident_app/.MainActivity
        }
    } else {
        Warn "No device connected via USB."
        Write-Host ""
        Write-Host "  To install, connect your phone with USB Debugging enabled and run:" -ForegroundColor Cyan
        Write-Host "  adb install $apkPath" -ForegroundColor White
        Write-Host ""
        Write-Host "  For wireless install (same WiFi network):" -ForegroundColor Cyan
        Write-Host "  1. adb tcpip 5555" -ForegroundColor White
        Write-Host "  2. adb connect <PHONE_IP>:5555" -ForegroundColor White
        Write-Host "  3. adb install $apkPath" -ForegroundColor White
    }
} catch {
    Warn "ADB not found. Add Android SDK platform-tools to PATH."
    Write-Host "  Manual install: copy $apkPath to your phone and open it." -ForegroundColor Cyan
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  All done! See README.md for help." -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
