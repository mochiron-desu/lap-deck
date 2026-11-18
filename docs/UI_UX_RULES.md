# LAPDECK UI/UX & Design System Rules (`docs/UI_UX_RULES.md`)

This document is the canonical design, visual language, and interaction specification for **LAPDECK** (`com.mochirondesu.lap_deck`). It derives directly from the active Material 3 4-tab implementation (`lib/theme/deck_theme.dart` and `lib/ui/`) and serves as the single source of truth for all future interface changes.

> **Relationship to `AGENTS.md`**: Root-level [`AGENTS.md`](../AGENTS.md) governs repository architecture, networking, and operational safety. Coding agents **MUST** consult and follow this document before creating or modifying any file under `lib/theme/` or `lib/ui/`.

---

## 1. Product Identity & Design Philosophy

### 1.1 Core Design Personality
LAPDECK is an **industrial-grade mobile infrastructure command deck** built under the project's **Anti-AI-Slop Design System**. Its interface must feel:
- **Technical & Precise**: Surfaces real subsystem states (`Peer`, `SSH`, `Agent`, `Lapdog`), verified round-trip latencies (`ms`), CGNAT/LAN endpoints, and confirmed command outcomes.
- **Calm & Dependable**: Dark-first slate surfaces (`#11151B` to `#252F3D`) with 1px structural borders (`#303A47`), reserving high-saturation color strictly for verified status semantics and the signature warm amber accent (`#E89A50`).
- **Tactile & Functional**: Prioritizes fast operational comprehension, unambiguous target-device context, physical haptic feedback (`HapticFeedback`), and one-tap access to common workstation workflows.

### 1.2 Anti-Patterns (What LAPDECK Must Never Become)
1. **No Generic SaaS / Marketing Dashboards**: Never introduce decorative pastel gradients, glassmorphism blurs, floating drop shadows (`elevation > 0`), or marketing-style hero banners.
2. **No Decorative Analytics Bloat**: Never add fake sparklines, unverified historical charts, or ornamental gauges that do not correspond to real data returned by `SshService`.
3. **No Exaggerated Cyberpunk Clutter**: Avoid neon glow effects, unreadable condensed fonts, or gratuitous ASCII art that degrades legibility on a mobile screen.
4. **No Ambiguous "Magic" Actions**: Never hide which physical machine an action targets or disguise a remote SSH command as a local toggle without lifecycle feedback.

---

## 2. Canonical Visual Language & Design Tokens

All color and theme tokens live in `lib/theme/deck_theme.dart` (`DeckColors` and `DeckTheme.darkTheme`). Never define ad-hoc hex colors inside screen or widget files.

### 2.1 Surface & Border Palette (`DeckColors`)

| Token | Hex Value | Usage |
| :--- | :--- | :--- |
| `DeckColors.background` | `#11151B` | Primary scaffold background, app bar background, recessed inner containers inside cards/sheets, and PTY terminal viewport background. |
| `DeckColors.surfaceSecondary` | `#171D25` | Primary container surface for cards, device rows, bottom `NavigationBar`, modal bottom sheets, and dialogs. |
| `DeckColors.surfaceElevated` | `#1D2530` | Elevated interactive elements, text input fills (`InputDecorationTheme`), active selector row background, and floating `SnackBar` surface. |
| `DeckColors.surfaceHighlight` | `#252F3D` | Bottom `NavigationBar` active indicator pill and selected filter chip background (`DevicesTab`). |
| `DeckColors.borderSubtle` | `#303A47` | Default `1.0px` structural border for cards, containers, dividers, chips, and inputs. |
| `DeckColors.borderMedium` | `#3D4A5C` | Emphasized `1.0px` border for the Target Device Selector card, dialogs, snackbars, and bottom-sheet drag handles. |

### 2.2 Typography & Semantic Accent Palette (`DeckColors`)

| Token | Hex Value | Semantic Role |
| :--- | :--- | :--- |
| `DeckColors.primaryText` | `#F1F3F5` | Primary headings, device names, metric values, and active input text. |
| `DeckColors.secondaryText` | `#A0AAB8` | Supporting descriptions, OS/role subtitles, key-value labels, and inactive action icons. |
| `DeckColors.mutedText` | `#8490A3` | Timestamps, section overlines, unselected navigation items, and `Unknown` / `Unverified` status indicators (adjusted from `#768294`, which only achieved `4.35:1` on `surfaceSecondary` and `3.96:1` on `surfaceElevated`, to achieve `5.26:1` and `4.79:1` for WCAG AA `>= 4.5:1` compliance). |
| `DeckColors.primaryAccent` | `#E89A50` | Signature warm amber for primary CTAs, `Selected` target badges, active navigation icons/labels, focused input borders (`1.5px`), and `inProgress` spinners. |
| `DeckColors.healthy` | `#36B58E` | Mint emerald strictly for verified `Online` peers, `Available` services, `Home mode` Lapdog status, and `Successful` operations. |
| `DeckColors.informational` | `#47AFC5` | Cyan blue for `Connecting` / probing states, root storage progress bars, and `Diagnostics` quick action icon. |
| `DeckColors.warning` | `#E5B45D` | Caution amber for `Away armed` mode, partial degradation (`Peer online · SSH unavailable`), `Timed out`, and `Result unknown` states. |
| `DeckColors.error` | `#E16C70` | Coral red for `Unreachable` / `Offline` hosts, `Unavailable` services, `Failed` operations, high CPU load (`> 80%`), and destructive actions (`Disconnect`, `Sleep`, `Kill`). |
| `DeckColors.terminalText` | `#4ADE80` | Phosphor green reserved exclusively for live PTY terminal output in `TerminalTab`. |

