# LG webOS Wi-Fi Remote

A cross-platform **Flutter** app (iOS + Android) that discovers **LG webOS TVs**
on your local Wi-Fi network, pairs with them over the LG **SSAP WebSocket**
protocol, stores the returned client-key, and gives you a working on-screen
remote — no backend, no manual IP typing as the primary path, no vendor cloud.

> Package name: `lg_webos_wifi_remote` · Flutter stable · Dart null-safety

---

## Overview

The app talks directly to the TV on your LAN:

1. **Discover** — sends SSDP/UPnP `M-SEARCH` multicasts and lists responding LG TVs.
2. **Pair** — opens a WebSocket to the TV (`ws://<ip>:3000`, falling back to
   `wss://<ip>:3001`), sends an SSAP `register` request, and waits for you to
   accept the prompt on the TV.
3. **Store** — saves the TV's `client-key` locally with `shared_preferences` so
   future connections skip the prompt.
4. **Control** — sends SSAP commands (volume, mute, toast, power) and routes
   directional/Home/Back/OK through LG's pointer input socket.

## MVP Features

- 🔎 Auto-discovery of LG webOS TVs via SSDP/UPnP multicast
- 📺 Device list with name, IP, and (when available) the device-description URL
- 🔌 WebSocket connect with `ws://:3000` → `wss://:3001` fallback
- 🤝 Pairing with on-screen approval instructions + retry/cancel
- 💾 Client-key persistence and silent reconnect
- 🎛️ Remote screen: Power Off, Home, Back, D-pad (Up/Down/Left/Right), OK,
  Volume Up/Down, Mute toggle, and a Toast test button
