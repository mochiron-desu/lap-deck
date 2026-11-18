# LAPDECK Agent Development Rules (`AGENTS.md`)

This document is the authoritative engineering governance specification for **LAPDECK** (`com.mochirondesu.lap_deck`). Every AI coding agent and human contributor must read and follow these rules before modifying any code, configuration, or script in this repository.

Before relying on an implementation-specific class, method, field, command or file reference in this document, verify that it still exists in the current repository. Documentation is not proof of implementation. If the implementation differs, inspect the source and update the documentation rather than creating code to match a stale description

> **UI/UX Requirement**: Before modifying any screen, widget, dialog, bottom sheet, theme token, layout, or user flow under `lib/ui/` or `lib/theme/`, you **MUST** read and follow [`docs/UI_UX_RULES.md`](docs/UI_UX_RULES.md).

---

## 1. Project Identity and Responsibilities

### 1.1 What LAPDECK Is
LAPDECK is a **private infrastructure and remote-workstation command deck for Android**, built with Flutter (Material 3, Dart `^3.7.0`) and `dartssh2`. It operates over an encrypted **Tailscale WireGuard mesh network** (CGNAT `100.64.0.0/10`) with optional direct LAN failover (`192.168.x.x`) to manage real Linux, Windows, and macOS workstations (`surajworklaptop`, `mochirondesu`, and user-enrolled nodes).

LAPDECK is **not** a generic SaaS analytics dashboard, mock prototype, or consumer productivity app. Every button, status indicator, and terminal session interacts with live remote machines and physical desktop sessions.