### 2.3 Deprecation of Legacy v1 Token Aliases
`DeckColors` retains 14 legacy aliases (`surfaceCore`, `surfaceRack`, `surfaceInset`, `accentOrange`, `phosphorGreen`, `cautionAmber`, `alertCrimson`, `meshCyan`, `textHigh`, `textMid`, `textMuted`, `textTerminal`, `borderActive`, `offlineSteel`) solely for backward compatibility with unreferenced v1 widgets (`deck_screen.dart`, `deck_header.dart`, `host_rack_selector.dart`, `quick_action_pad.dart`, `terminal_bay.dart`) and `process_manager_card.dart`.
- **Rule**: All new code and any edits to existing widgets (including `process_manager_card.dart`) must use the canonical token names in Sections 2.1 and 2.2.

### 2.4 Corner Radii & Border Normalization
LAPDECK uses zero-elevation (`elevation: 0`) flat surfaces bounded by `1px` structural borders. Use this controlled radius scale:

| Element Type | Canonical Radius | Reference Implementation |
| :--- | :--- | :--- |
| **Bottom Sheet Top Corners** | `20px` (`BorderRadius.vertical(top: Radius.circular(20))`) | `HomeTab` selector, terminal, away,lock, and diagnostics sheets |
| **Filter Chips (Pill)** | `20px` (`BorderRadius.circular(20)`) | `DevicesTab._buildFilterChip` |
| **Modal Dialogs & Hero Overview Cards** | `14px` - `16px` | `HostConfigDialog` (`16px`), `DeviceDetailScreen` overview & `VitalsCard` (`16px`), `HomeTab` major cards (`14px`) |
| **Standard Cards, Device Rows & Banners** | `12px` | `DeckTheme.cardTheme`, `HomeTab` quick action cards, device rows, operation feedback banners, `SettingsTab` groups |
| **Buttons & Recessed Inner Boxes** | `8px` - `10px` | Primary/outlined sheet buttons (`10px`), recessed control buttons (`10px`), text inputs & snackbars (`8px`) |
| **Status Pills & Keybar Chips** | `4px` - `6px` | Subsystem chips (`6px`), terminal keybar buttons (`6px`), `Selected` badge & version badge (`4px`) |
| **Progress Bars & Drag Handles** | `2px` - `3px` | `VitalsCard` linear progress bars (`3px`), sheet drag handle (`2px`) |

---

## 3. Typography Rules

LAPDECK pairs **Inter** (`GoogleFonts.inter`) for readable UI hierarchy with **JetBrains Mono** (`GoogleFonts.jetBrainsMono`) for technical identifiers and shell I/O.

### 3.1 Semantic Type Scale (`DeckTheme.darkTheme.textTheme`)

| Semantic Role | Theme Slot / Font | Size / Weight | Color | Where to Use |
| :--- | :--- | :--- | :--- | :--- |
| **Application Wordmark** | `titleLarge` (`Inter`) | `20sp` / `w800`, `letterSpacing: 0.5` | `primaryText` | `LAPDECK` top bar wordmark in `HomeTab`. |
| **Screen / Sheet Title** | `titleLarge` / `titleMedium` (`Inter`) | `20sp` (`w600`-`w700`) or `16sp` (`w600`-`w700`) | `primaryText` | `AppBar` titles, modal bottom sheet titles, dialog headers. |
| **Primary Device Name** | `titleMedium` / `titleSmall` (`Inter`) | `16sp`-`18sp` (`w700`) in cards, `14sp` (`w700`) in compact rows | `primaryText` | Workstation hostnames (`surajworklaptop`, `mochirondesu`). |
| **Section Heading** | `titleSmall` (`Inter`) or `labelSmall` (`JetBrains Mono`) | `14sp` (`w600`) title case, or `10sp`-`11sp` (`w700`, `letterSpacing: 0.8`) overline | `secondaryText` / `mutedText` | Section headers (`Quick Actions`, `Connected Devices`, `NETWORK & FAILOVER`). |
| **Body & Consequence Copy** | `bodyMedium` / `bodySmall` (`Inter`) | `14sp` / `12sp` (`w400`, `height: 1.4`) | `secondaryText` | Explanations, consequence descriptions in confirmation sheets, empty state descriptions. |
| **Technical Identifiers & Badges** | `labelSmall` (`JetBrains Mono`) | `10sp`-`11sp` (`w500`-`w700`) | Contextual | Version tags (`v1.2`), IP:port strings, process PIDs, timestamps, status badges. |
| **Terminal Output & Prompt** | `GoogleFonts.jetBrainsMono` | Dynamic `9sp`-`18sp` (default `12sp`, `height: 1.35`) | `terminalText` (`#4ADE80`) | `TerminalTab` live PTY buffer, status bar, modifier keybar, and command input `TextField`. |

