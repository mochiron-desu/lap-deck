import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/host_target.dart';
import '../models/remote_file_item.dart';
import '../models/vitals_data.dart';
import 'app_logger.dart';

class SshExecutionResult {
  final int? exitCode;
  final String output;
  final String error;
  final Duration duration;
  final String connectedEndpoint;
  final bool isTimeout;
  final bool isConnectionFailure;

  const SshExecutionResult({
    this.exitCode,
    required this.output,
    required this.error,
    required this.duration,
    required this.connectedEndpoint,
    this.isTimeout = false,
    this.isConnectionFailure = false,
  });

  bool get isSuccess =>
      exitCode == 0 && !isTimeout && !isConnectionFailure;
}

class HostReachability {
  final bool isOnline;
  final PeerStatus peerStatus;
  final ServiceStatus sshPortStatus;
  final int? latencyMs;
  final bool isDirect;
  final bool localTailscaleActive;
  final String? errorDetail;
  final DateTime checkedAt;

  const HostReachability({
    required this.isOnline,
    required this.peerStatus,
    required this.sshPortStatus,
    this.latencyMs,
    this.isDirect = false,
    this.localTailscaleActive = false,
    this.errorDetail,
    required this.checkedAt,
  });
}

class TelemetryBundle {
  final VitalsData vitals;
  final List<ProcessItem> processes;
  final LapdogStatus lapdog;
  final DateTime fetchedAt;

  const TelemetryBundle({
    required this.vitals,
    required this.processes,
    required this.lapdog,
    required this.fetchedAt,
  });
}

class SshService {
  SSHClient? _activeClient;
  SSHSession? _activeShellSession;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  // Per-host reusable command execution connection pool (keyed by host.id)
  final Map<String, SSHClient> _cmdClientPool = {};

  bool get isConnected =>
      _activeClient != null && !(_activeClient?.isClosed ?? true);