### 1.2 Core Capabilities
1. **Multi-Layer Network & Service Probing**: Independently verifies local Tailscale VPN interface state, peer host reachability (Tailscale TCP, LAN TCP failover, ICMP ping), SSH daemon port availability, remote telemetry script execution, and `lap-dog` security daemon health.
2. **Canonical Target-Device Management**: Persists enrolled workstations (`HostTarget`) in `SharedPreferences` and hardware-backed credentials in Android Keystore via `FlutterSecureStorage`, maintaining a single explicit global target device across tabs while binding in-flight operations to the specific device captured at invocation time.
3. **Context-Aware Remote Operations**:
   - **Session Locking**: Executes OS-specific physical graphical session lock commands (Linux `gdbus`/`loginctl` with `LockedHint` verification; Windows `tsdiscon` + `LockWorkStation` + `LogonUI.exe` verification; macOS `pmset displaysleepnow`).
   - **Lapdog Security Control**: Arms (`lapdog away`) and disarms (`lapdog back`) the [`lap-dog`](https://github.com/mochiron-desu/lap-dog) background security daemon and reads recorded/pending security events.
   - **Host Diagnostics**: Runs a 5-stage live diagnostic pipeline (`chk-reachability`, `chk-ssh`, `chk-vitals`, `chk-processes`, `chk-lapdog`).
   - **System Telemetry & Process Management**: Collects CPU load, RAM allocation, root disk usage, uptime, and top processes (`ps -eo` on Linux / `Get-CimInstance` & `Get-Process` on Windows), with remote process termination (`kill -9 <pid>`).
4. **Persistent Interactive PTY Terminal**: Allocates an `xterm-256color` pseudo-terminal over SSH with a tactile hardware modifier keybar (`CTRL`, `CTRL-C`, `ESC`, `TAB`, `|`, `~`, `/`, `↑`, `↓`), command history, font scaling (`9sp`-`18sp`), and cross-tab session persistence.

### 1.3 Local vs. Remote Operations Boundary

| Operation | Execution Location | Implementation Location | External / Remote Dependency |
| :--- | :--- | :--- | :--- |
| Local Tailscale interface detection | **Local (Android OS)** | `SshService.isLocalTailscaleActive()` in `lib/services/ssh_service.dart` | Inspects local `NetworkInterface.list()` for `tailscale`/`tun` or `100.64.0.0/10` |
| Host list & active target ID persistence | **Local (Android SharedPreferences)** | `StorageService` in `lib/services/storage_service.dart` | Keys: `lapdeck_saved_hosts_v2`, `lapdeck_active_host_id` |
| SSH private key & password storage | **Local (Android Keystore)** | `StorageService` in `lib/services/storage_service.dart` | `FlutterSecureStorage` with key prefix `lapdeck_cred_<host.id>` |
| Peer TCP / ICMP reachability probe | **Network (Client -> Peer)** | `SshService.checkReachability()` in `lib/services/ssh_service.dart` | `Socket.connect` to `tailscaleIp:port`, fallback `directIp:port`, fallback `/system/bin/ping` |
| Batched telemetry collection | **Remote (SSH exec channel)** | `SshService.fetchTelemetryBundle()` in `lib/services/ssh_service.dart` | Executes bash/PowerShell telemetry script over `dartssh2` |
| Graphical session lock | **Remote (SSH exec channel)** | `HostTarget.lockSessionCommand` executed in `HomeTab` / `DeviceDetailScreen` | Linux `gdbus` + `loginctl`; Windows `tsdiscon` + `LockWorkStation` + `LogonUI.exe` verification; macOS `pmset` |
| Lapdog arm / disarm / status | **Remote (SSH exec channel)** | `HomeTab._executeArmAwayOperation()` & `DeviceDetailScreen._handleToggleAway()` | Remote `lapdog` or `~/.local/bin/lapdog` binary |
| Interactive shell session | **Remote (SSH PTY channel)** | `SshService.startInteractiveShell()` & `TerminalSessionController` | `dartssh2` `client.shell(pty: SSHPtyConfig(type: 'xterm-256color'))` |
| Windows OpenSSH provisioning | **Remote Host Setup Script** | `scripts/windows/install_openssh.ps1` & `install_openssh.bat` | Run locally on the Windows peer as Administrator |

---

## 2. Repository Navigation

Use the exact paths below when navigating or modifying the repository. Do not invent parallel directories.

### 2.1 Active Application Code (`lib/`)
- `lib/main.dart`: Application entry point, `SystemChrome` overlay configuration, service initialization (`StorageService`, `SshService`, `TerminalSessionController`), and root `LapDeckApp` widget.
- `lib/models/`
  - `lib/models/host_target.dart`: Canonical `HostTarget` model, `HostOs` (`linux`, `windows`, `macos`), `AuthMethod` (`privateKey`, `password`, `tailscaleSsh`), `PeerStatus` (`unknown`, `connecting`, `online`, `unreachable`, `offline`), `ServiceStatus` (`unknown`, `connecting`, `available`, `unavailable`), OS-specific `lockSessionCommand`, and `defaultHosts`.
  - `lib/models/vitals_data.dart`: `VitalsData`, `ProcessItem`, `LapdogStatus`, `OperationLifecycleState` (`ready`, `inProgress`, `successful`, `failed`, `timedOut`, `resultUnknown`, `targetUnavailable`), `OperationFeedback`, and `DiagnosticCheckResult`.
  - `lib/models/command_action.dart`: Action definitions (`CommandAction`) used by the legacy v1 quick action pad and unit tests.
- `lib/services/`
  - `lib/services/ssh_service.dart`: All network probing (`isLocalTailscaleActive`, `checkReachability`), pooled SSH command execution (`executeCommand`, `_cmdClientPool`), interactive PTY streaming (`startInteractiveShell`, `sendShellInput`, `disconnectShell`), and telemetry parsing (`fetchTelemetryBundle`).
  - `lib/services/storage_service.dart`: `SharedPreferences` and `FlutterSecureStorage` wrapper for host configurations, active host ID, and per-host secrets.
  - `lib/services/terminal_session_controller.dart`: `ChangeNotifier` managing the persistent interactive PTY session, output buffer, command history, and terminal font size.
- `lib/theme/`
  - `lib/theme/deck_theme.dart`: `DeckColors` design tokens and `DeckTheme.darkTheme` Material 3 theme definition.
- `lib/ui/screens/` (Active v2 4-Tab Architecture)
  - `lib/ui/screens/app_scaffold.dart`: Root `StatefulWidget` (`WidgetsBindingObserver`) hosting the 4-tab `IndexedStack`, bottom `NavigationBar`, global `_hosts` list, `_selectedHostId`, and `_telemetryByHost` cache.
  - `lib/ui/screens/home_tab.dart`: Primary operational screen (Tab 0) containing the app header, connectivity alert banner, network overview card, target device selector card + bottom sheet, 2x2 context-aware quick actions (`Terminal`, `Diagnostics`, `Arm/Disarm Away`, `Lock Session`), operation lifecycle feedback banner, connected devices list, Lapdog security summary card, and `_DiagnosticsBottomSheet`.
  - `lib/ui/screens/devices_tab.dart`: Peer inventory screen (Tab 1) with search bar, filter chips (`All devices`, `Online`, `Linux`, `Windows`), independent subsystem state pills (`Peer`, `SSH`, `Agent`), target selection action, and navigation to `DeviceDetailScreen`.
  - `lib/ui/screens/terminal_tab.dart`: Interactive PTY terminal screen (Tab 2) with landing connection card, target mismatch safety banner, `SelectableText` terminal viewport, hardware modifier keybar, and command input bar.
  - `lib/ui/screens/settings_tab.dart`: Application settings and keystore status screen (Tab 3).
  - `lib/ui/screens/device_detail_screen.dart`: Per-device deep inspection screen pushed from `HomeTab` or `DevicesTab`, composing `VitalsCard`, `LapdogCard`, `QuickControlsCard`, and `ProcessManagerCard`.
  - `lib/ui/screens/host_config_dialog.dart`: Modal dialog for enrolling a new peer node or editing/deleting an existing `HostTarget` and its Keystore secret.
- `lib/ui/widgets/` (Active Shared Widgets)
  - `lib/ui/widgets/vitals_card.dart`: CPU, RAM, disk progress meters and verified uptime display.
  - `lib/ui/widgets/lapdog_card.dart`: Per-device Lapdog status badge, Away Mode toggle switch, and event counters.
  - `lib/ui/widgets/quick_controls_card.dart`: 2x2 device control grid (`Lock Session`, `Restart Lapdog`, `Sync Skills`, `Sleep Device`) with confirmation dialogs for locking and sleeping.
  - `lib/ui/widgets/process_manager_card.dart`: Top CPU/memory process table with `KILL` (`kill -9`) action.

### 2.2 Legacy v1 Files (Retained, Do Not Use for New Features)
The following files belong to the initial single-screen v1 architecture (commit `f81a030`) and are superseded by `AppScaffold` and the 4-tab screens:
- `lib/ui/screens/deck_screen.dart`
- `lib/ui/widgets/deck_header.dart`
- `lib/ui/widgets/host_rack_selector.dart`
- `lib/ui/widgets/quick_action_pad.dart`
- `lib/ui/widgets/terminal_bay.dart`

**Rule**: Do not wire new features into `deck_screen.dart` or its v1 widgets. Implement all UI changes in the active 4-tab screens (`app_scaffold.dart`, `home_tab.dart`, `devices_tab.dart`, `terminal_tab.dart`, `settings_tab.dart`, `device_detail_screen.dart`) and active shared widgets. Do not delete legacy files without explicit user confirmation.

### 2.3 Android Host, Scripts, and Tests
- `android/app/build.gradle.kts`: Android application build configuration (`namespace = "com.mochirondesu.lap_deck"`, `compileSdk = 36`, `minSdk = 24`, `targetSdk = 35`).
- `android/app/src/main/AndroidManifest.xml`: Permissions (`INTERNET`, `ACCESS_NETWORK_STATE`, `VIBRATE`) and `MainActivity` declaration.
- `android/app/src/main/kotlin/com/mochirondesu/lap_deck/MainActivity.kt`: Flutter Android activity entry point.
- `scripts/windows/install_openssh.ps1` & `scripts/windows/install_openssh.bat`: Administrator provisioning scripts for Windows OpenSSH Server (`sshd`), firewall rules, and `administrators_authorized_keys` ACLs.
- `test/widget_test.dart`: Unit tests verifying `HostTarget`, `PeerStatus`/`ServiceStatus` separation, `OperationLifecycleState`, and `CommandAction`.

---

## 3. Architectural Rules

### 3.1 Dependency Injection and State Management
1. **Explicit Constructor Injection**: Services (`StorageService`, `SshService`, `TerminalSessionController`) are instantiated once in `main()` (`lib/main.dart`) and passed explicitly via widget constructors. Do not introduce global singletons, service locators (`GetIt`), or competing instances of `SshService`.
2. **State Ownership Hierarchy**:
   - **Global App State**: Owned by `_AppScaffoldState` (`lib/ui/screens/app_scaffold.dart`), which is the single source of truth for the enrolled `_hosts` list, the selected global target ID (`_selectedHostId`), and cached telemetry (`_telemetryByHost` keyed by `host.id`).
   - **Persistent PTY State**: Owned by `TerminalSessionController` (`ChangeNotifier`), allowing the interactive shell to survive tab switches in `AppScaffold`'s `IndexedStack`.
   - **Screen-Local State**: Ephemeral UI state (search queries, filter chips, bottom-sheet expansion, in-flight operation locks `_inFlightKeys`, and `_operationFeedback`) belongs in the respective screen's `State` class.
3. **No Unnecessary State Frameworks**: Although `flutter_riverpod` is present in `pubspec.yaml`, the codebase uses idiomatic Flutter `StatefulWidget`, `ChangeNotifier`, and constructor callbacks. Do not migrate screens to Riverpod, Bloc, or Provider unless explicitly instructed.

### 3.2 Separation of UI and Service Logic
1. **All Network and SSH I/O Must Live in `SshService`**: UI widgets and screens must never import `dartssh2` or `dart:io` `Socket`/`Process` directly. All socket probes, ping fallbacks, SSH command executions, and PTY shell streams must go through `SshService` (`lib/services/ssh_service.dart`).
2. **All Persistence Must Live in `StorageService`**: UI widgets must never call `SharedPreferences` or `FlutterSecureStorage` directly. Use `StorageService` methods (`loadHosts`, `saveHosts`, `getActiveHostId`, `setActiveHostId`, `saveHostCredential`, `getHostCredential`, `deleteHostCredential`).
3. **Immutable Domain Models**: Model classes in `lib/models/` (`HostTarget`, `VitalsData`, `ProcessItem`, `LapdogStatus`, `OperationFeedback`, `DiagnosticCheckResult`) must remain immutable (`const` constructors, `final` fields) and state transitions must use `copyWith()`.
4. **Single Shared Implementation for Device Operations**: Session lock and Lapdog Away arm/disarm execution flows must have **one** shared service implementation (e.g., `lib/services/device_operations.dart`) called by both `HomeTab` and `DeviceDetailScreen`, preventing divergent command scripts, reachability checks, or verification logic across screens.

### 3.3 SSH Connection Pooling vs. Interactive PTY Isolation
`SshService` separates short-lived command execution from the interactive terminal:
- **Command Execution Pool (`_cmdClientPool`)**: Keyed by `host.id`. Reused across `executeCommand()` calls (vitals, diagnostics, lock session, Lapdog toggle). Evicted and closed automatically on connection error.
- **Interactive Shell Session (`_activeClient` / `_activeShellSession`)**: Managed exclusively via `startInteractiveShell()`, `sendShellInput()`, and `disconnectShell()`.
- **Rule**: Never execute background telemetry or quick-action commands by injecting text into `_activeShellSession`. Conversely, `disconnectShell()` must never close clients in `_cmdClientPool`.

### 3.4 Lifecycle Awareness
- `AppScaffold` observes `AppLifecycleState` via `WidgetsBindingObserver`. Returning to `AppLifecycleState.resumed` triggers `_refreshNetworkState()` without resetting `_selectedHostId` or disconnecting an active PTY session.
- Every `async` method in a `State` class must check `if (!mounted) return;` before calling `setState()` or using `BuildContext` after an `await`.

---

## 4. Functional Preservation Rules

LAPDECK controls real remote infrastructure. Agents must strictly obey these preservation invariants:

1. **Inspect Before Modifying**: Always read the complete execution path (UI handler -> `SshService` method -> remote shell command -> output parser -> state update) before changing any feature.
2. **Never Replace Real Implementations with Mocks**: Never replace `SshService` calls, `Socket.connect` probes, or remote shell scripts with hardcoded dummy data, simulated delays (`Future.delayed`), or fake success responses.
3. **Never Hardcode Online or Healthy Status**: `HostTarget.fromMap()` and `HostTarget.defaultHosts` must always initialize runtime states to `isOnline: false`, `pingMs: null`, `peerStatus: PeerStatus.unknown`, `sshStatus: ServiceStatus.unknown`, `agentStatus: ServiceStatus.unknown`, and `lapdogDaemonStatus: ServiceStatus.unknown`. Latency (`hasFreshLatency`) is valid only when `peerStatus == PeerStatus.online && pingMs != null && lastChecked != null`.
4. **Never Assume Request Initiation Equals Success**: Sending an SSH command does not mean the operation succeeded. You must inspect `SshExecutionResult.isSuccess` (`exitCode == 0 && !isTimeout && !isConnectionFailure`) and verify the remote state (e.g., checking `LOCK_CONFIRMED` / `LockedHint=yes` on Linux, `LogonUI.exe` on Windows, or `lapdog status` output after toggling Away Mode).
5. **Preserve OS-Specific Command Branching**: Linux (`HostOs.linux`), Windows (`HostOs.windows`), and macOS (`HostOs.macos`) require distinct remote commands in `HostTarget.lockSessionCommand` and `SshService.fetchTelemetryBundle()`. Never run Linux-only commands (`free`, `df`, `ps -eo`, `loginctl`, `gdbus`) unconditionally against Windows hosts.
6. **Preserve Existing Default Host Identities**: Keep `host-surajworklaptop` (`surajworklaptop`, `100.118.7.117`, `surajwork`, Linux) and `host-mochirondesu` (`mochirondesu`, `100.79.206.82`, `qwerk`, Windows) as the seed defaults in `HostTarget.defaultHosts` when `SharedPreferences` is empty, while ensuring all runtime logic operates dynamically on any enrolled `HostTarget`.

---

## 5. Canonical Target-Device Rules

Every device-specific operation in LAPDECK is governed by the canonical target-device model:

1. **Stable Device Identifier (`host.id`)**: Every `HostTarget` has a permanent `id` (e.g., `host-surajworklaptop`, `host-mochirondesu`). All caches (`_telemetryByHost`), connection pools (`_cmdClientPool`), in-flight locks (`_inFlightKeys`), and Keystore credentials (`lapdeck_cred_<host.id>`) must be keyed by `host.id`, never by list index, IP address, or display name.
2. **Target Selection Is Separate from Connection Status**: A host can be the selected global target (`_selectedHostId == host.id`) while `peerStatus` is `unreachable` or `sshStatus` is `unavailable`. Never automatically deselect or switch the active target device because a reachability check failed.
3. **Persist Selection Across Navigation and Restarts**: Changing the selected target via `_handleSelectHost(HostTarget)` in `AppScaffold` immediately persists `host.id` via `storage.setActiveHostId(host.id)` and preserves selection across all four tabs. Only fall back to `_hosts.first.id` if the currently selected host was explicitly deleted by the user (`_reloadHosts()`).
4. **Capture Target at Operation Start (No Mid-Flight Redirection)**:
   - When an asynchronous operation begins (e.g., `_executeArmAwayOperation`, `_executeLockSessionOperation`, `_DiagnosticsBottomSheet`, `_fetchDeviceTelemetry`), capture `final target = ...;` in a local variable or `final` state field (`_capturedTarget`) before the first `await`.
   - All subsequent network probes, SSH commands, telemetry updates (`onTelemetryUpdated(target.id, bundle)`), and `OperationFeedback` records (`targetHostId: target.id`, `targetHostName: target.name`) for that operation **must** use the captured `target`, even if the user changes the global target while the operation is running.
5. **Inspecting a Device Must Not Silently Change the Global Target**: Tapping a device row in `HomeTab` or `DevicesTab` opens `DeviceDetailScreen` for that specific `host` without mutating `_selectedHostId`. Changing the global target requires an explicit user action (`Select Target Device` sheet on Home, `Set as target` button on Devices tab, or `Set <name> as Global Target` button inside `DeviceDetailScreen`).
6. **Terminal Session Target Isolation**: If `TerminalSessionController` has an active PTY session on Host A (`connectedHost.id == A`) and the user switches the global target to Host B (`activeHost.id == B`), `TerminalTab` must **not** silently kill or redirect the live shell on Host A. Instead, it must keep Host A's PTY alive and display the target-mismatch banner offering an explicit `Switch to <Host B>` action (`forceReconnect: true`).

---

## 6. Networking and Subsystem State Rules

### 6.1 Six Distinct Operational States (Never Conflate)
Agents must never collapse connectivity into a single boolean. Represent and check these states independently:

| Layer | Model Field / Method | Possible States | Meaning |
| :--- | :--- | :--- | :--- |
| **1. Local Tailscale VPN** | `SshService.isLocalTailscaleActive()` / `_localTailscaleActive` | `bool` | Local Android device has an active `tailscale`/`tun` interface with a `100.64.0.0/10` CGNAT IPv4 address. |
| **2. Peer Reachability** | `HostTarget.peerStatus` (`PeerStatus`) | `unknown`, `connecting`, `online`, `unreachable`, `offline` | Whether packets reach the target machine over Tailscale mesh or LAN failover. |
| **3. SSH Service** | `HostTarget.sshStatus` (`ServiceStatus`) | `unknown`, `connecting`, `available`, `unavailable` | Whether TCP port `host.port` (default 22) accepts connections and SSH authentication succeeds. |
| **4. Telemetry Agent** | `HostTarget.agentStatus` (`ServiceStatus`) | `unknown`, `connecting`, `available`, `unavailable` | Whether the remote OS shell successfully executes the batched telemetry script in `fetchTelemetryBundle()`. |
| **5. Lapdog Daemon** | `HostTarget.lapdogDaemonStatus` (`ServiceStatus`) + `LapdogStatus` | `unknown`, `connecting`, `available`, `unavailable` | Whether the `lapdog` binary is installed and responsive on the target host. |
| **6. Interactive PTY** | `TerminalSessionController.isConnected` & `connectedHost` | `bool` + `HostTarget?` | Whether a live interactive `xterm-256color` shell stream is currently open. |

### 6.2 Critical Probing Invariants in `SshService.checkReachability()`
1. **`ECONNREFUSED` Means Peer Is Online**: When `Socket.connect(ip, port)` throws a `SocketException` with OS error code `111` (Linux/Android), `61` (macOS), or message containing `'connection refused'`, the host responded over the network. You **must** set `isOnline: true`, `peerStatus: PeerStatus.online`, and `sshPortStatus: ServiceStatus.unavailable`. Never report the host as `unreachable` or Tailscale as offline when only `sshd` is stopped.
2. **Route Priority (Tailscale First, LAN Second, ICMP Ping Third)**:
   - Probe `host.tailscaleIp:host.port` first (`isDirect: false`).
   - If Tailscale TCP times out or fails (not `ECONNREFUSED`) and `host.directIp` is non-empty, probe `host.directIp!:host.port` (`isDirect: true`).
   - If TCP probes do not connect, run `_tryPingLatency(host.tailscaleIp)` (`ping -c 1 -W 1`) to detect online peers whose firewall drops TCP port 22. When ICMP ping succeeds after TCP timeouts, you **must** return `isOnline: true`, `peerStatus: PeerStatus.online`, and `sshPortStatus: ServiceStatus.unavailable`.
3. **SSH Auth Failure vs. Network Failure**: In `AppScaffold._refreshNetworkState()` and `DeviceDetailScreen._fetchDeviceTelemetry()`, if `checkReachability()` reports `sshPortStatus == ServiceStatus.available` but `fetchTelemetryBundle()` returns `null` (e.g., key rejected), keep `peerStatus: PeerStatus.online` and transition `sshStatus` and `agentStatus` to `ServiceStatus.unavailable` with a descriptive `lastError`.

### 6.3 Timeouts, Cancellation, and Duplicate Request Prevention
1. **Standard Timeouts**:
   - TCP / ICMP reachability probe: `1500ms` (`checkReachability`), `1200ms` (`_tryPingLatency`).
   - SSH socket connection timeout: `4s` (`executeCommand` default `timeout`, `startInteractiveShell`).
   - SSH command execution timeout: `8s` general default (`executionTimeout`), `6s` for session lock (`_executeLockSessionOperation`).
2. **`timedOut` vs. `resultUnknown` Semantics**:
   - **`OperationLifecycleState.timedOut`**: A timeout occurred **before** the remote SSH command session started (e.g., socket connect or handshake timed out); no remote state change occurred.
   - **`OperationLifecycleState.resultUnknown`**: `executeCommand()` caught a `TimeoutException` **after** the SSH session started (`isTimeout: true`, `exitCode: null`); the remote command may still have mutated host state. Never represent this as `successful`, keep it distinct from pre-execution `timedOut` / `targetUnavailable`, and surface a `Verify <host> state` action (`_verifyTargetState`).
3. **In-Flight Deduplication**: Guard consequential per-host operations with `_inFlightKeys` (`'away-${target.id}'`, `'lock-${target.id}'`) or boolean flags (`_isRunning`, `_isExecutingAction`, `_isLapdogToggling`) in a `try / finally` block so double-taps cannot spawn concurrent SSH mutations.

---

## 7. Security and Operational Safety Rules

1. **Credentials and Private Keys**:
   - Store all SSH private keys and passwords exclusively in Android Keystore via `StorageService.saveHostCredential(hostId, secret)`.
   - `HostTarget.toMap()` intentionally omits `privateKey` so secrets are never written to unencrypted `SharedPreferences`. Never add `privateKey` or `password` to `HostTarget.toMap()` or `toJson()`.
   - Never log, print, or render private key PEM contents, passwords, or raw auth tokens in `OperationFeedback`, `SnackBar`, terminal buffers, or `lastError`.
   - *Remediation Rule for `StorageService.defaultPersonalKey`*: Remove `StorageService.defaultPersonalKey` from `lib/services/storage_service.dart`, treat that embedded Ed25519 private key as compromised, and rotate it on all target hosts. Never introduce hardcoded keys, tokens, or credentials in source code.
2. **Confirmed Security State Transitions**:
   - **Session Lock**: Never report `OperationLifecycleState.successful` for locking a workstation unless `executeCommand` returns `isSuccess` (`exitCode == 0`), which on Linux requires `gdbus` `ScreenSaver.GetActive == true` or `loginctl show-session -p LockedHint --value == yes` (`LOCK_CONFIRMED`), and on Windows requires `LogonUI.exe` in `tasklist`.
   - **Lapdog Away Mode**: After running `lapdog away` or `lapdog back`, verify the resulting state via `lapdog status` / `fetchTelemetryBundle()` before reporting `OperationLifecycleState.successful`. If the confirmed state does not match the requested state, report `OperationLifecycleState.resultUnknown`.
3. **Pre-Execution Reachability Check**: Before executing any remote security or control command (`Lock Session`, `Arm/Disarm Away`, `LapdogCard` Away toggle, process `KILL` (`kill -9`), and `QuickControlsCard` actions: `Restart Lapdog`, `Sync Skills`, `Sleep Device`), run `sshService.checkReachability(target)` first. If `!reach.isOnline || reach.sshPortStatus != ServiceStatus.available`, halt immediately and report `OperationLifecycleState.targetUnavailable` stating clearly that the target was **not** modified.
4. **Contextual Confirmation for Consequential Actions**:
   - Locking a session, arming/disarming Away Mode (both on `HomeTab` and via the `LapdogCard` Away switch on `DeviceDetailScreen`), suspending/sleeping a device, deleting an enrolled node, or killing a process must present a confirmation dialog or sheet with clear target context (`target.name`, `target.tailscaleIp`, and the consequence description) before execution.
5. **SSH Host Key Verification**: `SshService` must verify remote SSH host keys using Trust On First Use (TOFU): pin the host key fingerprint in `StorageService` (`FlutterSecureStorage`) on first connection and block/warn explicitly on any subsequent fingerprint mismatch.

---

## 8. Code Quality and Maintainability Rules

1. **Naming Conventions**:
   - Files: `snake_case.dart` (`host_target.dart`, `terminal_session_controller.dart`).
   - Classes & Enums: `UpperCamelCase` (`HostTarget`, `PeerStatus`, `OperationLifecycleState`).
   - Methods, fields & variables: `lowerCamelCase`, with private screen/service members prefixed by `_` (`_refreshNetworkState`, `_cmdClientPool`).
2. **Design Tokens Over Hardcoded Styles**: Always reference `DeckColors` and `Theme.of(context).textTheme` from `lib/theme/deck_theme.dart`. Do not use the 14 legacy v1 token aliases (`surfaceCore`, `surfaceRack`, `surfaceInset`, `accentOrange`, `phosphorGreen`, `cautionAmber`, `alertCrimson`, `meshCyan`, `textHigh`, `textMid`, `textMuted`, `textTerminal`, `borderActive`, `offlineSteel`) in new or updated code; use the canonical tokens (`background`, `surfaceSecondary`, `surfaceElevated`, `surfaceHighlight`, `borderSubtle`, `borderMedium`, `primaryText`, `secondaryText`, `mutedText`, `primaryAccent`, `healthy`, `informational`, `warning`, `error`, `terminalText`). `lib/ui/widgets/process_manager_card.dart` must be migrated to canonical tokens when next edited.
3. **Flutter Modern API Usage**: Use `Color.withValues(alpha: ...)` (Flutter 3.27+ API used throughout the codebase) instead of the deprecated `withOpacity(...)`. Use `PopScope` instead of `WillPopScope`.
4. **File Size & Modularity**: `lib/ui/screens/home_tab.dart` is currently over 3,300 lines. Do not add new large modal sheets or standalone sub-screens directly inside `home_tab.dart`; extract new reusable sheets or cards into dedicated files under `lib/ui/widgets/` or `lib/ui/screens/`.
5. **Dependencies**: Do not add new packages to `pubspec.yaml` when the Dart standard library or existing packages (`dartssh2`, `shared_preferences`, `flutter_secure_storage`, `google_fonts`, `intl`, `uuid`) already solve the requirement.

---

## 9. Testing, Validation, and Build Commands

### 9.1 Canonical Commands
Run these exact commands from the repository root:

```bash
# 1. Static analysis & lint check (must report "No issues found!")
flutter analyze

# 2. Run unit and widget tests
flutter test

# 3. Build debug APK for local verification
flutter build apk --debug

# 4. Build release APK (outputs to build/app/outputs/flutter-apk/app-release.apk)
flutter build apk --release

# 5. List connected Android devices and run on physical hardware
flutter devices
flutter run -d <device-id> --release
```

### 9.2 Validation Scope Distinction
When reporting validation results, agents must explicitly distinguish between:
1. **Local Static & Unit Verification** (`flutter analyze`, `flutter test`, `flutter build apk`): Can and **must** be executed locally after any Dart, Gradle, or asset change.
2. **Android Device / Emulator Verification**: Requires an attached ADB device (`flutter devices`) to verify `FlutterSecureStorage` Android Keystore encryption, haptic feedback, and window insets.
3. **Live Tailscale & Remote Workstation Verification**: Requires an active `tailscale0`/`tun0` interface (`100.64.0.0/10`) and reachable remote peers (`surajworklaptop` or `mochirondesu`) with `sshd` and `lapdog` running to verify live SSH execution, PTY streaming, and session locking. Never claim live remote verification was performed if only `flutter test` and `flutter analyze` were run.

---

## 10. Mandatory Agent Workflow

Every agent working in this repository must follow this exact sequence:

1. **Inspect First**: Read the target files in `lib/models/`, `lib/services/`, `lib/theme/`, and `lib/ui/` before proposing or writing any code.
2. **Consult UI/UX Standards**: If the task touches any user-facing text, status indicator, layout, or interaction, read [`docs/UI_UX_RULES.md`](docs/UI_UX_RULES.md) and verify compliance.
3. **Trace Target & State Flows**: Verify how `HostTarget.id`, `PeerStatus`, `ServiceStatus`, and `OperationLifecycleState` flow through `AppScaffold`, `SshService`, and the affected screen.
4. **Plan Minimal, Cohesive Changes**: Modify only what is required. Do not refactor unrelated screens or alter remote shell scripts without cause.
5. **Verify No Regressions**: Run `flutter analyze` and `flutter test` after making changes. Fix any analyzer warnings or broken tests immediately.
6. **Respect Git Safety**: Keep Git operations read-only (`git status`, `git diff`, `git log`) unless the user explicitly confirms staging, committing, or pushing changes.
