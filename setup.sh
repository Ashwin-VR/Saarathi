#!/bin/bash
# ============================================================
# Accident App — One-shot setup + build script
# Run: chmod +x setup.sh && ./setup.sh
# ============================================================
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }

echo ""
echo "========================================"
echo "  Emergency SOS App — Build Setup"
echo "========================================"
echo ""

# ── 1. Check Flutter ─────────────────────────────────────────────────────────
info "Checking Flutter..."
if ! command -v flutter &> /dev/null; then
    error "Flutter not found. Install from https://docs.flutter.dev/get-started/install"
fi
FLUTTER_VER=$(flutter --version 2>/dev/null | head -1)
success "Flutter found: $FLUTTER_VER"

# ── 2. Check Java ─────────────────────────────────────────────────────────────
info "Checking Java..."
if ! command -v java &> /dev/null; then
    error "Java not found. Install JDK 17+ from https://adoptium.net"
fi
success "Java found: $(java -version 2>&1 | head -1)"

# ── 3. Check ADB ──────────────────────────────────────────────────────────────
info "Checking ADB..."
if command -v adb &> /dev/null; then
    success "ADB found: $(adb version | head -1)"
else
    warn "ADB not found. Install Android SDK platform-tools."
    warn "APK will be built but not transferred automatically."
fi

# ── 4. Detect SDK paths and write local.properties ───────────────────────────
info "Detecting SDK paths..."

FLUTTER_SDK=$(which flutter | xargs dirname | xargs dirname)
ANDROID_SDK="${ANDROID_HOME:-${HOME}/Android/Sdk}"

if [ ! -d "$ANDROID_SDK" ]; then
    # Try common macOS path
    if [ -d "$HOME/Library/Android/sdk" ]; then
        ANDROID_SDK="$HOME/Library/Android/sdk"
    else
        warn "Android SDK not found at $ANDROID_SDK"
        warn "Edit android/local.properties manually after this script."
    fi
fi

cat > android/local.properties << PROPS
sdk.dir=${ANDROID_SDK}
flutter.sdk=${FLUTTER_SDK}
flutter.versionCode=1
flutter.versionName=1.0.0
PROPS

success "local.properties written:"
cat android/local.properties
echo ""

# ── 5. Get Flutter packages ───────────────────────────────────────────────────
info "Running flutter pub get..."
flutter pub get
success "Packages downloaded"

# ── 6. Flutter doctor ─────────────────────────────────────────────────────────
info "Running flutter doctor..."
flutter doctor --android-licenses --no-color 2>/dev/null || true
flutter doctor 2>/dev/null || true

# ── 7. Build APK ──────────────────────────────────────────────────────────────
echo ""
info "Building debug APK (this takes 2–5 minutes on first run)..."
flutter build apk --debug

APK_PATH="build/app/outputs/flutter-apk/app-debug.apk"
if [ -f "$APK_PATH" ]; then
    APK_SIZE=$(du -sh "$APK_PATH" | cut -f1)
    success "APK built successfully!"
    success "Path: $APK_PATH"
    success "Size: $APK_SIZE"
else
    error "APK not found at $APK_PATH — build may have failed."
fi

# ── 8. Install to connected device ───────────────────────────────────────────
echo ""
if command -v adb &> /dev/null; then
    DEVICES=$(adb devices | grep -v "List of" | grep "device$" | wc -l)
    if [ "$DEVICES" -gt 0 ]; then
        info "Found $DEVICES connected device(s). Installing APK..."
        adb install -r "$APK_PATH"
        success "APK installed on device!"
        echo ""
        info "Launching app..."
        adb shell am start -n com.example.accident_app/.MainActivity
    else
        warn "No device connected via USB."
        echo ""
        echo "  To install manually:"
        echo "  1. Connect phone with USB Debugging enabled"
        echo "  2. Run: adb install $APK_PATH"
        echo ""
        echo "  Or wirelessly:"
        echo "  1. adb tcpip 5555"
        echo "  2. adb connect <PHONE_IP>:5555"
        echo "  3. adb install $APK_PATH"
    fi
else
    info "To install, run:"
    echo "  adb install $APK_PATH"
fi

echo ""
echo "========================================"
echo "  Done! See README.md for more help."
echo "========================================"
