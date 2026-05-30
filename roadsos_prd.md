# RoadSoS — Product Requirements Document
**Version:** 2.0  
**Hackathon:** Road Safety Hackathon 2026 — CoERS, RBG Labs, IIT Madras  
**Problem Statement:** 1.3 — RoadSoS  
**Theme:** AI in Road Safety / AI-powered chatbots  
**Platform:** Android (primary), iOS (secondary) — Flutter/Dart  
**Document purpose:** Complete engineering specification for use as direct AI coding agent input

---

## 1. First-Principles Problem Statement

India records 461,000+ road accidents per year, killing 168,000 people (MoRTH 2022). The clinical
concept of the Golden Hour — the 60-minute window after trauma when intervention dramatically
reduces mortality — is routinely lost. Only 20.6% of road accident victims reach a healthcare
facility within the Golden Hour (AIIMS/Sangli study, 2022). The average ambulance response time on
Indian national highways is 25–35 minutes, and a further 15–25 minutes is spent transporting the
victim to a hospital.

The time gap that kills people is not the ambulance drive. It is the minutes between the crash and
the first emergency call — caused by bystander confusion, ignorance of nearby resources, fear of
legal liability, and friction in reaching the right number. Three out of four Indians are hesitant to
help accident victims due to fear of police harassment and legal formalities (MoRTH survey).

**The engineering problem RoadSoS solves:**  
Eliminate the dead time between a crash happening and the right resources being mobilised. Do this
for anyone — the person in the crash or a person who witnessed it — in any connectivity condition,
under extreme cognitive stress.

---

## 2. The State Machine (Core Engineering Model)

The entire app is built around a single user state machine. There is no "victim mode" or "bystander
mode" as separate user-selected personas. There is one user. They are in one of three states at all
times. State transitions are triggered by sensors and explicit user actions — never by a menu choice.

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                                                                             │
│   IDLE ──────────────────────────────────────────────────── ACTIVE         │
│   (app background,        crash detected OR            (app foreground,    │
│    monitoring quietly)    manual SOS pressed           user at scene)      │
│        │                         │                          │              │
│        │                         ▼                          │              │
│        │                   CRASH_COUNTDOWN                  │              │
│        │                   (15s cancel window)              │              │
│        │                         │                          │              │
│        │              cancelled  │  expired                 │              │
│        │                  ▲      │      │                   │              │
│        │                  │      │      ▼                   │              │
│        └──────────────────┘   EMERGENCY                     │              │
│                                (alerts sent,           ◄────┘              │
│                                 app foregrounded)                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**State: IDLE**  
App running as a foreground service (persistent low-priority notification). Sensor monitoring
active. UI not visible. Battery cost: minimal (accelerometer polling at 10Hz in idle, no GPS drain).

**State: ACTIVE**  
App is in the foreground. The user is at an accident scene — either their own or one they witnessed.
This is the single main screen. It shows the POI map, the emergency dial bar, and the AI co-pilot.
The UI does not know or care whether the user is "the victim" or "a bystander" — it gives the same
information to both. What distinguishes victim vs bystander behaviour is only: was a crash detected?
if yes, the Emergency Response Panel is shown. If no, it is hidden.

**State: CRASH_COUNTDOWN**  
Triggered by: (a) crash detection algorithm, or (b) user pressing the manual SOS button.
Shows a full-screen countdown. Can be cancelled. Cannot be accidentally triggered.

**State: EMERGENCY**  
Crash confirmed (countdown elapsed without cancel). Two things happen immediately:
1. SMS alert fired to stored emergency contacts.
2. App foregrounds and shows the Emergency Response Panel prominently.
From this state the user can still use all bystander functions (POI map, AI).
The Emergency Response Panel is an additional overlay — it does not replace the main UI.

**Why this is the right model:**  
A person in the EMERGENCY state still needs to find the hospital. A bystander still might need to
send location to someone. They use the same map, the same AI, the same dial bar. Splitting into
"modes" would mean maintaining two parallel UIs that are 90% identical. The state machine unifies
them correctly.

---

## 3. System Context and Integration

### 3.1 What RoadSoS is

A local-first emergency resource finder with an AI co-pilot and crash detection. It does not replace
112. It does not replace the 112 India App. It is the layer between "crash happened" and "112
operator answers" — filling the information gap with: where are the nearest facilities, what do I
do right now, and who have I notified.

### 3.2 Integration with India's ERSS-112

<ERSS-112 is the Government of India's Emergency Response Support System, receiving distress signals
from 10 channels including "External Signals." There is no public API for third-party apps to send
structured signals directly to ERSS PSAPs as of this writing. The integration path is voice + SMS
— both of which ERSS handles natively.>

Integration approach (no API key, no registration required):
- **Voice:** `tel:112` via `url_launcher`. The call is received by the ERSS PSAP exactly as a
  regular 112 call. The operator has CAD (Computer-Aided Dispatch) tools to handle it.
- **SMS to 112:** `sms:112?body=...` via `url_launcher`. ERSS accepts SMS signals. The structured
  SMS body (see Section 6.2) gives the operator GPS coordinates, victim info, and nearest hospitals
  in a single message — more useful than a voice call from a panicked bystander.
- **Future path (post-hackathon):** ERSS accepts "External Signals" as a channel. MHA/C-DAC has not
  published an external signal API. The correct post-hackathon path is a formal integration request
  to C-DAC. For the hackathon, voice + SMS is the correct and complete integration.

### 3.3 Legal Context

**Section 134, Motor Vehicles Act 1988:** The driver of a vehicle involved in an accident has a
legal duty to secure medical attention for injured persons.

**Section 134A, Motor Vehicles (Amendment) Act 2019:** A Good Samaritan who renders emergency
assistance at an accident scene in good faith is protected from civil and criminal liability.
Three out of four Indians do not help accident victims due to fear of legal repercussions. The app
must surface this protection to reduce the bystander hesitation gap.

**DPDPA 2023:** Location data and health data (Victim ID) require explicit user consent. Consent
must be specific, informed, and revocable. Details in Section 9.

---

## 4. Screen Architecture

There is one primary screen. Everything else is a sheet, overlay, or supplementary screen.

```
RoadSoS
│
├── [PRIMARY] Home Screen
│       ├── Emergency Dial Bar (fixed top)
│       ├── POI Map (full bleed, centre)
│       ├── Category Filter Row (over map)
│       ├── POI Bottom Sheet (drag-up)
│       ├── AI Co-pilot FAB (bottom right)
│       └── Emergency Response Panel (conditional overlay, bottom)
│               └── visible only when state == EMERGENCY
│
├── [SHEET] AI Co-pilot Panel
│       ├── Quick-chip row
│       ├── Chat scroll
│       └── Text input + connectivity badge
│
├── [OVERLAY] Crash Countdown Screen
│       ├── Large countdown (15s)
│       └── Cancel button (full width)
│
├── [SUPPLEMENTARY] Victim ID Screen
│       ├── Profile form
│       └── QR code view
│
├── [SUPPLEMENTARY] Settings Screen
│       ├── Emergency contacts (for SMS alert)
│       ├── Victim ID shortcut
│       ├── Crash detection sensitivity
│       ├── Offline tile cache
│       └── DPDPA consent management
│
└── [SUPPLEMENTARY] Onboarding (first launch only)
        ├── DPDPA consent
        ├── Permission requests (location, SMS, notifications)
        ├── Emergency contacts setup
        └── Optional: Victim ID setup
```