- ⚡ Power **on** via Wake-on-LAN (learns the TV's MAC while connected)
- ⚠️ Clear, non-silent error reporting throughout the UI
- 🍏 iOS local-network permission setup
- 🤖 Android network/multicast permissions + MulticastLock
- ✅ GitHub Actions CI (format, analyze, test)

## Project Structure

```
lib/
  main.dart                      # App entry; launches the scan screen
  models/
    lg_tv_device.dart            # TV model + JSON (de)serialization
  services/
    ssdp_discovery_service.dart  # SSDP/UPnP M-SEARCH discovery
    lg_webos_service.dart        # SSAP WebSocket: connect/register/commands
    wake_on_lan_service.dart     # Wake-on-LAN magic-packet sender
    paired_tv_store.dart         # shared_preferences storage of paired TVs
  screens/
    scan_screen.dart             # Discover + list TVs
    pairing_screen.dart          # Connect, register, show prompt
    remote_screen.dart           # The working remote
  widgets/
    remote_button.dart           # Reusable remote button
```

---

## Prerequisites

- **Flutter SDK** (stable channel) — <https://docs.flutter.dev/get-started/install>
- **Dart** (bundled with Flutter)
- An **LG webOS TV** on the same Wi-Fi network as your phone
- For Android: **Android Studio** / Android SDK + a device or emulator
- For iOS: a **Mac** with **Xcode** and an Apple developer account (free tier
  works for on-device testing)

Verify your toolchain:

```bash
flutter doctor
```

## Windows Development Setup

This repo was scaffolded and validated on Windows.

```powershell
# 1. Clone
git clone https://github.com/SamEhr44/TVRemoteProject.git
cd TVRemoteProject

# 2. Dependencies
flutter pub get

# 3. Static checks + tests
flutter analyze
flutter test

# 4. Run on a connected Android device (Android SDK required)
flutter run
```

> iOS apps cannot be built on Windows — use a Mac for iOS (see below). On
> Windows you can still develop, analyze, test, and run on Android.

## Android Testing Setup

1. Install **Android Studio** and let it install the Android SDK + platform tools.
2. Enable **Developer Options → USB debugging** on your phone (or create an emulator).
3. Confirm the device is visible:
   ```bash
   flutter devices
   ```
4. Run:
   ```bash
   flutter run
   ```
5. Make sure the phone is on the **same Wi-Fi** as the TV, then tap
   **Scan for LG TVs**.

Permissions used (declared in `android/app/src/main/AndroidManifest.xml`):

- `INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`
- `CHANGE_WIFI_MULTICAST_STATE` — for the SSDP `MulticastLock` acquired in
  `MainActivity.kt`.

## iOS / macOS Deployment Setup

Build and run on iPhone **from a Mac**:

1. **Clone the repo:**
   ```bash
   git clone https://github.com/SamEhr44/TVRemoteProject.git
   cd TVRemoteProject
   ```

2. **Install Flutter dependencies:**
   ```bash
   flutter pub get
   ```

3. **Install iOS pods:**
   ```bash
   cd ios
   pod install
   cd ..
   ```

4. **Open the iOS project:**
   ```bash
   open ios/Runner.xcworkspace
   ```

5. **In Xcode:**
   - Select a **development team** (Signing & Capabilities).
   - Set a unique **bundle identifier** (e.g. `com.yourname.lgwebosremote`).
   - Confirm the **local network permission** key exists in `Info.plist`
     (`NSLocalNetworkUsageDescription` — already included).
   - Connect your **iPhone** and trust the computer.
   - **Build and run** (▶).

6. **CLI build (optional):**
   ```bash
   flutter build ios
   ```

> **iOS multicast note:** iOS restricts sending to multicast addresses. SSDP
> replies to a unicast M-SEARCH generally work under the standard local-network
> permission. If discovery is blocked on a device, Apple's
> **Multicast Networking entitlement**
> (`com.apple.developer.networking.multicast`) may be required; it must be
> requested from Apple and added to the provisioning profile. The first launch
> will prompt the user to allow local network access — this must be accepted.

## GitHub Clone Instructions

```bash
git clone https://github.com/SamEhr44/TVRemoteProject.git
cd TVRemoteProject
flutter pub get
```

---

## LG TV Setup

1. Connect the TV to the **same Wi-Fi** (or wired LAN on the same subnet) as
   your phone.
2. On the TV, enable mobile/LAN control. Depending on webOS version this lives
   under settings such as:
   - **General → Mobile TV On / Turn on via Wi-Fi**
   - **Connection / Network → LG Connect Apps** (older models)
3. Keep the TV on for first-time pairing (you must physically accept the prompt).

### How Pairing Works

- The app connects and sends an SSAP `register` message including a permission
  manifest.
- The TV shows an **on-screen approval prompt** — the app displays
  *"Accept the pairing request on your LG TV."*
- When you accept, the TV returns a **`client-key`**, which the app stores.
- On later connections the stored key is sent in the `register` message, so the
  TV reconnects **without** prompting again.
- Directional buttons (Home/Back/arrows/OK) use LG's **pointer input socket**,
  obtained via `ssap://com.webos.service.networkinput/getPointerInputSocket`.
  Support and exact behavior can vary by webOS version; if a TV doesn't expose
  this socket the app shows a clear error rather than failing silently.

---

## Troubleshooting

- **Phone and TV must be on the same Wi-Fi.** Different SSIDs, guest networks,
  or VLANs will prevent discovery and control.
- **iOS local network permission.** On first launch iOS prompts for local
  network access — you must allow it. If you declined, enable it under
  **Settings → Privacy & Security → Local Network**, or
  **Settings → [the app] → Local Network**.
- **Router AP/client isolation.** Many routers have "AP isolation" / "client
  isolation" that blocks device-to-device traffic. Disable it.
- **Multicast/SSDP blocked.** Some routers and mesh systems drop multicast.
  Try moving both devices to the same band/AP, or test on a simple network.
- **Enable mobile control on the TV.** See *LG TV Setup* above — discovery can
  succeed but control fail if this is off.
- **Accept the pairing prompt.** If pairing "times out," it usually means the
  on-screen prompt was not accepted in time. Retry and watch the TV.
- **Power on (Wake-on-LAN).** The app sends Power **Off** via SSAP and powers
  the TV back **on** with a Wake-on-LAN magic packet. For this to work:
  - You must have **connected to the TV at least once while it was on** — the
    app learns the TV's MAC from `connectionmanager/getStatus` and stores it.
    Until then, the **Wake** button reports that you need to connect once first.
  - The TV must have a **WoL-capable setting enabled**, e.g. LG's *Mobile TV On*
    / *Turn on via Wi-Fi* (often under General or Network settings). Some models
    only wake reliably over **wired Ethernet**.
  - Phone and TV must be on the **same subnet** — magic packets are LAN
    broadcasts and do not cross routers/VLANs.
  - Wake is offered on the **Previously paired** list (scan screen) and in the
    remote's connection bar after the link drops (e.g. right after Power Off).
- **Directional input differences.** Some webOS versions handle the pointer
  input socket differently; if arrows/OK error out, the rest of the remote
  (volume, mute, toast, power, home) still works.
- **Android multicast.** The app acquires a `MulticastLock`; if your device is
  aggressive about Wi-Fi power saving, keep the screen on during a scan.

---

## Development

```bash
flutter pub get
dart format .
flutter analyze
flutter test
flutter run
```

Continuous integration (`.github/workflows/flutter-ci.yml`) runs on every push
and pull request to `main`: `flutter pub get` → `dart format` check →
`flutter analyze` → `flutter test`.

## Tech Stack

- **Flutter / Dart** (null-safe)
- **`RawDatagramSocket`** (`dart:io`) for SSDP discovery and Wake-on-LAN
- **`web_socket_channel`** for the SSAP WebSocket
- **`shared_preferences`** for local storage of paired TVs / client keys
- No backend.

## License

Provided as-is for personal/educational use. LG and webOS are trademarks of
LG Electronics; this project is not affiliated with or endorsed by LG.