### 3.2 Typography Discipline
1. **Reserve Monospace for Technical Data**: Use `JetBrains Mono` (`labelSmall` or explicit `GoogleFonts.jetBrainsMono`) for shell buffers, command prompts, keybar chips, IP addresses, ports, PIDs, and compact status badges. Use `Inter` for all prose, button labels, and descriptions.
2. **Title Case for Buttons & Card Titles**: Use title case for buttons and card/section titles (`System Vitals`, `Lapdog Security`, `Quick Actions`, `Connected Devices`), and sentence case for body copy and descriptions. Restrict ALL-CAPS strictly to short overline labels (`TARGET DEVICE`, `CONNECTED PEERS`, `TARGET LATENCY`, `DIAGNOSTIC CHECKS`) and compact state badges (`UNREACHABLE`, `SERVICE WARNING`, `AWAY ARMED`, `HOME MODE`).
3. **Never Truncate Target Device Names**: Hostnames (`surajworklaptop`, `mochirondesu`) must never be clipped with `...` in the Network Overview card, Target Device Selector card, or Device rows. Use `Wrap` or dedicated full-width rows (as implemented in `HomeTab._buildNetworkOverviewCard` and `_buildDeviceRow`) so the complete hostname is always legible.

---

## 4. Colour and Status Semantics

### 4.1 Canonical Subsystem & Peer State Mapping
Status colors must never be assigned arbitrarily or used decoratively. Follow this exact mapping across all screens:

| Operational State | Enum / Condition | Canonical Color | Text Label | Required Visual Cues |
| :--- | :--- | :--- | :--- | :--- |
| **Healthy / Online & SSH Available** | `PeerStatus.online` + `ServiceStatus.available` | `DeckColors.healthy` (`#36B58E`) | `Online` / `Available` / `Network healthy` | `7px`-`8px` solid circle or `Icons.check_circle` + text label |
| **Selected Target** | `host.id == activeHost?.id` | `DeckColors.primaryAccent` (`#E89A50`) | `Selected` | Amber pill badge (`alpha: 0.14` fill) + radio/icon indicator |
| **Connecting / Probing** | `PeerStatus.connecting` / `ServiceStatus.connecting` | `DeckColors.informational` (`#47AFC5`) | `Connecting` / `Checking...` / `Measuring...` | Indeterminate spinner or cyan indicator + text label |
| **Degraded (Peer Online, SSH/Agent Down)** | `PeerStatus.online` + `sshStatus == unavailable` | `DeckColors.warning` (`#E5B45D`) | `SSH Unavailable` / `Peer online · SSH unavailable` | Amber warning dot/icon (`Icons.warning_amber_rounded`) + subsystem failure subtitle |
| **Lapdog Away Armed** | `LapdogStatus.isAwayArmed == true` | `DeckColors.warning` (`#E5B45D`) | `Away armed` / `AWAY ARMED` | `Icons.shield` + amber badge |
| **Lapdog Home Mode** | `isInstalled && !isAwayArmed` | `DeckColors.healthy` (`#36B58E`) | `Home mode` / `HOME MODE` | `Icons.verified_user_outlined` + green badge |
| **Unreachable / Offline / Service Down** | `PeerStatus.unreachable`, `offline`, or `ServiceStatus.unavailable` | `DeckColors.error` (`#E16C70`) | `Unreachable` / `Offline` / `Unavailable` | Red dot or `Icons.cloud_off_outlined` / `Icons.cancel_outlined` + text label |
| **Unknown / Unverified** | `PeerStatus.unknown`, `ServiceStatus.unknown`, `!isVerified` | `DeckColors.mutedText` (`#8490A3`) | `Unknown` / `Unverified` / `Unavailable` | Muted grey dot/icon + text label |

### 4.2 Operation Lifecycle State Mapping (`OperationLifecycleState`)
Every asynchronous action (`OperationFeedback` and `DiagnosticCheckResult`) maps to these seven states:

| State (`OperationLifecycleState`) | Label | Color | Icon / Indicator |
| :--- | :--- | :--- | :--- |
| `ready` | `Ready` | `DeckColors.informational` (banner) / `DeckColors.mutedText` (check tile) | `Icons.radio_button_unchecked` |
| `inProgress` | `In progress` | `DeckColors.primaryAccent` | `14px`-`16px` `CircularProgressIndicator(strokeWidth: 2)` |
| `successful` | `Successful` | `DeckColors.healthy` | `Icons.check_circle_outline` / `Icons.check_circle` |
| `failed` | `Failed` | `DeckColors.error` | `Icons.error_outline` / `Icons.cancel_outlined` |
| `timedOut` | `Timed out` | `DeckColors.warning` | `Icons.timer_off_outlined` (pre-execution timeout; no remote state change) |
| `resultUnknown` | `Result unknown` | `DeckColors.warning` | `Icons.help_outline` (post-execution timeout or unconfirmed state; remote state may have changed) |
| `targetUnavailable` | `Target unavailable` | `DeckColors.error` | `Icons.error_outline` / `Icons.cancel_outlined` |