---

## 5. Feature Specifications

### 5.1 Emergency Dial Bar

**Position:** Fixed at the top of the Home Screen. Always visible. Cannot be scrolled away.

**Content:** Three tap-to-call buttons, auto-populated from `assets/data/emergency_numbers.json`
keyed by detected country (ISO 3166-1 alpha-2 from reverse geocode). Default (India):

| Button | Number | Colour |
|--------|--------|--------|
| Ambulance | 108 | Red |
| Police | 100 | Blue |
| Emergency | 112 | Dark red |

On tap: `url_launcher` opens `tel:{number}`. No confirmation dialog — emergency dial must be a
single tap. The OS's native dialler opens; user taps Call. This is intentional — prevents
accidental pocket-dials.

**Disclaimer** (small text below bar): "Numbers may change. Verify locally. MHA plans to unify all
numbers under 112."

**Offline:** Fully functional. Cellular voice does not require data.

**Fallback if country unknown:** Show 112 for all three slots. 112 works across India and most
countries by routing to the local PSAP.

---

### 5.2 POI Map

**Library:** `flutter_map` with OSM tiles.

**Tile caching strategy:** `flutter_map_tile_caching`. On first launch with internet, silently
pre-download tiles for the detected district at zoom levels 10–16 in background. This takes 2–5
minutes on a typical connection. If the user closes the app before caching completes, resume on
next launch. Cached tiles persist until manually cleared or storage runs critically low.

If no cached tiles and no internet: render a plain grey canvas. POI markers are plotted as
coordinate points on the canvas — still usable for distance/direction to each POI. This is a
degraded but functional state, not a failure state.

**Map centre:** User's GPS location, auto-centred on launch. Heading indicator rotates with compass.

**Markers:** Colour-coded by category. On tap: POI card expands as a bottom sheet item.

#### 5.2.1 POI Categories

| Category | OSM Tags | Colour |
|----------|----------|--------|
| Hospital / Trauma centre | `amenity=hospital` | Red |
| Clinic / Doctor | `amenity=clinic\|doctors` | Orange |
| Pharmacy | `amenity=pharmacy` | Green |
| Ambulance station | `emergency=ambulance_station` | Red (pulsing ring) |
| Police station | `amenity=police` | Blue |
| Fire station | `amenity=fire_station` | Yellow |
| Car repair / Garage | `shop=car_repair` | Grey |
| Tyre shop | `shop=tyres` | Grey |

#### 5.2.2 Category Filter Row

Horizontal scrollable chip row above the map. Default: Hospitals, Ambulance, Police all active.
Others inactive by default. Chip tap toggles that category on/off instantly. "All" and "Trauma
only" quick-select chips at the left end.

State managed in `activeCategoriesProvider` (Riverpod `StateProvider<Set<PoiCategory>>`). Map
markers refilter reactively.

#### 5.2.3 POI Card (in bottom sheet)

Each card displays:
- Name (bold, 16sp)
- Category badge (colour-coded pill)
- Distance from user (e.g. "1.2 km")
- Phone number — tappable chip → `tel:` intent
- Data source badge: "OSM", "Govt", or "User-verified"
- Data age: "Fetched 2 days ago" or "Bundled — verify before visiting"
- "Flag as incorrect" icon button (saves local correction flag)
- "Navigate" button → opens Google Maps / native maps with POI coordinates

Sort order: Hospitals first, then ambulance, then others. Within category: distance ascending.

---

### 5.3 Emergency Response Panel

This panel is the only thing that changes when the user transitions to EMERGENCY state. It appears
as a non-dismissible panel at the bottom of the Home Screen, above the POI bottom sheet handle.
It does not replace the map or the dial bar.

**Panel contents:**

```
┌──────────────────────────────────────────────────────────┐
│  🔴  ALERT SENT · {timestamp}                     [×] ¹ │
│  ─────────────────────────────────────────────────────── │
│  Contacts notified: {contact_1_name}, {contact_2_name}  │
│  Your location was shared: {district}, {state}           │
│  ─────────────────────────────────────────────────────── │
│  [ CALL 112 NOW ]          [ SHARE LOCATION ]            │
└──────────────────────────────────────────────────────────┘
```

¹ The [×] dismiss button only hides the panel — it does not undo the alert. A dismissed panel can
be re-opened from a persistent notification.

**CALL 112 NOW:** Large red button. Dials 112 immediately.

**SHARE LOCATION:** Opens share sheet with pre-formatted text:
```
I've been in a road accident. Location: {lat},{lng} ({district}, {state})
Maps: https://maps.google.com/?q={lat},{lng}
Nearest hospital: {name_of_closest_hospital} — {distance} — {phone}
Time: {timestamp}
```
This format is designed to be sent via WhatsApp, SMS, or any messenger — giving a dispatcher or
family member everything they need in one message.

**Good Samaritan reminder** (small text below buttons):
"Section 134A, Motor Vehicles Act: You are legally protected for helping in good faith."
This is displayed only when the panel is in view. Purpose: reduce bystander inaction caused by fear
of legal liability. This is an evidence-based intervention — 75% of Indians cite legal fear as
their reason for not helping.

---

### 5.4 Crash Detection

Crash detection runs as a foreground service (persistent notification visible in the system tray).
This keeps the sensor subscription alive when the screen is off. Android 14+ foreground service
category: `FOREGROUND_SERVICE_HEALTH`.

#### 5.4.1 Detection Algorithm

**Sensor inputs:**
- Accelerometer via `sensors_plus`, sampled at 50Hz
- Gyroscope via `sensors_plus`, sampled at 50Hz
- GPS speed via `geolocator` position stream, sampled at 1Hz

**Crash condition (all three must be true simultaneously):**

1. Total G-force `g = sqrt(ax² + ay² + az²) / 9.81 > 3.0` sustained for ≥200ms
2. GPS speed at time of event `> 20 km/h`  
   *(speed gate: eliminates phone drops, speed bumps, road jolts at rest)*
3. Post-impact: gyroscope angular velocity `> 1.5 rad/s` within 500ms of the G-spike  
   *(orientation change: eliminates vertical drops, hitting the phone against a hard surface)*

**Why these thresholds:**
- 3.0G sustained for 200ms: Experimentally determined threshold separating vehicle impacts from
  road bumps. Single-sample spikes from potholes rarely exceed 2.0G at normal road speeds.
- 20 km/h speed gate: A dropped phone at rest will never pass this gate.
- 1.5 rad/s gyro gate: A vehicle crash almost always involves rotation. A phone dropped on a table
  does not.

