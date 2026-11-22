import 'dart:convert';

enum HostOs { linux, windows, macos }
enum AuthMethod { privateKey, password, tailscaleSsh }

/// Independent reachability state of a peer machine on the network.
enum PeerStatus {
  unknown,
  connecting,
  online,
  unreachable,
  offline,
}

/// Independent availability state of a specific service (SSH, Agent, Lapdog).
enum ServiceStatus {
  unknown,
  connecting,
  available,
  unavailable,
}

class HostTarget {
  final String id;
  final String name;
  final String tailscaleIp;
  final int port;
  final String username;
  final AuthMethod authMethod;
  final HostOs os;
  final String? directIp;
  final String? privateKey;
  final bool isDirect;
  final int? pingMs;
  final bool isOnline;
  final DateTime? lastConnected;
  final DateTime? lastChecked;
  final String? description;
  final PeerStatus peerStatus;
  final ServiceStatus sshStatus;
  final ServiceStatus agentStatus;
  final ServiceStatus lapdogDaemonStatus;
  final String? lastError;

  const HostTarget({
    required this.id,
    required this.name,
    required this.tailscaleIp,
    this.port = 22,
    required this.username,
    this.authMethod = AuthMethod.privateKey,
    required this.os,
    this.directIp,
    this.privateKey,
    this.isDirect = false,
    this.pingMs,
    this.isOnline = false,
    this.lastConnected,
    this.lastChecked,
    this.description,
    this.peerStatus = PeerStatus.unknown,
    this.sshStatus = ServiceStatus.unknown,
    this.agentStatus = ServiceStatus.unknown,
    this.lapdogDaemonStatus = ServiceStatus.unknown,
    this.lastError,
  });

  /// Human-readable OS name extracted from description or OS enum.
  String get osDisplayName {
    if (description != null && description!.contains('•')) {
      final parts = description!.split('•');
      if (parts.length > 1 && parts[1].trim().isNotEmpty) {
        return parts[1].trim();
      }
    }
    return switch (os) {
      HostOs.linux => 'Linux',
      HostOs.windows => 'Windows',
      HostOs.macos => 'macOS',
    };
  }

  /// Human-readable role or short description without duplicating OS label.
  String get roleDisplayName {
    if (description != null && description!.contains('•')) {
      final first = description!.split('•').first.trim();
      if (first.isNotEmpty) return first;
    }
    if (description != null && description!.trim().isNotEmpty) {
      return description!.trim();
    }
    return switch (os) {
      HostOs.linux => 'Linux Workstation',
      HostOs.windows => 'Windows Workstation',
      HostOs.macos => 'macOS Workstation',
    };
  }

  /// Accurate OS-specific lock action label based on actual backend support.
  String get lockActionTitle {
    return switch (os) {
      HostOs.windows => 'Lock Windows Session',
      HostOs.linux => 'Lock Linux Session',
      HostOs.macos => 'Lock macOS Session',
    };
  }