### 4.3 Non-Negotiable Semantic Rules
1. **Selected != Healthy**: A selected device uses `DeckColors.primaryAccent` (`Selected` badge) for selection identity, while its reachability badge independently reflects `PeerStatus` and `ServiceStatus`. Never color an unreachable selected device green.
2. **Green Requires Verification**: `DeckColors.healthy` may only be used when a probe or command has actively succeeded during the session (`peerStatus == PeerStatus.online`, `ServiceStatus.available`, `vitals.isVerified == true`). Unchecked or unavailable services (`Lapdog` on Windows, unprobed hosts on startup) must use `DeckColors.mutedText` or `DeckColors.error`.
3. **Never Communicate Status by Color Alone**: Every status indicator must pair its color dot or border with an explicit text label (`Online`, `Unreachable`, `SSH Unavailable`, `Away armed`) and/or a distinct icon (`Icons.check_circle`, `Icons.warning_amber_rounded`, `Icons.cloud_off_outlined`, `Icons.help_outline`).

---

## 5. Layout, Spacing & Dimensions

### 5.1 Canonical Spacing Scale
Follow the established spacing rhythm across all screens:
- **Screen Horizontal Padding**: `20dp` (`EdgeInsets.symmetric(horizontal: 20, vertical: 12)` on `HomeTab`, `DevicesTab`, `SettingsTab`, `DeviceDetailScreen`; `24dp` on `TerminalTab` landing state).
- **Major Section Vertical Spacing**: `16dp` to `20dp` (`SizedBox(height: 16)` between top overview/selector cards; `SizedBox(height: 20)` between major functional sections).
- **Grid & List Item Spacing**: `8dp` to `12dp` (`10dp` horizontal/vertical gap in 2x2 Quick Action grids; `8dp`-`12dp` separator in `ListView.separated`).
- **Card Internal Padding**:
  - Standard section cards: `16dp` (`EdgeInsets.all(16)`).
  - Device Detail overview card: `18dp` (`EdgeInsets.all(18)`).
  - Device rows & selector items: `EdgeInsets.symmetric(horizontal: 14, vertical: 12)`.
  - Compact quick action cards & feedback banners: `12dp` (`EdgeInsets.all(12)`).
  - Modal bottom sheets: `EdgeInsets.fromLTRB(20, 14, 20, 20)` or `EdgeInsets.all(20)`.

### 5.2 Component Dimensions & Touch Targets
- **Bottom Navigation Bar**: `height: 64` (`NavigationBarThemeData` in `DeckTheme`).
- **Primary & Outlined Action Buttons**: `minimumSize: Size.fromHeight(48)` (or `44dp` for secondary card-footer actions).
- **IconButtons in Headers/AppBars**: `constraints: BoxConstraints(minWidth: 48, minHeight: 48)`.
- **Device Row Minimum Height**: `minHeight: 68` (`BoxConstraints(minHeight: 68)`).
- **Quick Action Card Minimum Height**: `minHeight: 78` on `HomeTab`; `minHeight: 64` on `QuickControlsCard`.
- **Bottom Sheet List Constraints**: Cap scrollable lists inside modal bottom sheets at `MediaQuery.of(context).size.height * 0.55` (selector sheet) or `0.42` (diagnostics sheet) so sheets never overflow small screens.

---

## 6. Component Design Rules

### 6.1 Application Header & AppBars
- **HomeTab Header (`_buildAppHeader`)**: Fixed top bar with `1px` bottom border (`DeckColors.borderSubtle`), `LAPDECK` wordmark, `v1.2` monospace badge (must be derived from the `major.minor` version in `pubspec.yaml`, currently `1.2.0+37`, rather than drifting as an independent hardcoded string), `Refresh` action (morphs into an `18x18` amber spinner while loading), and `Add Peer Device` (`+`) action.
- **Secondary Screen AppBars (`DevicesTab`, `TerminalTab`, `SettingsTab`, `DeviceDetailScreen`)**: Flat `AppBar` with `backgroundColor: DeckColors.background`, `elevation: 0`, concise title (`Devices`, `Terminal · <host.name>`, `Settings`, `<host.name>`), and 48x48dp action buttons.

### 6.2 Connectivity Alert Banner (`HomeTab._buildConnectivityAlert`)
- Appears at the top of `HomeTab` **only** when the active target has been checked and has a confirmed issue (`peerStatus` is `unreachable`/`offline`, or `sshStatus`/`agentStatus` is `unavailable`).
- Displays a severity badge (`UNREACHABLE` in `DeckColors.error` or `SERVICE WARNING` in `DeckColors.warning`), the target hostname, a 1-line explanation, an inline `Retry` button, an expand/collapse chevron (`Icons.expand_more` / `Icons.expand_less`) revealing 5 subsystem key-value rows, and a `Dismiss` (`Icons.close`) button keyed by state signature (`id-peerStatus-sshStatus-agentStatus`).
- Dismissing the alert hides the banner for that specific failure signature without altering underlying host state; if the state changes, the alert re-evaluates automatically.

