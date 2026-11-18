# LapDeck 🎛️
### Tactile Mobile Control Deck & Remote Host Manager for Android

**LapDeck** is a high-density, industrial-grade remote management client for Android. Built specifically to interact with your workstation ecosystem over encrypted **Tailscale WireGuard** mesh networking, it gives you tactile control over your Linux and Windows machines right from your phone.

Designed strictly under the **Anti-AI-Slop Design System**: zero generic pastel gradients, zero rounded pill cards, zero bloated decorative animations. Pure functional utility, high-contrast monospace typography, and mechanical physical feedback.

---

## ⚡ Core Capabilities

- **Tailscale Mesh Native**: Seamlessly bridges your connected Android device (`mochi-pxl` / Pixel 7a) to your remote workstations over static CGNAT IPs (`100.x.y.z`), bypassing public port forwarding, NAT traversal issues, and unencrypted relays.
- **Peer Host Rack Selector**:
  - `surajworklaptop` (Linux Ubuntu 24.04 LTS • `100.118.7.117`)
  - `mochirondesu` (Windows 11 / WSL2 • `100.79.206.82` • Direct LAN `192.168.29.61:41641`)
  - Live latency readout, OS badges, and real-time connectivity status.
- **Dual Mode Operation**:
  1. **Tactical Deck**: Asymmetric quick-action pads for instant execution:
     - **Host Telemetry**: `uptime`, memory allocations (`free -h`), and root disk capacity (`df -h`).
     - **Top Processes**: Dynamic process tree sorted by CPU and memory load (`ps -eo ...`).
     - **Tailscale Mesh Diagnostics**: Peer routing status, direct route latency, and DERP fallback state.
     - **Workstation Security**: Instant display lock (`loginctl lock-session`) and process inspection.
  2. **Full PTY Terminal Bay**:
     - Embedded xterm-256color interactive shell with full ANSI color output.
     - Tactile hardware modifier keybar: `[CTRL]`, `[CTRL-C]`, `[ESC]`, `[TAB]`, `[ | ]`, `[ ~ ]`, `[ / ]`, `[ ↑ ]`, `[ ↓ ]`.
     - Direct command input with scrollable history and buffer export.
- **Lap-Dog Companion Integration**:
  - Full native bridge to the [`lap-dog`](https://github.com/mochiron-desu/lap-dog) background security daemon.
  - Arm and disarm Away Mode (`lapdog away` / `lapdog back`) directly from your pocket.
  - Live inspection of PAM authentication attempts, failed logins, and security audit logs.
- **Hardware-Backed Keystore**:
  - Passwords and Ed25519 / RSA private keys stored securely using Android Keystore encryption via `FlutterSecureStorage`.
  - Zero plain-text credential persistence.

---

## 🏗️ Architecture

```
lib/
├── main.dart                      # App entry point, system UI styling & DI
├── models/
│   ├── host_target.dart           # Peer host schema, OS metadata, Tailscale IPs
│   └── command_action.dart        # Quick action definitions & execution policies
├── services/
│   ├── ssh_service.dart           # dartssh2 client, PTY streaming & execution engine
│   └── storage_service.dart       # SharedPreferences + Android Keystore integration
├── theme/
│   └── deck_theme.dart            # Anti-AI-Slop industrial design tokens & typography
└── ui/
    ├── screens/
    │   ├── deck_screen.dart       # Tactical master deck & viewmode router
    │   └── host_config_dialog.dart# Node enrollment & credential manager
    └── widgets/
        ├── deck_header.dart       # Hardware-style topbar with status LED
        ├── host_rack_selector.dart# Tactile rackmount chassis selector
        ├── quick_action_pad.dart  # Asymmetric command launcher grid
        └── terminal_bay.dart      # Monospace terminal view with modifier keybar
```

---

## 🚀 Running on Connected Android Device

### 1. Build and Run via ADB
```bash
# Verify connected device (e.g. Pixel 7a)
flutter devices

# Run directly on your connected phone in release mode
flutter run -d 33281JEHN01757 --release
```

### 2. Build Release APK
```bash
flutter build apk --release
# Generated APK: build/app/outputs/flutter-apk/app-release.apk
```

---

## 🔒 Security & Connectivity Blueprint

1. **Authentication Choices**:
   - **Tailscale SSH**: Zero key exchange required. Relies on Tailscale node identity and WireGuard encryption.
   - **Ed25519 / RSA Key**: Upload your SSH private key into the app; stored in encrypted Android Keystore.
   - **Password**: Standard credential authentication with in-memory hashing.
2. **Access Control**:
   - No external analytical trackers.
   - No cloud backends or third-party relays.
   - 100% peer-to-peer over your private Tailscale tailnet.

---

## 📜 License & Author

Crafted for **Suraj (Mochi)** under personal identity `mochiron-desu`.
Part of the personal workstation management suite alongside `lap-dog` and `telegram-antigravity-connector`.