  /// Checks whether the local Android/Linux device has an active Tailscale
  /// CGNAT (100.64.0.0/10) network interface.
  Future<bool> isLocalTailscaleActive() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        final nameLower = iface.name.toLowerCase();
        if (nameLower.contains('tailscale') || nameLower.contains('tun')) {
          for (final addr in iface.addresses) {
            if (_isTailscaleCgnat(addr.address)) {
              AppLogger.debug('SshService', 'Tailscale interface active: ${iface.name} (${addr.address})');
              return true;
            }
          }
        }
        for (final addr in iface.addresses) {
          if (_isTailscaleCgnat(addr.address)) {
            AppLogger.debug('SshService', 'Tailscale CGNAT addr active: ${iface.name} (${addr.address})');
            return true;
          }
        }
      }
    } catch (e, st) {
      AppLogger.warning('SshService', 'Failed inspecting local network interfaces: $e', e, st);
    }
    return false;
  }

  bool _isTailscaleCgnat(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) return false;
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    if (first == 100 && second != null && second >= 64 && second <= 127) {
      return true;
    }
    return false;
  }

  /// Executes a command against a specific [host] (identified by host.id).
  /// Distinguishes connection failure (before execution) from execution timeout
  /// (where the remote command may still have taken effect).
  Future<SshExecutionResult> executeCommand({
    required HostTarget host,
    required String command,
    String? password,
    String? privateKeyPem,
    Duration timeout = const Duration(seconds: 4),
    Duration executionTimeout = const Duration(seconds: 8),
  }) async {
    final stopwatch = Stopwatch()..start();
    String connectedIp = host.tailscaleIp;
    SSHClient? client;

    // Step 1: Establish or reuse SSH client for this specific host.id
    try {
      final cached = _cmdClientPool[host.id];
      if (cached != null && !cached.isClosed) {
        client = cached;
      } else {
        try {
          cached?.close();
        } catch (_) {}
        _cmdClientPool.remove(host.id);

        try {
          client = await _connectToIp(
            ip: host.tailscaleIp,
            port: host.port,
            username: host.username,
            password: password,
            privateKeyPem: privateKeyPem,
            timeout: timeout,
          );
        } catch (e) {
          if (host.directIp != null && host.directIp!.isNotEmpty) {
            connectedIp = host.directIp!;
            client = await _connectToIp(
              ip: host.directIp!,
              port: host.port,
              username: host.username,
              password: password,
              privateKeyPem: privateKeyPem,
              timeout: timeout,
            );
          } else {
            rethrow;
          }
        }
        _cmdClientPool[host.id] = client;
      }
    } catch (e) {
      try {
        _cmdClientPool[host.id]?.close();
      } catch (_) {}
      _cmdClientPool.remove(host.id);
      stopwatch.stop();
      return SshExecutionResult(
        exitCode: -1,
        output: '',
        error: 'SSH connection failed: $e',
        duration: stopwatch.elapsed,
        connectedEndpoint: connectedIp,
        isTimeout: false,
        isConnectionFailure: true,
      );
    }

    // Step 2: Execute command over the established SSH session
    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();
    StreamSubscription? outSub;
    StreamSubscription? errSub;

    try {
      final session = await client.execute(command).timeout(executionTimeout);

      outSub = session.stdout.listen((bytes) {
        stdoutBuffer.write(utf8.decode(bytes, allowMalformed: true));
      });
      errSub = session.stderr.listen((bytes) {
        stderrBuffer.write(utf8.decode(bytes, allowMalformed: true));
      });

      await session.done.timeout(executionTimeout);
      await outSub.cancel();
      await errSub.cancel();

      stopwatch.stop();

      return SshExecutionResult(
        exitCode: session.exitCode ?? 0,
        output: stdoutBuffer.toString().trim(),
        error: stderrBuffer.toString().trim(),
        duration: stopwatch.elapsed,
        connectedEndpoint: connectedIp,
        isTimeout: false,
        isConnectionFailure: false,
      );
    } on TimeoutException {
      await outSub?.cancel();
      await errSub?.cancel();
      stopwatch.stop();
      return SshExecutionResult(
        exitCode: null,
        output: stdoutBuffer.toString().trim(),
        error:
            'Command timed out after ${executionTimeout.inSeconds}s on ${host.name}. The remote operation may still have completed.',
        duration: stopwatch.elapsed,
        connectedEndpoint: connectedIp,
        isTimeout: true,
        isConnectionFailure: false,
      );
    } catch (e) {
      await outSub?.cancel();
      await errSub?.cancel();
      try {
        _cmdClientPool[host.id]?.close();
      } catch (_) {}
      _cmdClientPool.remove(host.id);

      stopwatch.stop();
      return SshExecutionResult(
        exitCode: -1,
        output: stdoutBuffer.toString().trim(),
        error: e.toString(),
        duration: stopwatch.elapsed,
        connectedEndpoint: connectedIp,
        isTimeout: false,
        isConnectionFailure: false,
      );
    }
  }

  /// Starts an interactive PTY shell session with real-time stream subscription.
  Future<bool> startInteractiveShell({
    required HostTarget host,
    required Function(String chunk) onOutput,
    required Function() onDisconnected,
    String? password,
    String? privateKeyPem,
    int width = 80,
    int height = 24,
  }) async {
    try {
      await disconnectShell();

      SSHClient? client;
      try {
        client = await _connectToIp(
          ip: host.tailscaleIp,
          port: host.port,
          username: host.username,
          password: password,
          privateKeyPem: privateKeyPem,
          timeout: const Duration(seconds: 4),
        );
      } catch (_) {
        if (host.directIp != null && host.directIp!.isNotEmpty) {
          client = await _connectToIp(
            ip: host.directIp!,
            port: host.port,
            username: host.username,
            password: password,
            privateKeyPem: privateKeyPem,
            timeout: const Duration(seconds: 4),
          );
        } else {
          rethrow;
        }
      }

      _activeClient = client;

      final session = await client.shell(
        pty: SSHPtyConfig(
          width: width,
          height: height,
          type: 'xterm-256color',
        ),
      );

      _activeShellSession = session;

      _stdoutSub = session.stdout.listen(
        (data) => onOutput(utf8.decode(data, allowMalformed: true)),
        onDone: () => onDisconnected(),
        onError: (_) => onDisconnected(),
      );

      _stderrSub = session.stderr.listen(
        (data) => onOutput(utf8.decode(data, allowMalformed: true)),
      );

      return true;
    } catch (e) {
      await disconnectShell();
      return false;
    }
  }

  /// Send user keystroke or string into the live shell session.
  void sendShellInput(String input) {
    if (_activeShellSession != null && isConnected) {
      _activeShellSession!.write(Uint8List.fromList(utf8.encode(input)));
    }
  }

  /// Close only the interactive shell session without killing background telemetry clients.
  Future<void> disconnectShell() async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;

    try {
      _activeShellSession?.close();
    } catch (_) {}
    _activeShellSession = null;

    try {
      _activeClient?.close();
    } catch (_) {}
    _activeClient = null;
  }

  /// Close and cleanup all SSH sessions and connection pools.
  Future<void> disconnect() async {
    await disconnectShell();
    for (final client in _cmdClientPool.values) {
      try {
        client.close();
      } catch (_) {}
    }
    _cmdClientPool.clear();
  }

  /// Independently probes peer reachability vs SSH port availability.
  /// - Does NOT report Tailscale failure if only SSH port is closed/refused.
  /// - Does NOT mark a peer offline if it responds on the network (e.g. TCP reset or ICMP ping) while SSH is unavailable.
  Future<HostReachability> checkReachability(
    HostTarget host, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final now = DateTime.now();
    final localTs = await isLocalTailscaleActive();

    // 1. Try Tailscale IP TCP connect to SSH port
    final tsSw = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        host.tailscaleIp,
        host.port,
        timeout: timeout,
      );
      tsSw.stop();
      socket.destroy();
      return HostReachability(
        isOnline: true,
        peerStatus: PeerStatus.online,
        sshPortStatus: ServiceStatus.available,
        latencyMs: tsSw.elapsedMilliseconds,
        isDirect: false,
        localTailscaleActive: true,
        checkedAt: now,
      );
    } on SocketException catch (e) {
      tsSw.stop();
      final msg = e.message.toLowerCase();
      final errCode = e.osError?.errorCode;
      // Connection refused (errno 111 on Linux/Android, 61 on macOS) means the
      // packet reached the peer over Tailscale, so the peer IS online,
      // but the SSH daemon on port [host.port] is not listening.
      if (errCode == 111 || errCode == 61 || msg.contains('connection refused')) {
        return HostReachability(
          isOnline: true,
          peerStatus: PeerStatus.online,
          sshPortStatus: ServiceStatus.unavailable,
          latencyMs: tsSw.elapsedMilliseconds,
          isDirect: false,
          localTailscaleActive: true,
          errorDetail:
              '${host.name} is online on Tailscale (${host.tailscaleIp}), but SSH port ${host.port} refused connection.',
          checkedAt: now,
        );
      }
    } catch (_) {
      tsSw.stop();
    }

    // 2. Try Direct LAN IP if configured
    if (host.directIp != null && host.directIp!.isNotEmpty) {
      final lanSw = Stopwatch()..start();
      try {
        final socket = await Socket.connect(
          host.directIp!,
          host.port,
          timeout: timeout,
        );
        lanSw.stop();
        socket.destroy();
        return HostReachability(
          isOnline: true,
          peerStatus: PeerStatus.online,
          sshPortStatus: ServiceStatus.available,
          latencyMs: lanSw.elapsedMilliseconds,
          isDirect: true,
          localTailscaleActive: localTs,
          checkedAt: now,
        );
      } on SocketException catch (e) {
        lanSw.stop();
        final msg = e.message.toLowerCase();
        final errCode = e.osError?.errorCode;
        if (errCode == 111 || errCode == 61 || msg.contains('connection refused')) {
          return HostReachability(
            isOnline: true,
            peerStatus: PeerStatus.online,
            sshPortStatus: ServiceStatus.unavailable,
            latencyMs: lanSw.elapsedMilliseconds,
            isDirect: true,
            localTailscaleActive: localTs,
            errorDetail:
                '${host.name} is reachable on LAN (${host.directIp}), but SSH port ${host.port} refused connection.',
            checkedAt: now,
          );
        }
      } catch (_) {
        lanSw.stop();
      }
    }

    // 3. Fast ICMP ping check to distinguish "Peer online, SSH filtered" from "Host unreachable"
    final pingLatency = await _tryPingLatency(host.tailscaleIp);
    if (pingLatency != null) {
      return HostReachability(
        isOnline: true,
        peerStatus: PeerStatus.online,
        sshPortStatus: ServiceStatus.unavailable,
        latencyMs: pingLatency,
        isDirect: false,
        localTailscaleActive: true,
        errorDetail:
            '${host.name} responds on Tailscale (${host.tailscaleIp}), but SSH port ${host.port} is unreachable.',
        checkedAt: now,
      );
    }

    return HostReachability(
      isOnline: false,
      peerStatus: PeerStatus.unreachable,
      sshPortStatus: ServiceStatus.unavailable,
      latencyMs: null,
      isDirect: false,
      localTailscaleActive: localTs,
      errorDetail: localTs
          ? 'Tailscale mesh is active, but ${host.name} (${host.tailscaleIp}) did not respond.'
          : 'Cannot reach ${host.name} (${host.tailscaleIp}). Tailscale VPN interface was not detected on this device.',
      checkedAt: now,
    );
  }

  Future<int?> _tryPingLatency(String ip) async {
    try {
      final result = await Process.run(
        'ping',
        ['-c', '1', '-W', '1', ip],
      ).timeout(const Duration(milliseconds: 1200));
      if (result.exitCode == 0) {
        final out = result.stdout.toString();
        final match = RegExp(r'time=([\d.]+)\s*ms').firstMatch(out);
        if (match != null) {
          final ms = double.tryParse(match.group(1)!);
          if (ms != null) return ms.round();
        }
        return 1;
      }
    } catch (_) {}
    return null;
  }

  /// Single-command batched telemetry fetch for Vitals, Processes, and Lapdog.
  Future<TelemetryBundle?> fetchTelemetryBundle(
    HostTarget host, {
    String? secret,
  }) async {
    final String script;
    if (host.os == HostOs.windows) {
      script = '''
Write-Output "===LAPDECK_VITALS==="
\$perf = Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction SilentlyContinue
\$cpu = if (\$perf) { [Math]::Round(\$perf.PercentProcessorTime, 1) } else { [Math]::Round(((Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average), 1) }
Write-Output "CPU_USAGE:\$cpu"
Write-Output "CPU_LOAD:\$cpu%"
\$os = Get-CimInstance Win32_OperatingSystem
\$totMem = [Math]::Round(\$os.TotalVisibleMemorySize / 1MB, 1)
\$freeMem = [Math]::Round(\$os.FreePhysicalMemory / 1MB, 1)
\$usedMem = [Math]::Round(\$totMem - \$freeMem, 1)
\$memPct = [Math]::Round((\$usedMem / \$totMem) * 100, 0)
Write-Output "MEM_INFO:\$usedMem/\$totMem GB (\$memPct%)"
\$d = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'"
\$totDisk = [Math]::Round(\$d.Size / 1GB, 0)
\$freeDisk = [Math]::Round(\$d.FreeSpace / 1GB, 0)
\$usedDisk = [Math]::Round(\$totDisk - \$freeDisk, 0)
\$diskPct = [Math]::Round((\$usedDisk / \$totDisk) * 100, 0)
Write-Output "DISK_INFO:\${usedDisk}G/\${totDisk}G (\$diskPct%)"
\$up = (Get-Date) - \$os.LastBootUpTime
Write-Output "UPTIME:\$([int]\$up.TotalHours) hours, \$(\$up.Minutes) minutes"
\$locked = Get-Process -Name LogonUI -ErrorAction SilentlyContinue
if (\$locked) { Write-Output "SESSION_LOCK:LOCKED" } else { Write-Output "SESSION_LOCK:UNLOCKED" }
Write-Output "===LAPDECK_PROCESSES==="
\$cores = [Math]::Max((Get-CimInstance Win32_ComputerSystem).NumberOfLogicalProcessors, 1)
\$totMemBytes = \$os.TotalVisibleMemorySize * 1KB
Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction SilentlyContinue | Where-Object { \$_.Name -ne '_Total' -and \$_.Name -ne 'Idle' } | Sort-Object PercentProcessorTime -Descending | Select-Object -First 8 | ForEach-Object {
    \$pCpu = [Math]::Round(\$_.PercentProcessorTime / \$cores, 1)
    \$pMem = if (\$totMemBytes -gt 0) { [Math]::Round((\$_.WorkingSetPrivate / \$totMemBytes) * 100, 1) } else { 0.0 }
    "\$(\$_.IDProcess) \$(\$_.Name) \$pCpu \$pMem \$(\$_.Name)"
}
Write-Output "===LAPDECK_LAPDOG==="
Write-Output "LAPDOG_NOT_FOUND"
''';
    } else {
      script = '''
echo "===LAPDECK_VITALS==="
echo "CPU_USAGE:\$(top -bn1 2>/dev/null | grep 'Cpu(s)' | awk '{print \$2 + \$4}' || echo '0')"
echo "CPU_LOAD:\$(uptime 2>/dev/null | awk -F'load average:' '{ print \$2 }' | cut -d, -f1 | tr -d ' ' || echo '0.00')"
echo "MEM_INFO:\$(free -m 2>/dev/null | awk '/Mem:/ { printf "%.1f/%.1f GB (%.0f%%)", \$3/1024, \$2/1024, (\$3/\$2)*100 }' || echo '0.0/0.0 GB (0%)')"
echo "DISK_INFO:\$(df -h / 2>/dev/null | awk 'NR==2 { printf "%s/%s (%s)", \$3, \$2, \$5 }' || echo '0/0 GB (0%)')"
echo "UPTIME:\$(uptime -p 2>/dev/null || uptime 2>/dev/null | awk -F'up ' '{print \$2}' | cut -d, -f1 || echo 'Active')"
if [ -n "\$DBUS_SESSION_BUS_ADDRESS" ] || [ -e "/run/user/\$(id -u)/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="\${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/\$(id -u)/bus}"
fi
LOCKED_FOUND=0
if gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.GetActive 2>/dev/null | grep -q "true"; then
  LOCKED_FOUND=1
else
  for sid in \$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print \$1}'); do
    stype=\$(loginctl show-session "\$sid" -p Type --value 2>/dev/null)
    locked=\$(loginctl show-session "\$sid" -p LockedHint --value 2>/dev/null)
    if { [ "\$stype" = "wayland" ] || [ "\$stype" = "x11" ]; } && [ "\$locked" = "yes" ]; then
      LOCKED_FOUND=1
      break
    fi
  done
fi
if [ "\$LOCKED_FOUND" -eq 1 ]; then
  echo "SESSION_LOCK:LOCKED"
else
  echo "SESSION_LOCK:UNLOCKED"
fi
echo "===LAPDECK_PROCESSES==="
ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -n 9 | tail -n +2 || true
echo "===LAPDECK_LAPDOG==="
lapdog status 2>/dev/null || ~/.local/bin/lapdog status 2>/dev/null || echo "LAPDOG_NOT_FOUND"
''';
    }

    final res = await executeCommand(
      host: host,
      command: script,
      password: host.authMethod == AuthMethod.password ? secret : null,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
    );

    if (!res.isSuccess || res.output.isEmpty) return null;

    final output = res.output;
    final vitalsPart = _extractSection(
      output,
      '===LAPDECK_VITALS===',
      '===LAPDECK_PROCESSES===',
    );
    final procsPart = _extractSection(
      output,
      '===LAPDECK_PROCESSES===',
      '===LAPDECK_LAPDOG===',
    );
    final lapdogPart = _extractSection(output, '===LAPDECK_LAPDOG===', null);
    final now = DateTime.now();

    return TelemetryBundle(
      vitals: _parseVitalsOutput(vitalsPart, now),
      processes: _parseProcessesOutput(procsPart),
      lapdog: _parseLapdogOutput(lapdogPart, now),
      fetchedAt: now,
    );
  }

  String _extractSection(String full, String startTag, String? endTag) {
    final startIdx = full.indexOf(startTag);
    if (startIdx == -1) return '';
    final contentStart = startIdx + startTag.length;
    if (endTag != null) {
      final endIdx = full.indexOf(endTag, contentStart);
      if (endIdx != -1) {
        return full.substring(contentStart, endIdx).trim();
      }
    }
    return full.substring(contentStart).trim();
  }

  VitalsData _parseVitalsOutput(String output, DateTime timestamp) {
    double cpuPercent = 0.0;
    String loadAvg = '0.00';
    double ramPercent = 0.0;
    String ramUsage = '0.0 / 0.0 GB';
    double diskPercent = 0.0;
    String diskUsage = '0 / 0 GB';
    String uptime = 'Online';
    bool? isScreenLocked;

    final lines = output.split('\n');
    for (final line in lines) {
      if (line.startsWith('CPU_USAGE:')) {
        final val =
            double.tryParse(line.replaceFirst('CPU_USAGE:', '').trim()) ?? 0.0;
        cpuPercent = (val / 100.0).clamp(0.0, 1.0);
      } else if (line.startsWith('CPU_LOAD:')) {
        final v = line.replaceFirst('CPU_LOAD:', '').trim();
        if (v.isNotEmpty) loadAvg = v;
      } else if (line.startsWith('MEM_INFO:')) {
        final v = line.replaceFirst('MEM_INFO:', '').trim();
        if (v.isNotEmpty) ramUsage = v;
        final match = RegExp(r'\((\d+)%\)').firstMatch(ramUsage);
        if (match != null) {
          ramPercent = (double.tryParse(match.group(1)!) ?? 0.0) / 100.0;
        }
      } else if (line.startsWith('DISK_INFO:')) {
        final v = line.replaceFirst('DISK_INFO:', '').trim();
        if (v.isNotEmpty) diskUsage = v;
        final match = RegExp(r'\((\d+)%\)').firstMatch(diskUsage);
        if (match != null) {
          diskPercent = (double.tryParse(match.group(1)!) ?? 0.0) / 100.0;
        }
      } else if (line.startsWith('UPTIME:')) {
        final v =
            line.replaceFirst('UPTIME:', '').replaceFirst('up ', '').trim();
        if (v.isNotEmpty) uptime = v;
      } else if (line.startsWith('SESSION_LOCK:')) {
        final v = line.replaceFirst('SESSION_LOCK:', '').trim();
        if (v == 'LOCKED') {
          isScreenLocked = true;
        } else if (v == 'UNLOCKED') {
          isScreenLocked = false;
        }
      }
    }

    return VitalsData(
      cpuPercent: cpuPercent,
      loadAvg: loadAvg,
      ramPercent: ramPercent,
      ramUsage: ramUsage,
      diskPercent: diskPercent,
      diskUsage: diskUsage,
      uptime: uptime,
      timestamp: timestamp,
      isVerified: true,
      isScreenLocked: isScreenLocked,
    );
  }

  List<ProcessItem> _parseProcessesOutput(String output) {
    final list = <ProcessItem>[];
    for (final line in output.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length >= 5) {
        final pid = int.tryParse(parts[0]) ?? 0;
        final user = parts[1];
        final cpu = double.tryParse(parts[2]) ?? 0.0;
        final mem = double.tryParse(parts[3]) ?? 0.0;
        final name = parts.sublist(4).join(' ');
        if (pid > 0 && name != 'ps') {
          list.add(ProcessItem(
            pid: pid,
            name: name,
            cpuPercent: cpu,
            memPercent: mem,
            user: user,
          ));
        }
      }
    }
    return list;
  }

  LapdogStatus _parseLapdogOutput(String output, DateTime timestamp) {
    if (output.isEmpty || output.contains('LAPDOG_NOT_FOUND')) {
      return LapdogStatus(
        isInstalled: false,
        lastChecked: timestamp,
        isVerified: true,
      );
    }
    final isAway = output.contains('Away Mode:      ARMED') ||
        output.toUpperCase().contains('ARMED');
    final isInstalled = output.contains('lap-dog Status Dashboard') ||
        output.toLowerCase().contains('lap-dog') ||
        output.toLowerCase().contains('away mode');

    int pending = 0;
    int sent = 0;
    final pendingMatch = RegExp(r'Pending Queue:\s+(\d+)').firstMatch(output);
    if (pendingMatch != null) {
      pending = int.tryParse(pendingMatch.group(1)!) ?? 0;
    }
    final sentMatch = RegExp(r'Sent History:\s+(\d+)').firstMatch(output);
    if (sentMatch != null) {
      sent = int.tryParse(sentMatch.group(1)!) ?? 0;
    }

    return LapdogStatus(
      isInstalled: isInstalled,
      isAwayArmed: isAway,
      pendingEvents: pending,
      sentHistory: sent,
      version: isInstalled ? 'v0.1.4' : '',
      lastChecked: timestamp,
      isVerified: true,
    );
  }

  Future<VitalsData?> fetchVitals(HostTarget host, {String? secret}) async {
    final bundle = await fetchTelemetryBundle(host, secret: secret);
    return bundle?.vitals;
  }

  Future<List<ProcessItem>> fetchProcesses(
    HostTarget host, {
    String? secret,
  }) async {
    const cmd =
        "ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -n 9 | tail -n +2";
    final res = await executeCommand(
      host: host,
      command: cmd,
      password: host.authMethod == AuthMethod.password ? secret : null,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
    );

    if (!res.isSuccess) return [];
    return _parseProcessesOutput(res.output);
  }

  Future<LapdogStatus> fetchLapdogStatus(
    HostTarget host, {
    String? secret,
  }) async {
    const cmd =
        "lapdog status 2>/dev/null || ~/.local/bin/lapdog status 2>/dev/null || echo 'LAPDOG_NOT_FOUND'";
    final res = await executeCommand(
      host: host,
      command: cmd,
      password: host.authMethod == AuthMethod.password ? secret : null,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
    );

    final now = DateTime.now();
    if (!res.isSuccess || res.output.isEmpty) {
      return LapdogStatus(
        isInstalled: false,
        lastChecked: now,
        isVerified: false,
      );
    }
    return _parseLapdogOutput(res.output, now);
  }

  /// Checks if the workstation graphical session is currently locked or unlocked.
  Future<bool?> checkWorkstationLockState(
    HostTarget host, {
    String? secret,
  }) async {
    final String cmd;
    if (host.os == HostOs.windows) {
      cmd = r'''
$locked = Get-Process -Name LogonUI -ErrorAction SilentlyContinue
if ($locked) { Write-Output "LOCKED" } else { Write-Output "UNLOCKED" }
''';
    } else if (host.os == HostOs.linux) {
      cmd = '''
if [ -n "\$DBUS_SESSION_BUS_ADDRESS" ] || [ -e "/run/user/\$(id -u)/bus" ]; then
  export DBUS_SESSION_BUS_ADDRESS="\${DBUS_SESSION_BUS_ADDRESS:-unix:path=/run/user/\$(id -u)/bus}"
fi
if gdbus call --session --dest org.gnome.ScreenSaver --object-path /org/gnome/ScreenSaver --method org.gnome.ScreenSaver.GetActive 2>/dev/null | grep -q "true"; then
  echo "LOCKED"
  exit 0
fi
for sid in \$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print \$1}'); do
  stype=\$(loginctl show-session "\$sid" -p Type --value 2>/dev/null)
  locked=\$(loginctl show-session "\$sid" -p LockedHint --value 2>/dev/null)
  if { [ "\$stype" = "wayland" ] || [ "\$stype" = "x11" ]; } && [ "\$locked" = "yes" ]; then
    echo "LOCKED"
    exit 0
  fi
done
echo "UNLOCKED"
''';
    } else {
      cmd =
          'ioreg -n Root -d1 -a 2>/dev/null | grep -q "<key>CGSSessionScreenIsLocked</key>" && echo "LOCKED" || echo "UNLOCKED"';
    }

    final res = await executeCommand(
      host: host,
      command: cmd,
      password: host.authMethod == AuthMethod.password ? secret : null,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
      executionTimeout: const Duration(seconds: 5),
    );

    if (!res.isSuccess) return null;
    final out = res.output.trim();
    if (out.contains('LOCKED')) return true;
    if (out.contains('UNLOCKED')) return false;
    return null;
  }

  /// Captures a screengrab from the host's primary graphical display.
  Future<Uint8List?> captureScreengrab(
    HostTarget host, {
    String? secret,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final String cmd;
    if (host.os == HostOs.windows) {
      cmd = r'''
$ErrorActionPreference = 'SilentlyContinue'
if (Get-Process -Name LogonUI -ErrorAction SilentlyContinue) {
  Write-Output "SCREENGRAB_FAILED"
  exit 0
}
$ts = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$img = "$env:TEMP\lapdeck_screen_$ts.jpg"
$tmpScript = "$env:TEMP\lapdeck_grab_$ts.ps1"
$cmdFile = "$env:TEMP\lapdeck_grab_$ts.cmd"
Remove-Item $img -Force -ErrorAction SilentlyContinue

$code = @'
$ErrorActionPreference = 'Stop'
try {
  try {
    $pinvoke = '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr c); [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();'
    Add-Type -MemberDefinition $pinvoke -Name DpiNative -Namespace LapDeck -ErrorAction SilentlyContinue
    if (![LapDeck.DpiNative]::SetProcessDpiAwarenessContext([IntPtr]-4)) {
      if (![LapDeck.DpiNative]::SetProcessDpiAwarenessContext([IntPtr]-3)) {
        [LapDeck.DpiNative]::SetProcessDPIAware() | Out-Null
      }
    }
  } catch {
    try {
      [LapDeck.DpiNative]::SetProcessDPIAware() | Out-Null
    } catch {}
  }

  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
  if ($bounds.Width -le 0 -or $bounds.Height -le 0) {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  }
  $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  try {
    $g.CopyFromScreen($bounds.Left, $bounds.Top, 0, 0, $bounds.Size)
    $bmp.Save('__IMG_PATH__', [System.Drawing.Imaging.ImageFormat]::Jpeg)
  } finally {
    $g.Dispose()
    $bmp.Dispose()
  }
} catch {
  exit 1
}
'@.Replace('__IMG_PATH__', $img)
Set-Content -Path $tmpScript -Value $code -Encoding Ascii
$cmdContent = "@powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$tmpScript`""
Set-Content -Path $cmdFile -Value $cmdContent -Encoding Ascii

# Attempt interactive dispatch via Task Scheduler (/IT) to bridge Session 0 isolation
$taskName = "LapDeckGrab_$ts"
$taskCreated = $false
try {
  & schtasks.exe /Create /TN $taskName /TR "`"$cmdFile`"" /SC ONCE /ST 00:00 /IT /F 2>$null | Out-Null
  if ($LASTEXITCODE -eq 0) {
    $taskCreated = $true
    & schtasks.exe /Run /TN $taskName 2>$null | Out-Null
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path $img) -and ($sw.ElapsedMilliseconds -lt 5000)) {
      Start-Sleep -Milliseconds 150
    }
  }
} catch {}
if ($taskCreated) {
  & schtasks.exe /Delete /TN $taskName /F 2>$null | Out-Null
}

# Fallback to direct execution if scheduled task did not produce the image
if (-not (Test-Path $img)) {
  try {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File $tmpScript 2>$null
  } catch {}
}

# Verify output: file must exist and have non-trivial size (>1000 bytes)
if (Test-Path $img) {
  $bytes = [System.IO.File]::ReadAllBytes($img)
  Remove-Item $img -Force -ErrorAction SilentlyContinue
  if ($bytes.Length -gt 1000) {
    [Convert]::ToBase64String($bytes)
  } else {
    Write-Output "SCREENGRAB_FAILED"
  }
} else {
  Write-Output "SCREENGRAB_FAILED"
}
Remove-Item $tmpScript -Force -ErrorAction SilentlyContinue
Remove-Item $cmdFile -Force -ErrorAction SilentlyContinue
''';
    } else if (host.os == HostOs.linux) {
      cmd = '''
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/\$(id -u)/bus"
TMP_OUT="/tmp/lapdeck_screengrab_\$\$.jpg"
DISPLAY=:0 ffmpeg -f x11grab -i :0.0 -frames:v 1 -update 1 -y "\$TMP_OUT" 2>/dev/null || (gnome-screenshot -f "\$TMP_OUT" 2>/dev/null)
if [ -f "\$TMP_OUT" ]; then
  base64 -w 0 "\$TMP_OUT" 2>/dev/null || base64 "\$TMP_OUT"
  rm -f "\$TMP_OUT"
else
  echo "SCREENGRAB_FAILED"
fi
''';
    } else {
      cmd = '''
TMP_OUT="/tmp/lapdeck_screengrab_\$\$.jpg"
screencapture -x -t jpg "\$TMP_OUT" 2>/dev/null
if [ -f "\$TMP_OUT" ]; then
  base64 -b 0 "\$TMP_OUT" 2>/dev/null || base64 "\$TMP_OUT"
  rm -f "\$TMP_OUT"
else
  echo "SCREENGRAB_FAILED"
fi
''';
    }

    final res = await executeCommand(
      host: host,
      command: cmd,
      password: host.authMethod == AuthMethod.password ? secret : null,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
      executionTimeout: timeout,
    );

    if (!res.isSuccess) return null;
    final out = res.output.trim();
    if (out.isEmpty || out.contains('SCREENGRAB_FAILED')) return null;

    try {
      final sanitized = out.replaceAll(RegExp(r'\s+'), '');
      return base64Decode(sanitized);
    } catch (e, st) {
      AppLogger.warning('SshService', 'Failed to decode screengrab base64: $e', e, st);
      return null;
    }
  }

  Future<SSHClient> _getClientForHost(
    HostTarget host, {
    String? secret,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final cached = _cmdClientPool[host.id];
    if (cached != null && !cached.isClosed) {
      return cached;
    }
    try {
      cached?.close();
    } catch (_) {}
    _cmdClientPool.remove(host.id);

    final password = host.authMethod == AuthMethod.password ? secret : null;
    final privateKeyPem = host.authMethod == AuthMethod.privateKey ? secret : null;

    SSHClient client;
    try {
      client = await _connectToIp(
        ip: host.tailscaleIp,
        port: host.port,
        username: host.username,
        password: password,
        privateKeyPem: privateKeyPem,
        timeout: timeout,
      );
    } catch (_) {
      if (host.directIp != null && host.directIp!.isNotEmpty) {
        client = await _connectToIp(
          ip: host.directIp!,
          port: host.port,
          username: host.username,
          password: password,
          privateKeyPem: privateKeyPem,
          timeout: timeout,
        );
      } else {
        rethrow;
      }
    }
    _cmdClientPool[host.id] = client;
    return client;
  }

  /// Lists items in [remotePath] using SFTP subsystem.
  Future<List<RemoteFileItem>> listRemoteFiles(
    HostTarget host,
    String remotePath, {
    String? secret,
  }) async {
    final client = await _getClientForHost(host, secret: secret);
    final sftp = await client.sftp();
    try {
      final names = await sftp.listdir(remotePath);
      final items = <RemoteFileItem>[];
      for (final n in names) {
        if (n.filename == '.' || n.filename == '..') continue;
        final isDir = n.attr.isDirectory;
        final subPath = remotePath == '/' || remotePath == '.'
            ? (remotePath == '.' ? n.filename : '/${n.filename}')
            : (remotePath.endsWith('/')
                ? '$remotePath${n.filename}'
                : '$remotePath/${n.filename}');
        DateTime? modTime;
        if (n.attr.modifyTime != null) {
          modTime = DateTime.fromMillisecondsSinceEpoch(
            n.attr.modifyTime! * 1000,
          );
        }
        items.add(RemoteFileItem(
          name: n.filename,
          path: subPath,
          isDirectory: isDir,
          size: n.attr.size ?? 0,
          modifyTime: modTime,
          permissions: n.attr.mode?.value,
        ));
      }
      items.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      return items;
    } finally {
      await sftp.close();
    }
  }

  /// Resolves the absolute path for [remotePath] via SFTP.
  Future<String> resolveRemoteAbsolutePath(
    HostTarget host,
    String remotePath, {
    String? secret,
  }) async {
    final client = await _getClientForHost(host, secret: secret);
    final sftp = await client.sftp();
    try {
      return await sftp.absolute(remotePath);
    } finally {
      await sftp.close();
    }
  }

  /// Downloads a remote file to [localDestinationPath] using SFTP stream.
  Future<void> downloadRemoteFile(
    HostTarget host,
    String remotePath,
    String localDestinationPath, {
    String? secret,
    void Function(int bytesReceived, int totalBytes)? onProgress,
  }) async {
    final client = await _getClientForHost(host, secret: secret);
    final sftp = await client.sftp();
    try {
      final stat = await sftp.stat(remotePath);
      final total = stat.size ?? 0;
      final localFile = File(localDestinationPath);
      if (await localFile.exists()) {
        await localFile.delete();
      }
      final sink = localFile.openWrite();
      try {
        await sftp.download(
          remotePath,
          sink,
          onProgress: (received) {
            onProgress?.call(received, total);
          },
        );
      } finally {
        await sink.flush();
        await sink.close();
      }
    } finally {
      await sftp.close();
    }
  }

  /// Uploads a local file from [localSourcePath] to [remoteDestinationPath] using SFTP stream.
  Future<void> uploadRemoteFile(
    HostTarget host,
    String localSourcePath,
    String remoteDestinationPath, {
    String? secret,
    void Function(int bytesSent, int totalBytes)? onProgress,
  }) async {
    final client = await _getClientForHost(host, secret: secret);
    final sftp = await client.sftp();
    try {
      final localFile = File(localSourcePath);
      final total = await localFile.length();
      final remoteFile = await sftp.open(
        remoteDestinationPath,
        mode: SftpFileOpenMode.write |
            SftpFileOpenMode.create |
            SftpFileOpenMode.truncate,
      );
      try {
        final stream = localFile.openRead().map((chunk) {
          return chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
        });
        final writer = remoteFile.write(
          stream,
          onProgress: (sent) {
            onProgress?.call(sent, total);
          },
        );
        await writer.done;
      } finally {
        await remoteFile.close();
      }
    } finally {
      await sftp.close();
    }
  }

  /// Creates a directory on the remote host via SFTP.
  Future<void> createRemoteDirectory(
    HostTarget host,
    String remotePath, {
    String? secret,
  }) async {
    final client = await _getClientForHost(host, secret: secret);
    final sftp = await client.sftp();
    try {
      await sftp.mkdir(remotePath);
    } finally {
      await sftp.close();
    }
  }

  /// Deletes a file or directory on the remote host via SFTP.
  Future<void> deleteRemoteItem(
    HostTarget host,
    String remotePath, {
    required bool isDirectory,
    String? secret,
  }) async {
    final client = await _getClientForHost(host, secret: secret);
    final sftp = await client.sftp();
    try {
      if (isDirectory) {
        await sftp.rmdir(remotePath);
      } else {
        await sftp.remove(remotePath);
      }
    } finally {
      await sftp.close();
    }
  }

  Future<SSHClient> _connectToIp({
    required String ip,
    required int port,
    required String username,
    String? password,
    String? privateKeyPem,
    required Duration timeout,
  }) async {
    AppLogger.debug('SshService', 'Connecting SSH socket to $ip:$port (user: $username)...');
    final socket = await SSHSocket.connect(ip, port, timeout: timeout);

    List<SSHKeyPair>? identities;
    if (privateKeyPem != null && privateKeyPem.trim().isNotEmpty) {
      try {
        identities = SSHKeyPair.fromPem(privateKeyPem);
      } catch (e, st) {
        AppLogger.warning('SshService', 'Failed parsing privateKeyPem: $e', e, st);
      }
    }

    AppLogger.info('SshService', 'SSH socket connected to $ip:$port, initializing client (hasIdentities: ${identities?.isNotEmpty == true})...');
    return SSHClient(
      socket,
      username: username,
      identities: identities,
      onPasswordRequest: password != null ? () => password : null,
    );
  }
}