**What happens on detection:**
1. Transition to CRASH_COUNTDOWN state.
2. Play loud alarm (audioplayers, `assets/audio/alarm.mp3`) — serves dual purpose: alerts user and
   attracts nearby people.
3. Display countdown screen (15 seconds).
4. If cancelled: return to IDLE. Log event locally.
5. If countdown elapses: transition to EMERGENCY. Stop alarm. Fire alerts (Section 5.4.2).

**GPS speed unavailable (cold start / no fix):**  
Skip the speed gate. Raise the G threshold to 4.0G and require 500ms sustain. More conservative,
slightly higher false positive rate, but still functional.

**Parking/stationary detection:**  
If GPS speed has been <5 km/h for >60 consecutive seconds, suspend crash detection and set a
"parked" flag. Resume when speed rises above 10 km/h. This prevents drain from continuous
sensor polling when the car is parked.

#### 5.4.2 Alert Payload (on EMERGENCY transition)

Two alerts are fired in parallel:

**Alert 1 — SMS to emergency contacts** (via `url_launcher` SMS intent, iterated for each contact):
```
ROADSOS ALERT — Road accident detected.
Name: {user_name or "Unknown"}
Location: {lat}, {lng} ({district}, {state})
Maps: https://maps.google.com/?q={lat},{lng}
Time: {ISO_timestamp}
Blood group: {blood_group if set, else "Unknown"}
Nearest hospital: {name} — {distance} — {phone}
Status: Sent automatically. If this is a mistake, call me now.
```

**Alert 2 — WhatsApp deep link** (if WhatsApp is installed, via `url_launcher`):
```
wa.me/?text={URI_encoded_same_message}
```
WhatsApp is used by >500M Indians and frequently has better delivery reliability than SMS in urban
areas. Both are attempted; user does not need to choose.

Note on SMS: `url_launcher` opens the native SMS app pre-populated. The user must tap Send.
This is not a silent background SMS. This is a deliberate design choice:
1. Silent SMS sending requires `SEND_SMS` permission which triggers Play Store security review.
2. The user's confirmation tap is a required human-in-the-loop for a false-positive safety net.
3. The 15-second countdown already provides the primary false-positive gate.

#### 5.4.3 Manual SOS

A persistent floating action button (FAB) with an SOS icon is always visible on the Home Screen.
Long-press (1 second) → triggers CRASH_COUNTDOWN. Short tap shows a tooltip: "Hold to send SOS."
Long-press requirement prevents accidental activation when interacting with the map.

---

### 5.5 Victim ID Card

A structured personal health summary stored entirely on-device. Its purpose: give first-responding
EMTs critical information about the patient before the patient can speak.

**Access:** Settings → Victim ID. Also reachable from the Emergency Response Panel via "My medical
info" link.

**Fields:**

| Field | Type | Required |
|-------|------|----------|
| Full name | Text | Yes |
| Profile photo | Camera / gallery | No |
| Blood group | Dropdown (8 options + Unknown) | Yes |
| Known allergies | Multi-line text | No |
| Chronic conditions | Multi-line text | No |
| Current medications | Multi-line text | No |
| Emergency contact 1 | Name + phone | Yes |
| Emergency contact 2 | Name + phone | No |
| Organ donor | Toggle (Yes / No / Not specified) | No |
| Health insurer | Text | No |

**Storage:** `SharedPreferences`. Profile photo stored as base64-encoded JPEG, max 80KB
(compressed on write). Never transmitted to any server under any condition.

**QR Code:**
- Generated client-side by `qr_flutter`
- Payload: compact JSON, example:
  `{"n":"Arjun Kumar","bg":"O+","al":"Penicillin","co":"Type 2 Diabetes","me":"Metformin 500mg","ec":"Mom:+9198XXXXXXXX","od":false}`
- Shown full-screen on tap — large enough for a scanner or camera at 30cm distance

**Lock screen accessibility:**
The foreground service notification (crash detection) includes an Android notification action:
"📋 Medical Card". Tapping this action from the lock screen opens the QR code full-screen without
requiring PIN/biometric unlock. This is the primary EMT use case.

Implementation: `flutter_local_notifications` with `NotificationAction`, navigating to
`/victim-id/qr` via deep link on tap.

**PDF export:**
- `pdf` package, A6 size (105mm × 148mm — ID card proportions)
- Layout: photo left, name/blood group right, conditions and contacts below, QR code bottom-right
- Shared via `share_plus`
- Suggested use: print and keep in wallet, or share with family

**Disclaimer shown in UI:**
"This card contains your personal health summary for emergency use only.
It is not a medical record. Data is stored only on this device and never transmitted."

---

### 5.6 AI Co-pilot

The AI co-pilot's purpose is precisely defined: it handles the questions that a POI map cannot
answer. It is not a general assistant. It is not the entry point to the app.

**Access:** Floating chat bubble FAB, bottom-right of Home Screen. One tap → AI panel slides up
as a modal bottom sheet (not a new screen — the map remains visible behind it at 30% opacity).

#### 5.6.1 What the AI handles

Questions from a bystander who has just called 112 and is waiting:
- "How do I stop the bleeding?"
- "The victim is unconscious — what do I do?"
- "Which hospital is nearest?" (answered using injected POI context)
- "The ambulance is 20 minutes away — what now?"
- "How do I describe this location to the dispatcher?"
- "I'm outside India — what number do I call?"
- "Am I legally protected if I help?"

Questions a panicked person cannot answer for themselves by looking at a map.

#### 5.6.2 What the AI does NOT handle

- Route navigation
- Diagnosing injuries
- Recommending medications or dosages
- Any question requiring real-time data it cannot verify

#### 5.6.3 Quick-chip row

Shown at top of AI panel, always visible regardless of chat history.
No voice input. STT fails at >70dB ambient noise. A crash scene routinely exceeds 80dB.
The chip row is the primary interaction mechanism.

Chips (fixed, not dynamic):
- "Stop the bleeding"
- "Victim unconscious"
- "What to do while waiting"
- "Nearest hospital?"
- "Describe my location"
- "My legal rights as helper"

Tapping a chip sends the associated query string. Response appears in the chat area below.

#### 5.6.4 Online mode — Gemini

**Model:** `gemini-2.0-flash-exp` or `gemini-2.0-flash` via `google_generative_ai` package.

**System prompt** (injected on every `generateContent` call via `systemInstruction`):