  /// Accurate OS-specific session lock command that targets the physical
  /// graphical session (not the SSH tty) and verifies the locked state.
  ///
  /// On Windows (where OpenSSH DefaultShell is PowerShell and SSH sessions
  /// run in non-interactive Session 0), `LockWorkStation` must be dispatched
  /// into the interactive console user session (Session 1+) via an interactive
  /// (`/IT`) scheduled task or `tsdiscon.exe`, followed by verifying that
  /// `LogonUI` is active.
  String get lockSessionCommand {
    return switch (os) {
      HostOs.windows => r'''
$ErrorActionPreference = 'SilentlyContinue'
if (Get-Command tsdiscon.exe -ErrorAction SilentlyContinue) {
  & tsdiscon.exe 2>$null
}
& schtasks.exe /Create /TN "LapDeckLock" /TR "rundll32.exe user32.dll,LockWorkStation" /SC ONCE /ST 00:00 /IT /F 2>$null | Out-Null
& schtasks.exe /Run /TN "LapDeckLock" 2>$null | Out-Null
& rundll32.exe user32.dll,LockWorkStation 2>$null
Start-Sleep -Milliseconds 900
& schtasks.exe /Delete /TN "LapDeckLock" /F 2>$null | Out-Null
$locked = Get-Process -Name LogonUI -ErrorAction SilentlyContinue
if ($locked) {
  Write-Output "LOCK_CONFIRMED:WINDOWS_LOGONUI"
  exit 0
}
Write-Error "Failed to verify Windows session lock (LogonUI not detected)."
exit 1
''',
      HostOs.linux => '''
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/\$(id -u)/bus"
gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.Lock >/dev/null 2>&1 || true
gdbus call --session --dest org.freedesktop.ScreenSaver --object-path /org/freedesktop/ScreenSaver --method org.freedesktop.ScreenSaver.Lock >/dev/null 2>&1 || true
for sid in \$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print \$1}'); do
  stype=\$(loginctl show-session "\$sid" -p Type --value 2>/dev/null)
  if [ "\$stype" = "wayland" ] || [ "\$stype" = "x11" ]; then
    loginctl lock-session "\$sid" 2>/dev/null || true
  fi
done
loginctl lock-sessions 2>/dev/null || true
sleep 0.4
if gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.GetActive 2>/dev/null | grep -q "true"; then
  echo "LOCK_CONFIRMED:GNOME_SCREENSAVER"
  exit 0
fi
for sid in \$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print \$1}'); do
  stype=\$(loginctl show-session "\$sid" -p Type --value 2>/dev/null)
  locked=\$(loginctl show-session "\$sid" -p LockedHint --value 2>/dev/null)
  if { [ "\$stype" = "wayland" ] || [ "\$stype" = "x11" ]; } && [ "\$locked" = "yes" ]; then
    echo "LOCK_CONFIRMED:LOGIND_\$sid"
    exit 0
  fi
done
echo "Failed to verify graphical session lock (LockedHint remained no)." >&2
exit 1
''',
      HostOs.macos => 'pmset displaysleepnow',
    };
  }

  /// OS-specific process termination command (PowerShell on Windows, POSIX on Linux/macOS).
  String killProcessCommand(int pid) {
    return switch (os) {
      HostOs.windows => 'Stop-Process -Id $pid -Force -ErrorAction Stop',
      HostOs.linux || HostOs.macos => 'kill -9 $pid',
    };
  }

  /// OS-specific system suspend / sleep command.
  String get sleepDeviceCommand {
    return switch (os) {
      HostOs.windows => 'rundll32.exe powrprof.dll,SetSuspendState 0,1,0',
      HostOs.linux => 'systemctl suspend',
      HostOs.macos => 'pmset sleepnow',
    };
  }

  /// Consequence explanation for locking this specific host.
  String get lockConsequenceDescription {
    return switch (os) {
      HostOs.windows =>
        'Executes LockWorkStation on $name. The active Windows desktop session will immediately lock and require user credentials at the physical machine.',
      HostOs.linux =>
        'Locks the active graphical user session on $name via loginctl/screensaver. Local credentials will be required to unlock the display.',
      HostOs.macos =>
        'Puts the display to sleep and locks the active macOS session on $name.',
    };
  }

  /// Clear reachability label following Section 3 terminology.
  String get reachabilityLabel {
    return switch (peerStatus) {
      PeerStatus.online => 'Online',
      PeerStatus.unreachable => 'Unreachable',
      PeerStatus.offline => 'Offline',
      PeerStatus.connecting => 'Connecting',
      PeerStatus.unknown => 'Unknown',
    };
  }

  /// Clear SSH service label following Section 3 terminology.
  String get sshStatusLabel {
    return switch (sshStatus) {
      ServiceStatus.available => 'Available',
      ServiceStatus.unavailable => 'Unavailable',
      ServiceStatus.connecting => 'Connecting',
      ServiceStatus.unknown => 'Unknown',
    };
  }

  /// Clear LAPDECK telemetry agent label.
  String get agentStatusLabel {
    return switch (agentStatus) {
      ServiceStatus.available => 'Available',
      ServiceStatus.unavailable => 'Unavailable',
      ServiceStatus.connecting => 'Connecting',
      ServiceStatus.unknown => 'Unknown',
    };
  }

  /// Clear Lapdog daemon label.
  String get lapdogStatusLabel {
    return switch (lapdogDaemonStatus) {
      ServiceStatus.available => 'Available',
      ServiceStatus.unavailable => 'Unavailable',
      ServiceStatus.connecting => 'Connecting',
      ServiceStatus.unknown => 'Unknown',
    };
  }

  /// True only when latency was measured during a verified online check.
  bool get hasFreshLatency =>
      peerStatus == PeerStatus.online && pingMs != null && lastChecked != null;