### 6.3 Network Overview Card (`HomeTab._buildNetworkOverviewCard`)
- **Top Row**: Status dot + non-contradictory summary title (`Network healthy`, `Mesh online · Target unreachable`, `Peer online · SSH unavailable`, `SSH connected · Telemetry degraded`, `Tailscale mesh offline`) + last check timestamp (`Checked just now`, `Checked 12s ago`, `Checked HH:mm:ss`).
- **Metrics Row**: 2 balanced columns separated by a `1px` vertical divider (`CONNECTED PEERS` and `TARGET LATENCY`). Never cram 3 columns into a single mobile row.
- **Bottom Row**: Full-width `SELECTED DEVICE` footer displaying the complete, untruncated active target name.

### 6.4 Target Device Selector Card (`HomeTab._buildTargetDeviceSelectorCard`)
- Placed **directly above** Quick Actions on `HomeTab` so the operator always sees which machine Quick Actions will hit.
- Shows: `TARGET DEVICE` overline + `Selected` badge + reachability pill on top; OS icon + full hostname (`18sp w700`) + `<OS> · <tailscaleIp>` subtitle + explicit `Change device` button (`Icons.swap_horiz`) in the middle; and independent subsystem status pills (`Host`, `SSH`, `Agent`, `RTT`) at the bottom.
- Tapping anywhere on the card opens `_showTargetSelectorSheet()`.

### 6.5 Context-Aware Quick Action Cards (`HomeTab._buildQuickActionsSection`)
- Organized as a **2x2 grid** (`Terminal`, `Diagnostics`, `Arm/Disarm Away`, `Lock <OS> Session`).
- Every card must display three pieces of information:
  1. **Action Title & Icon** (or `18x18` spinner when `isBusy` for that host).
  2. **Explicit Target Subtitle**: e.g., `Open on surajworklaptop`, `Resume on surajworklaptop`, `Inspect surajworklaptop`, `Protect surajworklaptop`, `Lock mochirondesu`.
  3. **Live Prerequisite / State Hint**: e.g., `Active PTY session`, `SSH Available`, `Daemon Unavailable`.

### 6.6 Device Rows & Cards (`HomeTab` & `DevicesTab`)
- **Line 1**: OS icon + complete untruncated hostname + `Selected` badge (if active target) + trailing reachability dot, status label, and verified latency (`<pingMs> ms` only when `hasFreshLatency == true`).
- **Line 2**: `<osDisplayName> · <roleDisplayName>`.
- **In `DevicesTab`**: Also includes independent `Peer`, `SSH`, and `Agent` status pills and a split bottom action bar (`Set as target` / `Selected target` on the left; `Device details` on the right).
- **Interaction Rule**: Tapping the main body of a device row/card navigates to `DeviceDetailScreen` for that device without silently changing the global selected target.

### 6.7 Lapdog Security Summary (`HomeTab._buildSecurityOverviewCard` & `LapdogCard`)
- On `HomeTab`, the Security Overview card is a **read-only status summary** (`Current security mode`, `Daemon health`, `Last health check`, `Security events` using the exact phrasing `X events recorded · Y pending in queue`) with a `Manage security` button that navigates to `DeviceDetailScreen`. Do not duplicate the `Arm Away` button inside `HomeTab`'s summary card, because `Arm/Disarm Away` is already in Quick Actions above.
- On `DeviceDetailScreen`, `LapdogCard` provides the interactive Away Mode `Switch` bound to that specific device.

---

## 7. Navigation & Information Architecture

### 7.1 Primary 4-Tab Structure (`AppScaffold`)
LAPDECK uses a persistent 4-tab `IndexedStack` + bottom `NavigationBar` in `lib/ui/screens/app_scaffold.dart`:

| Tab Index | Label | Icon (Unselected / Selected) | Screen Widget | Primary Responsibility |
| :--- | :--- | :--- | :--- | :--- |
| **0** | `Home` | `Icons.home_outlined` / `Icons.home` | `HomeTab` | Operational command deck: network health, target selector, context-aware quick actions, peer summary, and Lapdog security overview. |
| **1** | `Devices` | `Icons.devices_outlined` / `Icons.devices` | `DevicesTab` | Searchable, filterable inventory of all enrolled peers with subsystem pills, target switching, and node enrollment. |
| **2** | `Connector` | `Icons.cell_tower_outlined` / `Icons.cell_tower` | `ConnectorTab` | Telegram Antigravity Connector operations: mesh overview, peer lifecycle lockout, media command audit stream, structured error feed, and dynamic API runner. |
| **3** | `Settings` | `Icons.settings_outlined` / `Icons.settings` | `SettingsTab` | Network failover preferences, Android Keystore status, and build metadata. |