```
You are the emergency assistant in RoadSoS, a road accident response app.
You help bystanders and accident victims at the scene of road accidents in India and nearby countries.

Context for this session (updated with every message):
- User GPS: {lat}, {lng}
- District: {district_name}, {state_name}, {country_name}
- Emergency numbers here: Ambulance {amb}, Police {pol}, General Emergency {gen}
- Nearby services (nearest 5 per category):
  Hospitals: {hospital_list}
  Ambulance stations: {amb_station_list}
  Police: {police_list}

Your role:
1. Help find and contact nearby emergency services — reference them by name and distance.
2. Provide bystander first aid guidance aligned with WHO/Indian Red Cross untrained bystander
   protocols. Never exceed this scope.
3. Inform bystanders of their legal protection under Section 134A, MV Act 2019 when relevant.
4. Help bystanders describe their location to dispatchers.
5. Provide emergency numbers for other countries if the user is outside India.

Hard constraints — never break:
- Never diagnose specific injuries.
- Never recommend specific medications, dosages, or clinical procedures.
- Never claim that nearby facilities are definitely open or equipped — always say
  "call ahead to confirm" or "call 112 and they will dispatch to you".
- Never say you are an AI, a chatbot, or a language model. Just answer.
- Maximum 3 sentences per response unless the user asks for more detail.
- If unsure, default to: "Call 112 and stay on the line with the operator."

When asked about stopping bleeding:
"Apply firm, direct pressure with any clean cloth. Hold continuously — do not lift to check.
If cloth soaks through, add more on top. Keep pressure until help arrives."

When asked about an unconscious victim:
"Check for breathing — look, listen, feel. If breathing: recovery position (on their side,
top knee bent forward). If not breathing and you know CPR, begin. Call 112 immediately if
not already done."

When asked about the Good Samaritan law:
"Under Section 134A of India's Motor Vehicles Act, you are legally protected from civil and
criminal liability for helping a road accident victim in good faith. You cannot be detained,
forced to give personal information, or charged for any outcome if you acted with good intent."
```

**API call implementation:**

```dart
final model = GenerativeModel(
  model: 'gemini-2.0-flash',
  apiKey: _apiKey,
  systemInstruction: Content.system(_buildSystemPrompt(context)),
  generationConfig: GenerationConfig(
    maxOutputTokens: 200,  // enforces 3-sentence limit
    temperature: 0.2,      // low temperature = consistent, safe answers
  ),
);
final response = await model.generateContent([Content.text(userMessage)]);
```

**Error handling:** On any API error (timeout, rate limit, network failure) → immediately route to
offline mode without showing an error. The user sees a response, not an error screen.

#### 5.6.5 Offline mode — Static Q&A

File: `assets/data/offline_qa.json`. Loaded at startup into memory (≤50KB). Never triggers
a network call.

**Matching:** Tokenise and lowercase user message. Find entry with most keyword matches.
Zero-match fallback: "I can't answer that without internet. Call 112 for immediate help.
The nearest hospital on the map is {nearest_hospital_name}, {nearest_hospital_distance} away."
(The fallback always injects the nearest POI from the local data — this is possible offline.)

**UI indicator:** Badge in the AI panel header. Green dot = "AI Active". Orange dot = "Offline —
Quick Answers". The distinction is visible but not alarming.

**Minimum Q&A entries** (must cover these at minimum; the actual file should have ≥80 entries):
```json
[
  {
    "keywords": ["bleed", "blood", "wound", "cut", "hemorrhage"],
    "answer": "Apply firm direct pressure with any clean cloth. Hold without lifting. Add more cloth if it soaks through. Keep pressure until help arrives."
  },
  {
    "keywords": ["unconscious", "not responding", "unresponsive", "passed out", "fainted"],
    "answer": "Check for breathing — look for chest rise. If breathing: recovery position on their side, top knee bent. If not breathing and you know CPR, begin. Call 112 immediately."
  },
  {
    "keywords": ["waiting", "ambulance", "what do", "while", "now"],
    "answer": "Keep them still and warm. Talk to them even if unconscious. Do not give food or water. Send someone to the road junction to flag down the ambulance."
  },
  {
    "keywords": ["helmet", "remove", "take off"],
    "answer": "Do NOT remove the helmet. Incorrect removal can worsen a spinal injury. Only remove if the airway is completely blocked and you cannot open it any other way. Wait for trained responders."
  },
  {
    "keywords": ["location", "address", "where am", "describe", "tell dispatcher"],
    "answer": "Read your GPS coordinates from the map. Look for road signs, kilometre markers, or landmark names nearby. Share the Google Maps link from the Share button. Tell the operator the direction you are travelling."
  },
  {
    "keywords": ["legal", "liability", "arrested", "police", "samaritan", "protected", "rights"],
    "answer": "Under Section 134A of India's Motor Vehicles Act 2019, you are legally protected from civil and criminal liability for helping in good faith. You cannot be detained or forced to disclose personal information."
  },
  {
    "keywords": ["fire", "burning", "smoke", "petrol", "fuel"],
    "answer": "Move everyone at least 50 metres away immediately. Do not re-enter the vehicle. Call 101 for fire and 112 for all services."
  },
  {
    "keywords": ["outside india", "abroad", "foreign", "not india", "another country"],
    "answer": "Dial 112. This number connects to emergency services in most countries worldwide and redirects to the local dispatcher."
  },
  {
    "keywords": ["fracture", "broken", "bone"],
    "answer": "Do not try to straighten the limb. Support the injury with clothing or padding above and below the fracture. Keep the person still and calm until help arrives."
  },
  {
    "keywords": ["hospital", "nearest", "closest", "where"],
    "answer": "The nearest hospital is shown on the map. Tap its card to call directly. If transporting the victim yourself, call the hospital first so they prepare."
  }
]
```

---

### 5.7 Foreground Service

**Purpose:** Keep crash detection alive when the app is backgrounded.

**Implementation:** `flutter_local_notifications` with `AndroidForegroundServiceStartMode.mandatory`
and notification importance set to `Importance.low` (no sound, no vibration — just the persistent
icon in the status bar).

**Notification content:**
- Title: "RoadSoS is active"
- Body: "Monitoring for crashes. Tap to open."
- Action button: "📋 Medical Card" → deep-links to QR screen

**When service stops:** User explicitly disables it in Settings, or app is uninstalled. Not stopped
by screen off, by system memory pressure (foreground services are protected), or by the user
swiping the app away from recents (foreground services survive this on Android).

**Battery impact:** Accelerometer at 10Hz (IDLE) consumes negligible battery. GPS is polled at 1Hz
only when speed > 5 km/h (moving state). At rest: only accelerometer running.

---

## 6. Data Architecture

### 6.1 The Fallback Chain

When data is requested, the app walks this chain and stops at the first source that returns results:

```
1. User corrections (local JSON) — highest trust
         ↓ (always run, merged not replaced)
2. OSM Overpass (live, 7-day cache in SQLite)
         ↓ (if Overpass fails or cache miss)
3. data.gov.in hospital CSV (bundled asset, government-verified)
         ↓ (always active for hospitals, merged with above)
4. District tile bundle (bundled gzipped JSON, offline survival)
         ↓ (if district tile missing)
5. Nearest state capital tile (always bundled)
```

Sources 3 and 4 are always loaded and merged — they are not fallbacks to each other, they are
additive. Source 2 is merged on top when available. Source 1 overrides specific records.

**Result:** Even with zero network, zero GPS signal freshness, the user sees hundreds of POI records
sourced from pre-built district tiles and the government hospital directory.