  HostTarget copyWith({
    String? id,
    String? name,
    String? tailscaleIp,
    int? port,
    String? username,
    AuthMethod? authMethod,
    HostOs? os,
    String? directIp,
    String? privateKey,
    bool? isDirect,
    int? pingMs,
    bool clearPing = false,
    bool? isOnline,
    DateTime? lastConnected,
    DateTime? lastChecked,
    String? description,
    PeerStatus? peerStatus,
    ServiceStatus? sshStatus,
    ServiceStatus? agentStatus,
    ServiceStatus? lapdogDaemonStatus,
    String? lastError,
    bool clearError = false,
  }) {
    final nextPeerStatus = peerStatus ?? this.peerStatus;
    final nextIsOnline = isOnline ?? (nextPeerStatus == PeerStatus.online);
    return HostTarget(
      id: id ?? this.id,
      name: name ?? this.name,
      tailscaleIp: tailscaleIp ?? this.tailscaleIp,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      os: os ?? this.os,
      directIp: directIp ?? this.directIp,
      privateKey: privateKey ?? this.privateKey,
      isDirect: isDirect ?? this.isDirect,
      pingMs: clearPing ? null : (pingMs ?? this.pingMs),
      isOnline: nextIsOnline,
      lastConnected: lastConnected ?? this.lastConnected,
      lastChecked: lastChecked ?? this.lastChecked,
      description: description ?? this.description,
      peerStatus: nextPeerStatus,
      sshStatus: sshStatus ?? this.sshStatus,
      agentStatus: agentStatus ?? this.agentStatus,
      lapdogDaemonStatus: lapdogDaemonStatus ?? this.lapdogDaemonStatus,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'tailscaleIp': tailscaleIp,
      'port': port,
      'username': username,
      'authMethod': authMethod.name,
      'os': os.name,
      'directIp': directIp,
      'isDirect': isDirect,
      'description': description,
    };
  }

  factory HostTarget.fromMap(Map<String, dynamic> map) {
    return HostTarget(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      tailscaleIp: map['tailscaleIp'] ?? '',
      port: map['port'] ?? 22,
      username: map['username'] ?? '',
      authMethod: AuthMethod.values.firstWhere(
        (e) => e.name == map['authMethod'],
        orElse: () => AuthMethod.privateKey,
      ),
      os: HostOs.values.firstWhere(
        (e) => e.name == map['os'],
        orElse: () => HostOs.linux,
      ),
      directIp: map['directIp'],
      isDirect: map['isDirect'] ?? false,
      description: map['description'],
      isOnline: false,
      pingMs: null,
      peerStatus: PeerStatus.unknown,
      sshStatus: ServiceStatus.unknown,
      agentStatus: ServiceStatus.unknown,
      lapdogDaemonStatus: ServiceStatus.unknown,
    );
  }

  String toJson() => json.encode(toMap());
  factory HostTarget.fromJson(String source) =>
      HostTarget.fromMap(json.decode(source));

  static List<HostTarget> get defaultHosts => [
        const HostTarget(
          id: 'host-surajworklaptop',
          name: 'surajworklaptop',
          tailscaleIp: '100.118.7.117',
          port: 22,
          username: 'surajwork',
          authMethod: AuthMethod.privateKey,
          os: HostOs.linux,
          directIp: '192.168.29.112',
          description: 'Primary Linux Rig • Ubuntu 24.04 LTS',
          isOnline: false,
          isDirect: false,
          pingMs: null,
          peerStatus: PeerStatus.unknown,
          sshStatus: ServiceStatus.unknown,
          agentStatus: ServiceStatus.unknown,
          lapdogDaemonStatus: ServiceStatus.unknown,
        ),
        const HostTarget(
          id: 'host-mochirondesu',
          name: 'mochirondesu',
          tailscaleIp: '100.79.206.82',
          port: 22,
          username: 'qwerk',
          authMethod: AuthMethod.privateKey,
          os: HostOs.windows,
          directIp: '192.168.29.61',
          description: 'Secondary Rig • Windows 11 / WSL2',
          isOnline: false,
          isDirect: false,
          pingMs: null,
          peerStatus: PeerStatus.unknown,
          sshStatus: ServiceStatus.unknown,
          agentStatus: ServiceStatus.unknown,
          lapdogDaemonStatus: ServiceStatus.unknown,
        ),
      ];
}
