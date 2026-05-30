Analysis Summary
App: Saarathi (package: accident_app) — Offline-first emergency response Flutter app.
Folder Structure
lib/
├── main.dart                          # ProviderScope + MaterialApp.router
├── core/router/app_router.dart        # GoRouter (9 routes) + SettingsPage + SosAlertPage (inline)
├── core/theme/app_theme.dart          # Material 3 light/dark + AppColors extension
├── features/
│   ├── bystander/                     # Bystander coordination (model + provider + widget)
│   ├── fake_call/                     # Fake call escape tool
│   ├── history/                       # Incident history list
│   ├── logs/                          # Debug log viewer
│   ├── map/                           # Embeddable OSM map widget
│   ├── nearby/                        # Full-screen nearby services list
│   ├── onboarding/                    # 3-page first-launch flow
│   └── sos/                           # SOS screen, SOS map, incident detail
├── screens/home_screen.dart           # Main screen (map + SOS + panels)
└── shared/
    ├── models/                        # 3 models (EmergencyService, IncidentRecord, SafeLocation)
    ├── providers/app_state.dart       # Central state (SOS pipeline, location, POI, proximity)
    ├── services/                      # 24 service files
    ├── utils/maps_launcher.dart
    └── widgets/                       # 6 reusable widgets
State Management: Riverpod 2.x
- Provider for service singletons, NotifierProvider for complex SOS state, AsyncNotifierProvider for POI loading, StateProvider for simple toggles
- Central orchestrator: SosNotifier manages the full SOS lifecycle (idle → preAlert → response window → active → received)
Navigation: GoRouter 13.x
- 9 declarative routes with onboarding redirect via SharedPreferences
- Data passing via state.extra
Service Layer: 24 services across GPS, BLE, sensors, communication, AI, care mode, data persistence
Data Layer: SharedPreferences for all persistence + file system for PDFs. No backend database. Optional Gemini AI enrichment.
Key Features:
- One-tap SOS (BLE broadcast + SMS + PDF)
- Crash detection (accelerometer G-force + sudden stop)
- BLE mesh relay with multi-hop propagation
- Nearby emergency services (OSM Overpass)
- Care Mode (wellness checks)
- Fake call escape tool
- AI triage + report narrative (Gemini 2.0 Flash)
- Fully offline-capable