### 6.2 Data Sources

#### Source A: OSM Overpass API (live)

URL: `https://overpass-api.de/api/interpreter`

Query executed on app launch (if online) and cached in SQLite with a 7-day TTL per district bounding box:

```
[out:json][timeout:25];
(
  node["amenity"~"hospital|clinic|doctors|pharmacy"](around:10000,{lat},{lng});
  node["emergency"="ambulance_station"](around:10000,{lat},{lng});
  node["amenity"="police"](around:10000,{lat},{lng});
  node["amenity"="fire_station"](around:10000,{lat},{lng});
  node["shop"~"car_repair|tyres"](around:20000,{lat},{lng});
  way["amenity"~"hospital|clinic"](around:10000,{lat},{lng});
);
out center body;
```

Result parsing: extract `id`, `lat`/`lon` (for nodes) or `center.lat`/`center.lon` (for ways),
`tags.name`, `tags.phone` or `tags["contact:phone"]`, `tags.amenity`, `tags.shop`.

Cache key: `overpass_{district_key}`. Invalidate after 7 days.

#### Source B: data.gov.in Hospital Directory CSV (build-time asset)

Downloaded once at build time from:
`https://data.gov.in/catalog/hospital-directory-national-health-portal`

No API key required. Released under National Data Sharing and Accessibility Policy (NDSAP).
Approximately 3,000 records with state, district, coordinates, phone, category.

Processing script (`scripts/process_hospitals.py`):
```python
import pandas as pd, json

df = pd.read_csv('nhp_hospital_directory.csv', encoding='latin-1')
df = df.dropna(subset=['Latitude', 'Longitude'])
df['lat'] = pd.to_numeric(df['Latitude'], errors='coerce')
df['lng'] = pd.to_numeric(df['Longitude'], errors='coerce')
df = df.dropna(subset=['lat', 'lng'])
df = df[(df['lat'].between(-90, 90)) & (df['lng'].between(-180, 180))]

result = {}
for _, row in df.iterrows():
    state = str(row.get('StateName', 'Unknown')).strip().upper()
    result.setdefault(state, []).append({
        'name': str(row.get('HospitalName', '')).strip(),
        'lat': round(float(row['lat']), 6),
        'lng': round(float(row['lng']), 6),
        'phone': str(row.get('PhoneNo', '')).strip(),
        'category': 'hospital',
        'source': 'govt',
        'district': str(row.get('District', '')).strip(),
    })

with open('../assets/data/hospitals_india.json', 'w', encoding='utf-8') as f:
    json.dump(result, f, ensure_ascii=False, separators=(',', ':'))

print(f"Wrote {sum(len(v) for v in result.values())} records across {len(result)} states")
```

**At runtime:** Load the state's sub-array on demand. Match to current district by the `district`
field. All records shown with "Govt" badge and "Bundled data — verify phone before visiting" notice.

#### Source C: District Tile Bundle (build-time, offline survival)

Pre-built Overpass query results for 200 Indian districts, stored as gzipped JSON at:
`assets/tiles/{STATE_CODE}-{DISTRICT_SLUG}.json.gz`

Build script (`scripts/build_district_tiles.py`):
```python
import requests, json, gzip, time, os, re

DISTRICTS = [
    # (state_code, district_name, lat, lng)
    ("TN", "Chennai", 13.0827, 80.2707),
    ("TN", "Coimbatore", 11.0168, 76.9558),
    ("MH", "Mumbai", 19.0760, 72.8777),
    ("MH", "Pune", 18.5204, 73.8567),
    ("KA", "Bengaluru", 12.9716, 77.5946),
    ("DL", "Delhi", 28.6139, 77.2090),
    ("RJ", "Jaipur", 26.9124, 75.7873),
    ("UP", "Lucknow", 26.8467, 80.9462),
    ("WB", "Kolkata", 22.5726, 88.3639),
    ("GJ", "Ahmedabad", 23.0225, 72.5714),
    # ... continue to 200 districts from NCRB accident data
]

QUERY = """[out:json][timeout:30];
(
  node["amenity"~"hospital|clinic|doctors|pharmacy"](around:15000,{lat},{lng});
  node["emergency"="ambulance_station"](around:15000,{lat},{lng});
  node["amenity"="police"](around:15000,{lat},{lng});
  node["amenity"="fire_station"](around:15000,{lat},{lng});
  node["shop"~"car_repair|tyres"](around:25000,{lat},{lng});
);
out body;"""

os.makedirs('../assets/tiles', exist_ok=True)

for state, district, lat, lng in DISTRICTS:
    query = QUERY.format(lat=lat, lng=lng)
    try:
        resp = requests.post(
            'https://overpass-api.de/api/interpreter',
            data=query, timeout=60
        )
        if resp.status_code == 200:
            slug = re.sub(r'[^a-zA-Z0-9]', '_', district)
            path = f"../assets/tiles/{state}-{slug}.json.gz"
            with gzip.open(path, 'wt', encoding='utf-8') as f:
                json.dump(resp.json(), f, ensure_ascii=False)
            count = len(resp.json().get('elements', []))
            print(f"✓ {state}-{district}: {count} POIs → {path}")
        else:
            print(f"✗ {state}-{district}: HTTP {resp.status_code}")
    except Exception as e:
        print(f"✗ {state}-{district}: {e}")
    time.sleep(3)  # Overpass rate limit: max 1 req/3s
```

**At runtime** (`DistrictTileService`):
1. Get current district name from reverse geocode (or last known district).
2. Slugify: `RegExp(r'[^a-zA-Z0-9]').allMatches` → underscore.
3. Load asset: `rootBundle.load('assets/tiles/{STATE}-{DISTRICT}.json.gz')`.
4. Decompress with `dart:io` GZipDecoder or `archive` package.
5. Parse Overpass JSON → List<Poi>.
6. If asset not found: fall through to nearest state capital tile.

#### Source D: Emergency Numbers (bundled JSON)

File: `assets/data/emergency_numbers.json` — see Section 5.1 for schema.

#### Source E: User Corrections (local JSON)

File in app documents directory: `user_corrections.json`.
Schema:
```json
[
  {
    "poi_id": "osm_node_12345678",
    "corrected_phone": "+914422001234",
    "flagged_incorrect": false,
    "note": "Phone number updated May 2026",
    "corrected_at": "2026-05-15T10:30:00Z"
  }
]
```

### 6.3 POI Fusion Pipeline

Run on every data refresh. Produces a single merged list consumed by Riverpod `PoiNotifier`.

