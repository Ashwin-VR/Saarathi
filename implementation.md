# RoadSoS — Implementation Plan (Corrected)

> **PRD**: `roadsos_prd.md` v2.0  
> **Platform**: Flutter/Dart — Android primary, iOS secondary  
> **Package**: `accident_app` (kept as-is to avoid native plugin breakage)

---

## Gap Analysis vs PRD

### Build-Breaking Issues (must fix first)
| Issue | File | Fix |
|---|---|---|
| `flutter_ble_peripheral` — NDK compile failure on API 34+ | pubspec.yaml | Remove; replace advertising calls with no-ops |
| `telephony` — unmaintained, compile failure | pubspec.yaml | Remove (SMS already uses `url_launcher`) |
| `flutter_tts` — out of scope per PRD §17 | pubspec.yaml | Remove; stub TtsService |
| `volume_controller` — out of scope per PRD §17 | pubspec.yaml | Remove (SosAlertService uses MethodChannel only — already clean) |
| Firebase `google-services` classpath with no `google-services.json` | android/build.gradle.kts | Remove classpath |
| Firebase plugin applied in app module | android/app/build.gradle.kts | Remove plugin |

### Missing Packages
| Package | Purpose | Version |
|---|---|---|
| `google_generative_ai` | Gemini AI co-pilot | ^0.4.3 |
| `qr_flutter` | Victim ID QR code | ^4.1.0 |
| `pdf` | Victim ID PDF export | ^3.12.0 |
| `archive` | District tile .json.gz decompression | ^3.4.10 |
| `flutter_map_tile_caching` | OSM tile pre-caching | ^9.1.0 |

### Missing Features vs PRD
| Feature | PRD Section | Status |
|---|---|---|
| Emergency Dial Bar (108/100/112, always visible) | §5.1 | ❌ Missing |
| AI Co-pilot (Gemini + offline Q&A) | §5.6 | ❌ Missing |
| Crash Countdown Screen (15s) | §5.4.1 | ❌ Missing (existing is 10s, no dedicated screen) |
| Emergency Response Panel | §5.3 | ❌ Missing |
| Victim ID Card (QR + PDF) | §5.5 | ❌ Missing |
| DPDPA consent in onboarding | §9.1 | ❌ Missing |
| Good Samaritan law modal | §9.3 | ❌ Missing |
| `assets/data/emergency_numbers.json` | §5.1, §6.4 | ❌ Missing |
| `assets/data/offline_qa.json` | §5.6.5 | ❌ Missing |
| `assets/data/hospitals_india.json` | §6.2 | ❌ Missing |
| Category filter: all 8 PRD categories | §5.2.1 | ⚠️ Partial |
| POI card: navigate, flag, data source badge | §5.2.3 | ⚠️ Partial |

### Existing Features (keep, enhance)
| Feature | Status |
|---|---|
| OSM Map with `flutter_map` | ✅ Working |
| Overpass POI fetch + cache | ✅ Working |
| Crash sensor detection | ✅ Working (threshold: 2.5G) |
| SMS alert via `url_launcher` | ✅ Working |
| SOS countdown (10s → update to 15s) | ✅ Working |
| BLE passive scan (bystander detection) | ✅ Keep |
| Location service + cache | ✅ Working |
| Settings (contacts, profile, toggles) | ✅ Working |
| Onboarding flow | ✅ Working (needs DPDPA page added) |
| Dark mode via `ThemeMode.system` | ✅ Working |
| Notification service | ✅ Working |

---

## Implementation Phases

### Phase 1 — Build Fixes
1. `pubspec.yaml` — remove bad packages, add missing ones, update assets section
2. `android/build.gradle.kts` — remove Firebase classpath
3. `android/app/build.gradle.kts` — remove Firebase plugin
4. `android/app/src/main/AndroidManifest.xml` — fix permissions
5. `lib/shared/services/ble_sos_service.dart` — stub out advertising
6. `lib/shared/services/tts_service.dart` — stub out TTS

### Phase 2 — Asset Files
7. `assets/data/emergency_numbers.json`
8. `assets/data/offline_qa.json`
9. `assets/data/hospitals_india.json`

### Phase 3 — New Services
10. `lib/shared/services/gemini_service.dart`
11. `lib/shared/services/offline_qa_service.dart`
12. `lib/shared/models/chat_message.dart`
13. `lib/shared/providers/chat_provider.dart`

### Phase 4 — New UI Features
14. `lib/features/home/widgets/emergency_dial_bar.dart`
15. `lib/features/home/widgets/emergency_response_panel.dart`
16. `lib/features/ai_copilot/ai_copilot_panel.dart`
17. `lib/features/crash_detection/crash_countdown_screen.dart`
18. `lib/features/victim_id/victim_id_screen.dart`
19. `lib/features/victim_id/victim_qr_screen.dart`
20. `lib/features/victim_id/victim_id_pdf.dart`

### Phase 5 — Home Screen + Router
21. `lib/screens/home_screen.dart` — add Dial Bar, AI FAB, Response Panel
22. `lib/core/router/app_router.dart` — add new routes + Victim ID in Settings

### Phase 6 — Onboarding
23. `lib/features/onboarding/onboarding_screen.dart` — DPDPA consent first page

---

## File Structure After Implementation

```
lib/
├── core/router/app_router.dart          (MODIFY — new routes)
├── core/theme/app_theme.dart            (no change)
├── features/
│   ├── ai_copilot/
│   │   └── ai_copilot_panel.dart        (NEW)
│   ├── crash_detection/
│   │   └── crash_countdown_screen.dart  (NEW)
│   ├── home/
│   │   └── widgets/
│   │       ├── emergency_dial_bar.dart  (NEW)
│   │       └── emergency_response_panel.dart (NEW)
│   ├── onboarding/
│   │   └── onboarding_screen.dart      (MODIFY — DPDPA page)
│   └── victim_id/
│       ├── victim_id_screen.dart        (NEW)
│       ├── victim_qr_screen.dart        (NEW)
│       └── victim_id_pdf.dart           (NEW)
├── screens/home_screen.dart             (MODIFY — integrate new widgets)
└── shared/
    ├── models/chat_message.dart         (NEW)
    ├── providers/chat_provider.dart     (NEW)
    └── services/
        ├── gemini_service.dart          (NEW)
        ├── offline_qa_service.dart      (NEW)
        ├── ble_sos_service.dart        (MODIFY — stub advertising)
        └── tts_service.dart            (MODIFY — stub TTS)

assets/
├── data/
│   ├── emergency_numbers.json           (NEW)
│   ├── offline_qa.json                  (NEW)
│   └── hospitals_india.json             (NEW — stub)
├── tiles/                               (NEW — placeholder dir)
└── audio/                               (NEW — placeholder dir)
```
