# ResQLink — Disaster Response Platform

ResQLink is a multi-platform disaster response system that combines a real-time admin web dashboard, an offline-capable Android mobile app, and ESP32 firmware nodes into a unified emergency response network.

---

## 📦 Repository Structure

```
RESQLINK/
├── web/          # Next.js admin dashboard (disaster command centre)
├── mobile/       # Flutter Android app (field rescue mobile app)
├── hardware/     # ESP32 firmware (BLE/WiFi mesh sensor nodes)
├── releases/     # Pre-built APK release files
├── docs/         # Project documentation & architecture files
│   ├── RESQLINK.pdf
│   ├── system_architecture.md
│   └── tech_stack.txt
└── README.md     # This file
```

---

## 🌐 Web — Admin Dashboard (`web/`)

A Next.js web application providing the disaster command centre interface for administrators.

**Key features:**
- Live SOS/rescue request feed with GPS location
- Out-of-region verification workflow
- AI triage & resource dispatch
- Leaflet map with flood zone overlay
- Offline mesh telemetry display

**Setup:**
```bash
cd web
npm install
cp .env.example .env        # fill in your Supabase credentials
npm run dev                  # runs on http://localhost:3000
```

**Environment variables (`.env`):**
| Variable | Description |
|---|---|
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_ANON_KEY` | Your Supabase anonymous key |
| `GROQ_API_KEY` | Groq API key for AI triage |

**Production build:**
```bash
cd web
npm run build
npm start
```

---

## 📱 Mobile — Android App (`mobile/`)

A Flutter Android application for field rescue teams and affected civilians. Works **fully offline** via BLE mesh networking.

**Key features:**
- SOS beacon / distress signal broadcasting
- Offline P2P Bluetooth mesh relay network
- Tactical map with live signal index
- Emergency SMS portal (pre-filled templates)
- Role-based UI: Victim / Relay / Command

**Setup:**
```bash
cd mobile
flutter pub get
flutter run                  # connect Android device or emulator
```

**Build APK:**
```bash
cd mobile
flutter build apk --release --target-platform android-arm64
# Output: mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

---

## ⚙️ Hardware — ESP32 Firmware (`hardware/`)

C++ firmware for ESP32 nodes that act as BLE/WiFi mesh relay points and environmental sensors deployed in disaster-affected zones.

**Key features:**
- BLE mesh broadcasting of SOS signals
- WiFi bridge mode for internet uplink
- Environmental sensor integration (temperature, flood depth)

**Files:**
| File | Description |
|---|---|
| `espcode.c++` | Main firmware source code |
| `esp32_circuit_diagram.jpg` | Hardware wiring schematic |
| `firmware_flow_chart.jpg` | Firmware execution flow |
| `deployment_guide.txt` | Field deployment instructions |
| `system_architecture.md` | Firmware architecture notes |

**Flash firmware:**
```bash
# Using Arduino IDE or PlatformIO
# Open hardware/espcode.c++ and flash to ESP32 board
```

---

## 🚀 Quick Start (Full Stack)

```bash
# 1. Start the web dashboard
cd web && npm install && npm run dev

# 2. Flash firmware to ESP32 nodes (see hardware/deployment_guide.txt)

# 3. Install the Android app
adb install releases/resqlink_mobile_arm64.apk
# or build from source: cd mobile && flutter build apk --release
```

---

## 📐 System Architecture

See [`docs/system_architecture.md`](./docs/system_architecture.md) for the full architecture diagram and inter-component communication protocols.

---

## 📄 License

© ResQLink Team. All rights reserved.