```dart
List<Poi> fuse({
  required List<Poi> overpass,
  required List<Poi> govt,
  required List<Poi> districtTile,
  required List<UserCorrection> corrections,
  required LatLng userLocation,
}) {
  // 1. Start with all records from all sources
  final all = [...overpass, ...govt, ...districtTile];

  // 2. Deduplicate: within 100m + same category = same facility
  //    Prefer: govt > overpass > districtTile for the canonical record
  final deduped = _deduplicateByProximity(all, radiusMetres: 100);

  // 3. Apply user corrections
  for (final correction in corrections) {
    final idx = deduped.indexWhere((p) => p.sourceId == correction.poiId);
    if (idx >= 0) {
      deduped[idx] = deduped[idx].copyWith(
        phone: correction.correctedPhone ?? deduped[idx].phone,
        flaggedIncorrect: correction.flaggedIncorrect,
        source: PoiSource.userVerified,
      );
    }
  }

  // 4. Remove flagged-incorrect records
  deduped.removeWhere((p) => p.flaggedIncorrect);

  // 5. Compute distance from user, sort
  for (final p in deduped) {
    p.distanceKm = _haversine(userLocation, p.location);
  }
  deduped.sort((a, b) {
    // Hospitals first; within category, distance ascending
    final catCmp = _categoryPriority(a.category).compareTo(_categoryPriority(b.category));
    if (catCmp != 0) return catCmp;
    return a.distanceKm.compareTo(b.distanceKm);
  });

  return deduped;
}
```

### 6.4 SQLite Schema (Drift)

```dart
@DataClassName('PoiCacheEntry')
class PoiCacheTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceId => text().withLength(max: 64)();   // "osm_12345" | "govt_KA_001"
  TextColumn get name => text().withLength(max: 256)();
  TextColumn get category => text().withLength(max: 32)();
  RealColumn get lat => real()();
  RealColumn get lng => real()();
  TextColumn get phone => text().nullable()();
  TextColumn get source => text().withLength(max: 8)();      // "osm"|"govt"|"tile"|"user"
  TextColumn get districtKey => text().withLength(max: 64)();
  DateTimeColumn get fetchedAt => dateTime()();
  BoolColumn get flaggedIncorrect =>
      boolean().withDefault(const Constant(false))();
}
```

---

## 7. State Management

All business state managed via Riverpod. No `setState` in widgets except ephemeral UI state
(e.g. button animation).

### 7.1 Provider Map

```dart
// ─── Infrastructure ───────────────────────────────────────────────────────
final connectivityProvider   = StreamProvider<ConnectivityResult>(...);
final isOnlineProvider        = Provider<bool>(...);       // derived
final locationProvider        = StreamProvider<Position>(...);
final currentDistrictProvider = FutureProvider<String>(...); // cached reverse geocode

// ─── Data ─────────────────────────────────────────────────────────────────
final poiNotifierProvider     = AsyncNotifierProvider<PoiNotifier, List<Poi>>(...);
// PoiNotifier: runs fusion pipeline; refreshes on location change or manual pull

// ─── UI State ─────────────────────────────────────────────────────────────
final activeCategoriesProvider = StateProvider<Set<PoiCategory>>(...);
// Default: {hospital, ambulanceStation, police}

// ─── App State Machine ────────────────────────────────────────────────────
final appStateProvider = StateNotifierProvider<AppStateNotifier, AppState>(...);
// AppState: idle | active | crashCountdown(secondsRemaining) | emergency(EmergencyEvent)

// ─── Crash Detection ──────────────────────────────────────────────────────
final crashDetectorProvider = StateNotifierProvider<CrashDetector, CrashState>(...);
// CrashDetector: manages sensor subscriptions, speed gate, G-force evaluation

// ─── Profile ──────────────────────────────────────────────────────────────
final victimProfileProvider = StateNotifierProvider<VictimProfileNotifier, VictimProfile>(...);
// Reads/writes SharedPreferences; never touches network

// ─── AI ───────────────────────────────────────────────────────────────────
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>(...);
// ChatNotifier: routes to Gemini or static Q&A based on isOnlineProvider
// Injects POI context from poiNotifierProvider into every Gemini call
```

### 7.2 AppState Transitions

```dart
sealed class AppState {}
class IdleState extends AppState {}
class ActiveState extends AppState {}
class CrashCountdownState extends AppState {
  final int secondsRemaining;
  final bool triggeredBySensor; // vs manual SOS
}
class EmergencyState extends AppState {
  final DateTime triggeredAt;
  final LatLng location;
  final String district;
  final List<String> notifiedContacts;
}
```

Transitions:
- `IdleState → ActiveState`: user opens app
- `ActiveState → CrashCountdownState`: sensor fires OR manual SOS long-press
- `IdleState → CrashCountdownState`: sensor fires while app is backgrounded (foreground service)
- `CrashCountdownState → EmergencyState`: countdown elapses
- `CrashCountdownState → ActiveState`: user cancels
- `EmergencyState → ActiveState`: user dismisses panel

---

## 8. Navigation (go_router)

```dart
GoRouter(
  routes: [
    GoRoute(
      path: '/',
      builder: (_, __) => const HomeScreen(),
    ),
    GoRoute(
      path: '/crash-countdown',
      builder: (_, state) => CrashCountdownScreen(
        extra: state.extra as CrashCountdownState,
      ),
    ),
    GoRoute(
      path: '/victim-id',
      builder: (_, __) => const VictimIdScreen(),
      routes: [
        GoRoute(
          path: 'qr',
          builder: (_, __) => const VictimQrScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/ai',
      builder: (_, __) => const AiCopilotScreen(),
    ),
    GoRoute(
      path: '/settings',
      builder: (_, __) => const SettingsScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (_, __) => const OnboardingScreen(),
    ),
  ],
  redirect: (context, state) {
    final onboarded = prefs.getBool('onboarding_complete') ?? false;
    if (!onboarded && state.matchedLocation != '/onboarding') return '/onboarding';
    return null;
  },
)
```

---

## 9. Compliance and Legal Requirements

### 9.1 DPDPA 2023 — Digital Personal Data Protection Act

**Consent screen (first launch, before any sensor access):**

```
RoadSoS needs the following to help you:

📍 Location
   Your GPS coordinates are used to find nearby hospitals,
   police stations, and emergency services.
   When you ask the AI a question with internet access,
   your location is sent to Google's AI service to give
   you relevant answers. At all other times, it stays on
   this device.

🏥 Health profile (optional)
   If you set up a Victim ID card, that data is stored
   only on this device. It is never uploaded anywhere,
   and you can delete it at any time.

📱 SMS (only when SOS is activated)
   If a crash is detected, the app will open your SMS
   app pre-filled with your location to send to your
   emergency contacts. You must tap Send.

You can change these at any time in Settings.

   [ Agree and continue ]   [ Exit app ]
```

Consent stored as `bool dpdpa_consent_v1 = true` in `SharedPreferences`.
If consent not given: app shows only the emergency dial bar (112 / 108 / 100) as static buttons.
No location services. No AI. Just the dial bar — which is always safe to show without consent.

**Data minimisation:**
- Location is only read when app is active or crash detection service is running.
- Location is transmitted to Gemini only when user sends an AI message and `isOnline == true`.
- Health data (Victim ID) is never transmitted, not even to error reporting services.