### 7.2 Navigation Rules
1. **Preserve the 4-Tab Architecture**: Keep the bottom navigation strictly at four destinations (`Home`, `Devices`, `Connector`, `Settings`). Never introduce a fifth tab.
2. **Relocated Terminal Access**: Terminal remains fully operational through three dedicated contextual entry points rather than occupying a bottom-navigation tab:
   - **Home Quick Actions**: The `Terminal` quick action card opens `TerminalTab` via `Navigator.push`, automatically reusing an existing PTY session or connecting to the active host.
   - **Device Detail Screen**: Dedicated `Open Terminal` action in the AppBar and an action button inside the device overview card bound to the inspected host.
   - **Devices Tab Contextual Action**: Direct terminal launch icon on each enrolled device card.
   - **Session Persistence**: Sessions survive navigation popping because `TerminalSessionController` is owned by the app root. An explicit leading back button (`Icons.arrow_back`) is rendered in `TerminalTab` when pushed onto the stack.
3. **Back Button Behavior (`PopScope`)**: In `AppScaffold`, pressing the Android system back button when `_currentTabIndex != 0` returns the user to Tab 0 (`Home`) rather than exiting the app (`canPop: _currentTabIndex == 0`).
4. **Secondary Push Routes**: Deep inspection of a host pushes `DeviceDetailScreen` via `Navigator.of(context).push(MaterialPageRoute(...))`. When pushing `DeviceDetailScreen` from **any** screen (`HomeTab` or `DevicesTab`), callers must pass `isGlobalTarget`, `onSelectAsTarget`, and `onTelemetryUpdated` so target selection and telemetry caching behave identically regardless of entry point.

---

## 8. Context-Aware Interaction & Target Safety Rules

Every device-specific action in LAPDECK must obey these eight operational UX rules:

1. **Always Name the Target Machine**: Every quick action card, confirmation bottom sheet, diagnostic header, terminal prompt (`surajworklaptop$`), and feedback banner must explicitly display `target.name`.
2. **Capture Target Identity at Initiation**: Capture `final target = widget.activeHost;` (or `_capturedTarget`) when the user taps an action. If the user switches the global target while an SSH command or diagnostic run is in flight, the running operation and its resulting `OperationFeedback` banner must remain bound to the original `target`.
3. **Display Target Summary Card in Confirmation Sheets**: Every action bottom sheet (`Terminal`, `Arm/Disarm Away`, `Lock Session`, `Diagnostics`) must include the recessed target summary box (`_buildSheetTargetSummaryCard`) showing OS icon, `target.name`, `<osDisplayName> · <username>@<tailscaleIp>:<port>`, and live reachability badge.
4. **Explain Consequences Before Execution**: Consequential actions must state their physical impact in plain technical English before the user confirms:
   - **Lock Session**: Uses `target.lockConsequenceDescription` (e.g., locking the physical graphical desktop session on Linux via `loginctl`/screensaver or Windows via `LockWorkStation`).
   - **Arm / Disarm Away**: Explains whether webcam capture, PAM monitoring, and Telegram alerts will be armed (`lapdog away`) or suppressed (`lapdog back`).
   - **Sleep Device**: Warns that physical wake or Wake-on-LAN will be required to reconnect.
5. **Warn When Prerequisites Are Unmet**: If `target.peerStatus` is `unreachable`/`offline` or a required service (`SSH` or `Lapdog`) is `unavailable`, display an inline warning box inside the confirmation sheet explaining why the operation may fail before execution.
6. **Protect Active Terminal Sessions from Silent Target Switches**:
   - If `TerminalSessionController.hasActiveSessionFor(target)` is true, tapping the `Terminal` quick action on `HomeTab` jumps immediately to Tab 2 (`onNavigateTab(2)`) and reuses the active PTY session without showing an unnecessary confirmation sheet.
   - If an active PTY session exists on another host (`hasOtherSession`), the confirmation sheet warns the user that connecting to `target.name` will close the active session on `otherHost.name`.
   - If the user switches the global target while a PTY session is connected, `TerminalTab` displays an amber warning bar (`Active shell is on <connectedHost>. Selected target is <selectedTarget>.`) with an explicit `Switch to <selectedTarget>` button.

---

## 9. One-Tap Interaction Philosophy vs. Safety Gates

Balance operational speed with safety by categorizing every interaction into one of three tiers:

| Tier | Interaction Pattern | Examples in LAPDECK |
| :--- | :--- | :--- |
| **Tier 1: Immediate (1-Tap)** | Executes immediately on tap with visual loading indicator; no confirmation modal. | Refresh network/telemetry, switch filter chips, open `DeviceDetailScreen`, resume an already-connected PTY session for the active target, run `Diagnostics`, copy terminal buffer, adjust terminal font size. |
| **Tier 2: Contextual Confirmation Sheet / Dialog (2-Tap)** | Opens a focused bottom sheet or dialog displaying target identity, consequence description, and prerequisite status before executing. | Open new PTY session (or replace another host's PTY), `Arm Away Mode` / `Disarm Away Mode`, `Lock Session`. |
| **Tier 3: Destructive / Irreversible (Confirmation Required)** | Requires explicit confirmation naming the target resource before execution; styled with `DeckColors.error`. | `Delete Node` in `HostConfigDialog`, `Sleep Device` in `QuickControlsCard`, and process termination (`KILL` / `kill -9 <pid>` in `ProcessManagerCard`). |

---

## 10. Progressive Disclosure Rules

Keep `HomeTab` scannable in a single glance by tiering information density:

1. **Primary Surface (`HomeTab`)**: Shows only high-signal operational state:
   - Compact Connectivity Alert (only when degraded/unreachable; technical details collapsed by default behind the expand chevron).
   - Network Overview (overall health, connected peer count, target latency, selected device name).
   - Target Device Selector (active device identity + 4 compact subsystem chips: `Host`, `SSH`, `Agent`, `RTT`).
   - 2x2 Context-Aware Quick Actions + active `OperationFeedback` banner.
   - Connected Devices list (name, OS/role, status, latency).
   - Lapdog Security Summary (mode, daemon health, last check, event counts).
2. **Secondary Surface (`DeviceDetailScreen`)**: Houses deep per-host telemetry that would clutter `HomeTab`:
   - Full 8-row host & route metadata table (`Tailscale Mesh IP`, `Local LAN Route`, `SSH User & Port`, `Auth Strategy`, `Last Health Check`).
   - `VitalsCard` (CPU, RAM, and Root Storage progress bars + verified uptime).
   - Interactive `LapdogCard` toggle.
   - `QuickControlsCard` (`Lock Session`, `Restart Lapdog`, `Sync Skills`, `Sleep Device`).
   - `ProcessManagerCard` (top 8 CPU/memory processes with PIDs and `KILL` controls).
3. **Contextual On-Demand Surfaces (Bottom Sheets & Dialogs)**:
   - `_showTargetSelectorSheet`: Full peer switcher.
   - `_DiagnosticsBottomSheet`: Step-by-step 5-stage diagnostic runner.
   - `HostConfigDialog`: Node enrollment, IP/port/OS configuration, and Keystore credential input.

---

## 11. Android-Specific UX Standards

LAPDECK targets Android (`minSdk = 24`, `compileSdk = 36`, `targetSdk = 35`) with edge-to-edge dark system bars configured in `lib/main.dart`.

1. **System Bar Styling & Insets**:
   - `SystemChrome.setSystemUIOverlayStyle` sets `statusBarColor: Colors.transparent`, `statusBarIconBrightness: Brightness.light`, and `systemNavigationBarColor: DeckColors.background` (`#11151B`).
   - Wrap screen bodies and modal bottom sheets in `SafeArea` so content never collides with Android status bar cutouts or gesture navigation insets.
2. **Touch Targets**: All interactive buttons, icon buttons, and row actions must maintain a minimum `48x48dp` touch target (`44dp` minimum height for secondary inline card buttons). Avoid tiny hit areas on destructive actions.
3. **Tactile Haptic Feedback (`HapticFeedback`)**:
   - `HapticFeedback.lightImpact()`: Terminal modifier keybar taps (`CTRL`, `CTRL-C`, `ESC`, `TAB`, arrows).
   - `HapticFeedback.mediumImpact()`: Device control triggers (`QuickControlsCard`, `QuickActionPad`).
   - `HapticFeedback.heavyImpact()`: Security state toggles (`LapdogCard` Away Mode switch) and process termination (`ProcessManagerCard` kill).
4. **Soft Keyboard & Terminal Layout**: `AndroidManifest.xml` configures `android:windowSoftInputMode="adjustResize"`. `TerminalTab` places the scrollable terminal output inside an `Expanded` widget above the modifier keybar and input row so the keybar and prompt automatically ride above the Android soft keyboard when typing.
5. **Accessibility, Contrast & Font Scaling**:
   - All normal-sized text (`< 18sp` regular or `< 14sp` bold) must meet **WCAG AA contrast (`>= 4.5:1`)** against its background surface (`background`, `surfaceSecondary`, `surfaceElevated`, `surfaceHighlight`). Use `DeckColors.mutedText` at `#8490A3` (`5.26:1` on `surfaceSecondary`, `4.79:1` on `surfaceElevated`), never `#768294` (`4.35:1` and `3.96:1`, which fail WCAG AA).
   - Provide `tooltip` strings on all `IconButton` widgets (which Flutter exposes to Android TalkBack).
   - Use `Wrap` and `Expanded`/`Flexible` in metric rows (`VitalsCard`, `HomeTab`, `DevicesTab`) so Android system font scaling does not cause `RenderFlex` overflow errors.

---

## 12. Loading, Error & Lifecycle Feedback Patterns

1. **No Context-Free Spinners**: Every loading indicator must state what is being checked and on which host (e.g., `Checking network health...`, `Inspecting surajworklaptop...`, `Verifying live reachability and service state on surajworklaptop...`).
2. **Persistent Operation Feedback Banner (`_buildOperationFeedbackBanner`)**:
   - Displayed directly above Quick Actions on `HomeTab` and at the top of `DeviceDetailScreen`.
   - Always shows: uppercase lifecycle state badge (`IN PROGRESS`, `SUCCESSFUL`, `FAILED`, `TIMED OUT`, `RESULT UNKNOWN`, `TARGET UNAVAILABLE`), `<operationName> · <targetHostName>`, human-readable summary, optional monospace `technicalDetails`, and a dismiss (`Icons.close`) button when not busy.
   - When the state is `timedOut`, `resultUnknown`, `failed`, or `targetUnavailable`, render a `Verify <targetHostName> state` action button (`_verifyTargetState`) that re-probes reachability and telemetry to resolve uncertainty.
3. **Stale Data & Timestamp Honesty**:
   - Never display a cached `pingMs` value if the host is currently `unreachable`, `offline`, or `unknown` (`HostTarget.hasFreshLatency` enforces `peerStatus == PeerStatus.online && pingMs != null && lastChecked != null`).
   - Display `Telemetry not verified` in `VitalsCard` when `vitals.isVerified == false`.
   - Format check timestamps consistently: `Not checked yet` when `null`, `Checked just now` (`< 15s`), `Checked Xs ago` (`< 60s`), or `Checked HH:mm:ss` (`>= 60s`).

---

## 13. Motion & Interaction Feedback

1. **Restrained Functional Motion**:
   - Terminal output auto-scrolls smoothly on new chunks using a fast `60ms` `Curves.easeOut` transition (`TerminalTab._onTerminalOutput`).
   - Pull-to-refresh uses standard Material `RefreshIndicator` styled with `color: DeckColors.primaryAccent` and `backgroundColor: DeckColors.surfaceElevated`.
   - Tab switching uses `IndexedStack` (instantaneous switch with zero state loss and zero decorative page-slide delay).
2. **Prohibited Motion**: Do not add looping pulse animations on status dots, particle effects, custom page transition animations, or multi-second splash delays that slow down operational access.

---

## 14. Brand Mark, Logo & Iconography Specification

### 14.1 Product Identity & Core Metaphor
> **One control surface. Multiple remote systems.**

LAPDECK avoids consumer software clichés (laptop outlines, screens, terminal carets, clouds, Wi-Fi arcs, circuit boards, or generic connected graph diagrams). Its brand mark represents an engineered, physical control surface operating across distributed planes.

### 14.2 The Canonical Brand Mark: The Folded Deck (The Cantilever Deck)
The official visual symbol is **The Cantilever Deck** (Direction 1.1), constructed on a 64x64 grid:
- **Lower Ground Plane (Local Deck)**: Grounded base plate (`x: 8, y: 44, width: 48, height: 10, rx: 3px`) in warm signature amber (`#E89A50`).
- **Structural Spine / Vertical Riser**: Monolithic vertical column (`x: 8, y: 12, width: 14, height: 36, rx: 3px`) in primary text neutral (`#F1F3F5`), fused into the base plate to subtly evoke an architectural **L** monogram without becoming a literal typographic glyph.
- **Elevated Remote Plane (Infrastructure Shelf)**: Cantilevered upper plane (`x: 26, y: 12, width: 30, height: 10, rx: 3px`) in warm signature amber (`#E89A50`), separated from the structural riser by an engineered **4px air-gap slot** representing remote isolation.
- **Verification Node**: Precision alignment dot at `(26, 30)` radius `2.5px` in mint emerald (`#36B58E`), symbolizing verified peer connectivity.
- **Master Vector Asset**: `assets/branding/lapdeck_brandmark.svg`

### 14.3 Android Adaptive Launcher Icon Specification
In compliance with Android 8.0+ adaptive icon standards and Android 13+ Material You themed icons:
- **Viewport**: `108 x 108 dp` with an inner `72dp` diameter circular safe zone centered at `(54, 54)`.
- **Background Layer (`ic_launcher_background.xml` / `@color/ic_launcher_background`)**: Solid slate `#11151B`.
- **Foreground Layer (`ic_launcher_foreground.xml`)**: VectorDrawable centering the Cantilever Deck geometry with safe zone padding (all paths bounded within `x: 30..78, y: 34..76`).
- **Monochrome Themed Layer (`ic_launcher_monochrome.xml`)**: Solid white (`#FFFFFF`) silhouette vector enabling dynamic Material You tinting based on the user's Android system wallpaper.
- **Manifest Reference**: `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`

### 14.4 Wordmark Lockup Rules
When pairing the brand mark with text:
- **`LAP` Component**: Rendered in `Inter`, `24sp`, `FontWeight.w800`, `letterSpacing: 0.5`, Color `#F1F3F5`.
- **`DECK` Component**: Rendered in `JetBrains Mono`, `24sp`, `FontWeight.w700`, `letterSpacing: -0.2`, Color `#E89A50`.
- **Subtitle**: `CONTROL SURFACE` in `JetBrains Mono`, `8.5sp`, `FontWeight.w500`, `letterSpacing: 2.2`, Color `#A0AAB8`.
- **Lockup Asset**: `assets/branding/lapdeck_wordmark_lockup.svg`

### 14.5 Small Navigation Icon Family Rules
All navigation and contextual action icons must share consistent visual weight:
- **Grid Alignment**: Standard `24x24dp` bounding box with `2dp` padding.
- **Stroke & Mass**: Stroke width `1.8dp` for unselected outlined icons; `2.2dp` or solid silhouette for active selected icons.
- **Fillet Consistency**: `2.0dp` outer corner fillets; sharp `0dp` inner vertices matching the brand mark geometry.

