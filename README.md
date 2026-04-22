[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.2+-0175C2?logo=dart)](https://dart.dev)
[![Gemini AI](https://img.shields.io/badge/Gemini-2.0%20Flash-4285F4?logo=google)](https://ai.google.dev)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20iOS-lightgrey)](https://flutter.dev)
# 🚨 Accident App  Emergency SOS

Offline-first Flutter emergency response app  BLE SOS · OSM Maps · Nearby Emergency Services · SMS fallback.

---

## ⚡ Quick Start (Windows  recommended)

```powershell
# In PowerShell (run as normal user, NOT admin):
cd accident_app
powershell -ExecutionPolicy Bypass -File setup.ps1
```

`setup.ps1` automatically:
1. Downloads the real `gradle-wrapper.jar`
2. Detects your Android SDK + Flutter paths and writes `local.properties`
3. Runs `flutter pub get`
4. Builds the debug APK
5. Installs it on your phone if connected via USB

---

## ⚡ Quick Start (Linux / macOS)

```bash
cd accident_app
chmod +x setup.sh && ./setup.sh
```

---

## 🔧 Manual Steps (if scripts fail)

### Step 1  Fix gradle-wrapper.jar (Windows PowerShell)
```powershell
# This is what caused your error  run this FIRST:
Invoke-WebRequest `
  -Uri "https://github.com/gradle/gradle/raw/v8.3.0/gradle/wrapper/gradle-wrapper.jar" `
  -OutFile "android\gradle\wrapper\gradle-wrapper.jar"
```

```bash
# Linux / macOS:
curl -L https://github.com/gradle/gradle/raw/v8.3.0/gradle/wrapper/gradle-wrapper.jar \
     -o android/gradle/wrapper/gradle-wrapper.jar
```

### Step 2  Edit local.properties
Open `android/local.properties` and set your actual paths:
```properties
# Windows example:
sdk.dir=C:\\Users\\YourName\\AppData\\Local\\Android\\Sdk
flutter.sdk=C:\\flutter

# Linux/macOS example:
sdk.dir=/home/yourname/Android/Sdk
flutter.sdk=/home/yourname/flutter
```
Find your Android SDK path in Android Studio → File → Project Structure → SDK Location.

### Step 3  Build APK
```bash
flutter pub get
flutter build apk --debug
```

### Step 4  Install on phone

**USB (simplest):**
```bash
# Enable Developer Options + USB Debugging on phone first
adb install build/app/outputs/flutter-apk/app-debug.apk
```

**Wireless (same WiFi):**
```bash
adb tcpip 5555
# Find phone IP: Settings → About → Status → IP Address
adb connect 192.168.1.XXX:5555
adb install build/app/outputs/flutter-apk/app-debug.apk
adb disconnect
```

**Manual install (no ADB):**
- Copy `build/app/outputs/flutter-apk/app-debug.apk` to your phone via USB/cloud
- On phone: Settings → Security → enable "Install unknown apps"
- Tap the APK file to install

---

## 🗂️ Project Structure

```
accident_app/
├── setup.ps1                         ← ✅ Windows: run this first
├── setup.sh                          ← ✅ Linux/macOS: run this first
├── android/
│   ├── local.properties              ← ⚠️  EDIT: set your SDK paths
│   ├── gradle/wrapper/
│   │   ├── gradle-wrapper.jar        ← ⚠️  download real one (see Step 1)
│   │   └── gradle-wrapper.properties
│   ├── gradlew                       ← auto-downloads jar on Linux/macOS
│   ├── gradlew.bat                   ← auto-downloads jar on Windows
│   └── app/src/main/
│       ├── AndroidManifest.xml       ← all permissions
│       └── kotlin/…/MainActivity.kt
├── lib/
│   ├── main.dart
│   ├── core/router/app_router.dart
│   ├── core/theme/app_theme.dart
│   ├── features/
│   │   ├── map/map_screen.dart
│   │   ├── nearby/nearby_screen.dart
│   │   └── sos/sos_screen.dart
│   ├── screens/home_screen.dart
│   └── shared/
│       ├── models/emergency_service.dart
│       ├── providers/app_state.dart
│       ├── services/{location,overpass,sensor,sos}_service.dart
│       └── widgets/{sos_button,service_card,filter_chip_row,permission_gate}.dart
├── assets/icons/
└── pubspec.yaml
```

---

## 🗺️ Configure Map Tiles (optional)

Default uses free demo tiles. For production:
1. Get a free key at https://www.maptiler.com/
2. Edit `lib/features/map/map_screen.dart`:
```dart
static const _styleUrl =
    'https://api.maptiler.com/maps/streets/style.json?key=YOUR_KEY';
```

---

## 🛠️ Troubleshooting

| Error | Fix |
|-------|-----|
| `Could not find or load main class org.gradle.wrapper.GradleWrapperMain` | Download real `gradle-wrapper.jar` (Step 1 above) |
| `SDK not found` | Edit `android/local.properties` with correct paths |
| `flutter pub get` fails | Check internet; run `flutter doctor` |
| `adb: device not found` | Enable USB Debugging; try different cable |
| Map shows blank | Get free MapTiler key (see above) |
| BLE not working | Requires real device; grant Bluetooth permissions |

---

## Prerequisites

| Tool | Min version | Link |
|------|-------------|------|
| Flutter SDK | 3.19+ | https://docs.flutter.dev/get-started/install |
| Android SDK | API 34 | Via Android Studio |
| JDK | 17+ | https://adoptium.net |
| ADB | any | Bundled with Android SDK |