**Right to erasure:**
Settings → Clear all my data → deletes `SharedPreferences`, SQLite DB, user corrections JSON,
all tile cache. Uninstalling the app achieves the same.

### 9.2 Medical Disclaimer

Persistent banner at bottom of AI panel:
"Bystander guidance only — not a substitute for professional medical care."

On Victim ID screen:
"Emergency reference only. Not a medical record. Data stored only on this device."

### 9.3 Good Samaritan Notice (in app, not just in AI)

On the Emergency Response Panel, below the action buttons:
"Section 134A, MV Act 2019: You are legally protected for helping in good faith."
Tapping the text opens a modal with the full legal summary (100 words, plain language).

This is not legal advice. It is a statement of existing law that reduces the documented barrier to
bystander action in India. It is within the scope of a road safety application.

### 9.4 Emergency Number Disclaimer

Below every dial bar: "Numbers may change — verify locally if unsure."

### 9.5 Data Freshness Disclosure

Every POI card shows:
- OSM records: "Fetched {N} days ago" (computed from SQLite `fetchedAt`)
- Govt CSV: "Govt directory — verify phone before visiting"
- District tile: "Pre-loaded data — verify before visiting"
- User-corrected: "You updated this" + date

---

## 10. Permissions

**Android manifest declarations and runtime request strategy:**

| Permission | `AndroidManifest.xml` | Runtime request | Trigger |
|---|---|---|---|
| `ACCESS_FINE_LOCATION` | Required | Yes | On launch, after consent |
| `ACCESS_COARSE_LOCATION` | Required | Yes | On launch (fallback) |
| `FOREGROUND_SERVICE` | Required | No (granted at install) | — |
| `FOREGROUND_SERVICE_HEALTH` | Required (API 34+) | No | — |
| `POST_NOTIFICATIONS` | Required (API 33+) | Yes | On launch |
| `SEND_SMS` | Declared | Yes | First SOS activation |
| `CALL_PHONE` | Declared | No | `url_launcher` handles |
| `INTERNET` | Required | No | Silent |
| `ACCESS_NETWORK_STATE` | Required | No | Silent |
| `RECEIVE_BOOT_COMPLETED` | Declared | No | Restart service |
| `CAMERA` | Declared | Yes | Victim ID photo field |

**Do not request `BACKGROUND_LOCATION`**. The foreground service approach keeps the sensor active
without requiring background location permission, which triggers Play Store review and user
rejection rates >60%.

---

## 11. pubspec.yaml (Final)

```yaml
name: roadsos
description: Zero-friction emergency resource finder for road accident scenes.
publish_to: none
version: 1.0.0+1

environment:
  sdk: ">=3.2.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

  # Navigation
  go_router: ^13.2.0

  # State management
  flutter_riverpod: ^2.5.1
  riverpod_annotation: ^2.3.4

  # Maps
  flutter_map: ^6.1.0
  flutter_map_tile_caching: ^9.1.0
  latlong2: ^0.9.0

  # Location and sensors
  geolocator: ^11.0.0
  sensors_plus: ^4.0.2
  permission_handler: ^11.3.0

  # Network
  dio: ^5.4.3
  connectivity_plus: ^6.0.3
  http: ^1.6.0

  # Local database — POI cache
  drift: ^2.18.0
  sqlite3_flutter_libs: ^0.5.22
  path_provider: ^2.1.3
  path: ^1.9.0

  # Notifications and foreground service
  flutter_local_notifications: ^17.1.2

  # Intents (dial, SMS, share, maps)
  url_launcher: ^6.3.2
  share_plus: ^10.0.2

  # QR code
  qr_flutter: ^4.1.0

  # PDF generation
  pdf: ^3.12.0

  # AI
  google_generative_ai: ^0.4.3

  # Local asset decompression
  archive: ^3.4.10

  # Persistent storage
  shared_preferences: ^2.2.3

  # Utilities
  intl: ^0.19.0
  uuid: ^4.3.3
  cupertino_icons: ^1.0.6

  # Crash alarm audio
  audioplayers: ^6.6.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0
  build_runner: ^2.4.9
  drift_dev: ^2.18.0
  riverpod_generator: ^2.4.0

flutter:
  uses-material-design: true
  assets:
    - assets/data/
    - assets/tiles/
    - assets/icons/
    - assets/audio/
```

**Packages intentionally excluded (with reasons):**
- `telephony` — unmaintained; compile failure on Android SDK 34+. `url_launcher` is the correct
  and reliable replacement for both SMS and dial.
- `flutter_ble_peripheral` — NDK-specific compile failures; BLE advertising is not a core feature.
- `flutter_tts` — out of scope. No voice output.
- `volume_controller` — out of scope.
- Any `firebase_*` packages — Firebase is not required. `flutter_local_notifications` handles
  all notification needs. Removing Firebase removes the `google-services.json` dependency that
  breaks the Saarathi build.

---

## 12. Build Fix Sequence (for AI coding agent on Saarathi repo)

Execute in this exact order. Do not skip steps.

```bash
# ── Step 1: Fix missing Gradle wrapper JAR ─────────────────────────────────
curl -L \
  https://github.com/gradle/gradle/raw/v8.3.0/gradle/wrapper/gradle-wrapper.jar \
  -o android/gradle/wrapper/gradle-wrapper.jar

# ── Step 2: Remove Firebase dependency (root cause of Saarathi build failure)
# In android/build.gradle — remove:
#   classpath 'com.google.gms:google-services:X.X.X'
#
# In android/app/build.gradle — remove:
#   apply plugin: 'com.google.gms.google-services'
#   (and any firebase_ implementation lines)
#
# Remove google-services.json dependency entirely.
# Replace any firebase_messaging or fcm usage in Dart with
# flutter_local_notifications.

# ── Step 3: Replace pubspec.yaml with the version in Section 11 of this PRD
flutter pub get

# ── Step 4: Run code generators (Drift + Riverpod)
flutter pub run build_runner build --delete-conflicting-outputs

# ── Step 5: Verify environment
flutter doctor -v

# ── Step 6: Build
flutter build apk --debug
```

**If build still fails after Step 6:** Run `flutter doctor -v` and address any listed issues
(Java version mismatch, Android SDK path, NDK version). The most common remaining issue is
Java 17 required — Android Studio bundles it; if using system Java, ensure `JAVA_HOME` points to
Java 17+.

---

## 13. File Structure (Target)

```
lib/
├── main.dart
│
├── core/
│   ├── router/
│   │   └── app_router.dart
│   ├── theme/
│   │   └── app_theme.dart
│   └── constants/
│       ├── poi_categories.dart
│       └── app_strings.dart
│
├── features/
│   ├── home/
│   │   ├── home_screen.dart
│   │   └── widgets/
│   │       ├── emergency_dial_bar.dart
│   │       ├── poi_map.dart
│   │       ├── category_filter_row.dart
│   │       ├── poi_bottom_sheet.dart
│   │       ├── poi_card.dart
│   │       └── emergency_response_panel.dart   ← visible only in EmergencyState
│   │
│   ├── crash_detection/
│   │   └── crash_countdown_screen.dart
│   │
│   ├── victim_id/
│   │   ├── victim_id_screen.dart
│   │   ├── victim_qr_screen.dart
│   │   └── victim_id_pdf.dart
│   │
│   ├── ai_copilot/
│   │   ├── ai_copilot_screen.dart
│   │   └── widgets/
│   │       ├── quick_chip_row.dart
│   │       └── chat_message_tile.dart
│   │
│   ├── settings/
│   │   └── settings_screen.dart
│   │
│   └── onboarding/
│       └── onboarding_screen.dart
│
├── shared/
│   ├── models/
│   │   ├── poi.dart
│   │   ├── victim_profile.dart
│   │   ├── chat_message.dart
│   │   └── app_state.dart
│   │
│   ├── providers/
│   │   ├── connectivity_provider.dart
│   │   ├── location_provider.dart
│   │   ├── poi_provider.dart
│   │   ├── app_state_provider.dart
│   │   ├── crash_detector_provider.dart
│   │   ├── victim_profile_provider.dart
│   │   └── chat_provider.dart
│   │
│   └── services/
│       ├── overpass_service.dart
│       ├── govt_hospital_service.dart
│       ├── district_tile_service.dart
│       ├── poi_fusion_service.dart
│       ├── gemini_service.dart
│       ├── offline_qa_service.dart
│       ├── sensor_service.dart
│       ├── sms_service.dart
│       └── notification_service.dart
│
└── database/
    ├── app_database.dart
    └── app_database.g.dart              ← generated; do not edit manually

assets/
├── data/
│   ├── emergency_numbers.json
│   ├── hospitals_india.json             ← from scripts/process_hospitals.py
│   └── offline_qa.json
├── tiles/
│   ├── TN-Chennai.json.gz
│   ├── TN-Coimbatore.json.gz
│   └── ...                             ← from scripts/build_district_tiles.py
├── icons/
│   ├── hospital.png
│   ├── police.png
│   └── ...
└── audio/
    └── alarm.mp3

scripts/                                ← build-time only, not bundled in APK
├── process_hospitals.py
└── build_district_tiles.py
```

---

## 14. Offline Behaviour Matrix

| Capability | Online | Data-offline (cellular only) | Fully offline (no signal) |
|---|---|---|---|
| Emergency dial bar | ✅ JSON asset | ✅ JSON asset | ✅ JSON asset + cellular voice |
| POI markers on map | ✅ Overpass + govt + tile | ✅ govt + tile (7-day cache) | ✅ govt + tile |
| Map tile background | ✅ OSM | ✅ if pre-cached | ❌ grey canvas (POI markers still shown) |
| Emergency Response Panel | ✅ | ✅ | ✅ |
| SMS alert | ✅ cellular | ✅ cellular | ✅ cellular (SMS ≠ data) |
| Phone call | ✅ cellular | ✅ cellular | ✅ cellular |
| AI co-pilot | ✅ Gemini + POI | ❌ static Q&A + nearest POI from local | ❌ static Q&A + nearest POI from local |
| Crash detection | ✅ | ✅ | ✅ |
| Victim ID / QR | ✅ | ✅ | ✅ |
| Reverse geocode | ✅ | ❌ shows lat/lng + "Location unknown" | ❌ shows lat/lng |
| Tile pre-caching | ✅ background | ❌ | ❌ |

---

## 15. UX Constraints (Non-Negotiable)

These are engineering requirements, not design preferences. They follow from the cognitive science
of acute stress (prefrontal cortex suppression, tunnel vision, working memory reduction to 2–3 items).

1. **Every critical action ≤ 2 taps from app open.** Dial ambulance: 1 tap. Manual SOS: 1 long
   press. Nearest hospital call: tap POI card → tap phone number.

2. **No action in the Emergency Response Panel requires text input.** All buttons. All one tap.

3. **No voice input anywhere.** Crash scene ambient noise routinely exceeds 80dB. STT word error
   rate at 80dB is >40%. Quick-tap chips are the interaction model.

4. **The dial bar is always visible.** It cannot be scrolled away, collapsed, or hidden by any
   other UI element. It is the one thing that must never disappear.

5. **Loading states show something useful, not a spinner.** If POIs are loading, show the dial bar
   and "Finding nearby services..." with a progress indicator below the bar. Never a blank screen.

6. **Error states show the fallback, not the error.** If Overpass fails, show district tile results
   with a silent "Using offline data" badge. Not an error dialog. Not a retry button as the primary
   UI element.

7. **Minimum touch target: 48×48dp** on all interactive elements. Emergency dial buttons:
   minimum 60dp height. SOS FAB: 64×64dp minimum.

8. **Dark mode required.** Night crash rate is elevated. The app must be readable with no ambient
   light. Use system dark mode detection (`ThemeMode.system`).

9. **Text size minimum: 14sp body, 16sp buttons, 18sp primary actions.** Users may have compromised
   vision (dust, blood, shock). No text below 12sp anywhere in the app.

---

## 16. Evaluation Rubric — Final Mapping

| Criterion | Implementation | Evidence to show evaluators |
|---|---|---|
| **Reliability and data accuracy** | Three-source fusion; data age badge on every POI; user correction mechanism; flagging stale data | Show a POI card with "Fetched 2 hours ago" vs "Bundled data — verify". Show the fusion pipeline in code. |
| **Number of contacts fetched** | 3,000 govt hospital records (offline) + live Overpass (typically 50–200 records/district) + district tile (200 districts × avg 80 POIs) | Run the app offline in a demo district. Count the POI cards visible. Run `scripts/process_hospitals.py` output live. |
| **Offline functionality** | District tile + govt CSV + static Q&A + cellular SMS/dial | Enable airplane mode live in the demo. Show the map still has results. Ask AI a question — gets answered from static Q&A. |
| **Innovation & additional features** | Crash auto-detection with speed gate; Victim ID card with EMT-accessible QR on lock screen; Good Samaritan law reminder; structured SMS to 112 | Demo crash detection screen. Show Victim ID QR from lock screen. Show the legal notice. Show the SMS payload format. |
| **Information integration across countries** | BIMSTEC emergency number JSON; country auto-detected from GPS; AI aware of country context; OSM Overpass works globally | Switch phone GPS to a Bangladesh coordinate. Show the dial bar change to BD numbers. |

---

## 17. Out of Scope

Do not implement the following. They increase build time with no rubric return:

- Turn-by-turn route navigation
- Drowsiness detection (camera-based)
- Fleet management / multi-driver tracking
- BLE peripheral advertising
- Real-time crowdsourced data sync (requires a backend)
- Insurance claim automation
- In-app payments or subscriptions

---

*End of document — RoadSoS PRD v2.0*

*Every data format, algorithm threshold, API call, asset path, package version, legal reference, and
file name in this document is specified at implementation level. An AI coding agent should be able
to produce a working Flutter codebase directly from this document without requiring clarification.*
