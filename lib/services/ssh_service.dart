import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/host_target.dart';
import '../models/vitals_data.dart';

class SshExecutionResult {
  final int? exitCode;
  final String output;
  final String error;
  final Duration duration;
  final String connectedEndpoint;

  const SshExecutionResult({
    this.exitCode,
    required this.output,
    required this.error,
    required this.duration,
    required this.connectedEndpoint,
  });

  bool get isSuccess => exitCode == 0;
}

class HostReachability {
  final bool isOnline;
  final int? latencyMs;
  final bool isDirect;

  const HostReachability({
    required this.isOnline,
    this.latencyMs,
    this.isDirect = false,
  });
}

class TelemetryBundle {
  final VitalsData vitals;
  final List<ProcessItem> processes;
  final LapdogStatus lapdog;

  const TelemetryBundle({
    required this.vitals,
    required this.processes,
    required this.lapdog,
  });
}

class SshService {
  SSHClient? _activeClient;
  SSHSession? _activeShellSession;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;

  // Reusable command execution connection pool
  SSHClient? _cachedCmdClient;
  String? _cachedCmdHostId;

  bool get isConnected => _activeClient != null && !(_activeClient?.isClosed ?? true);

  /// Executes a command with auto-failover: tries Tailscale IP first;
  /// falls back to direct LAN IP if Tailscale is unreachable.
  /// Reuses cached SSH connection when available to eliminate redundant handshakes.
  Future<SshExecutionResult> executeCommand({
    required HostTarget host,
    required String command,
    String? password,
    String? privateKeyPem,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    final stopwatch = Stopwatch()..start();
    String connectedIp = host.tailscaleIp;

    try {
      SSHClient client;

      // Reuse active client if connected to the same host
      if (_cachedCmdClient != null &&
          !(_cachedCmdClient!.isClosed) &&
          _cachedCmdHostId == host.id) {
        client = _cachedCmdClient!;
      } else {
        // Discard any stale client
        try {
          _cachedCmdClient?.close();
        } catch (_) {}
        _cachedCmdClient = null;

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
        _cachedCmdClient = client;
        _cachedCmdHostId = host.id;
      }

      final session = await client.execute(command).timeout(const Duration(seconds: 8));
      final stdoutBuffer = StringBuffer();
      final stderrBuffer = StringBuffer();

      final outSub = session.stdout.listen((bytes) {
        stdoutBuffer.write(utf8.decode(bytes, allowMalformed: true));
      });
      final errSub = session.stderr.listen((bytes) {
        stderrBuffer.write(utf8.decode(bytes, allowMalformed: true));
      });

      await session.done;
      await outSub.cancel();
      await errSub.cancel();

      stopwatch.stop();

      return SshExecutionResult(
        exitCode: session.exitCode,
        output: stdoutBuffer.toString().trim(),
        error: stderrBuffer.toString().trim(),
        duration: stopwatch.elapsed,
        connectedEndpoint: connectedIp,
      );
    } catch (e) {
      // Discard cached client on failure
      try {
        _cachedCmdClient?.close();
      } catch (_) {}
      _cachedCmdClient = null;
      _cachedCmdHostId = null;

      stopwatch.stop();
      return SshExecutionResult(
        exitCode: -1,
        output: '',
        error: e.toString(),
        duration: stopwatch.elapsed,
        connectedEndpoint: connectedIp,
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
      await disconnect();

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
      await disconnect();
      return false;
    }
  }

  /// Send user keystroke or string into the live shell session.
  void sendShellInput(String input) {
    if (_activeShellSession != null && isConnected) {
      _activeShellSession!.write(Uint8List.fromList(utf8.encode(input)));
    }
  }

  /// Close and cleanup existing SSH sessions and connection pools.
  Future<void> disconnect() async {
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

    try {
      _cachedCmdClient?.close();
    } catch (_) {}
    _cachedCmdClient = null;
    _cachedCmdHostId = null;
  }

  /// Quickly tests whether host SSH port (or direct LAN fallback) is reachable.
  /// Measures round-trip TCP connection time in milliseconds.
  Future<HostReachability> checkReachability(
    HostTarget host, {
    Duration timeout = const Duration(milliseconds: 1500),
  }) async {
    final sw = Stopwatch()..start();

    // 1. Try Tailscale IP
    try {
      final socket = await Socket.connect(host.tailscaleIp, host.port, timeout: timeout);
      sw.stop();
      socket.destroy();
      return HostReachability(
        isOnline: true,
        latencyMs: sw.elapsedMilliseconds,
        isDirect: false,
      );
    } catch (_) {
      // 2. Try direct LAN IP if configured
      if (host.directIp != null && host.directIp!.isNotEmpty) {
        try {
          final lanSw = Stopwatch()..start();
          final socket = await Socket.connect(host.directIp!, host.port, timeout: timeout);
          lanSw.stop();
          socket.destroy();
          return HostReachability(
            isOnline: true,
            latencyMs: lanSw.elapsedMilliseconds,
            isDirect: true,
          );
        } catch (_) {}
      }
    }

    sw.stop();
    return const HostReachability(
      isOnline: false,
      latencyMs: null,
      isDirect: false,
    );
  }

  /// Single-command batched telemetry fetch for Vitals, Processes, and Lapdog.
  /// Eliminates multiple sequential SSH handshakes and completely prevents UI stutter.
  Future<TelemetryBundle?> fetchTelemetryBundle(HostTarget host, {String? secret}) async {
    const script = '''
echo "===LAPDECK_VITALS==="
echo "CPU_USAGE:\$(top -bn1 2>/dev/null | grep 'Cpu(s)' | awk '{print \$2 + \$4}' || echo '0')"
echo "CPU_LOAD:\$(uptime | awk -F'load average:' '{ print \$2 }' | cut -d, -f1 | tr -d ' ')"
echo "MEM_INFO:\$(free -m | awk '/Mem:/ { printf "%.1f/%.1f GB (%.0f%%)", \$3/1024, \$2/1024, (\$3/\$2)*100 }')"
echo "DISK_INFO:\$(df -h / | awk 'NR==2 { printf "%s/%s (%s)", \$3, \$2, \$5 }')"
echo "UPTIME:\$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print \$2}' | cut -d, -f1)"
echo "===LAPDECK_PROCESSES==="
ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -n 9 | tail -n +2
echo "===LAPDECK_LAPDOG==="
lapdog status 2>/dev/null || ~/.local/bin/lapdog status 2>/dev/null || true
''';

    final res = await executeCommand(
      host: host,
      command: script,
      password: host.authMethod == AuthMethod.password ? secret : null,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
    );

    if (!res.isSuccess || res.output.isEmpty) return null;

    final output = res.output;
    final vitalsPart = _extractSection(output, '===LAPDECK_VITALS===', '===LAPDECK_PROCESSES===');
    final procsPart = _extractSection(output, '===LAPDECK_PROCESSES===', '===LAPDECK_LAPDOG===');
    final lapdogPart = _extractSection(output, '===LAPDECK_LAPDOG===', null);

    return TelemetryBundle(
      vitals: _parseVitalsOutput(vitalsPart),
      processes: _parseProcessesOutput(procsPart),
      lapdog: _parseLapdogOutput(lapdogPart),
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

  VitalsData _parseVitalsOutput(String output) {
    double cpuPercent = 0.0;
    String loadAvg = '0.00';
    double ramPercent = 0.0;
    String ramUsage = '0.0 / 0.0 GB';
    double diskPercent = 0.0;
    String diskUsage = '0 / 0 GB';
    String uptime = 'Unknown';

    final lines = output.split('\n');
    for (final line in lines) {
      if (line.startsWith('CPU_USAGE:')) {
        final val = double.tryParse(line.replaceFirst('CPU_USAGE:', '').trim()) ?? 0.0;
        cpuPercent = (val / 100.0).clamp(0.0, 1.0);
      } else if (line.startsWith('CPU_LOAD:')) {
        loadAvg = line.replaceFirst('CPU_LOAD:', '').trim();
      } else if (line.startsWith('MEM_INFO:')) {
        ramUsage = line.replaceFirst('MEM_INFO:', '').trim();
        final match = RegExp(r'\((\d+)%\)').firstMatch(ramUsage);
        if (match != null) {
          ramPercent = (double.tryParse(match.group(1)!) ?? 0.0) / 100.0;
        }
      } else if (line.startsWith('DISK_INFO:')) {
        diskUsage = line.replaceFirst('DISK_INFO:', '').trim();
        final match = RegExp(r'\((\d+)%\)').firstMatch(diskUsage);
        if (match != null) {
          diskPercent = (double.tryParse(match.group(1)!) ?? 0.0) / 100.0;
        }
      } else if (line.startsWith('UPTIME:')) {
        uptime = line.replaceFirst('UPTIME:', '').replaceFirst('up ', '').trim();
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
      timestamp: DateTime.now(),
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

  LapdogStatus _parseLapdogOutput(String output) {
    if (output.isEmpty) {
      return const LapdogStatus(isInstalled: false);
    }
    final isAway = output.contains('Away Mode:      ARMED');
    final isInstalled = output.contains('lap-dog Status Dashboard');

    int pending = 0;
    int sent = 0;
    final pendingMatch = RegExp(r'Pending Queue:\s+(\d+)').firstMatch(output);
    if (pendingMatch != null) pending = int.tryParse(pendingMatch.group(1)!) ?? 0;
    final sentMatch = RegExp(r'Sent History:\s+(\d+)').firstMatch(output);
    if (sentMatch != null) sent = int.tryParse(sentMatch.group(1)!) ?? 0;

    return LapdogStatus(
      isInstalled: isInstalled,
      isAwayArmed: isAway,
      pendingEvents: pending,
      sentHistory: sent,
      version: 'v0.1.4',
    );
  }

  /// Fetches real-time CPU, RAM, Disk and Uptime metrics formatted cleanly for cards.
  Future<VitalsData?> fetchVitals(HostTarget host, {String? secret}) async {
    const script = '''
echo "CPU_USAGE:\$(top -bn1 2>/dev/null | grep 'Cpu(s)' | awk '{print \$2 + \$4}' || echo '0')"
echo "CPU_LOAD:\$(uptime | awk -F'load average:' '{ print \$2 }' | cut -d, -f1 | tr -d ' ')"
echo "MEM_INFO:\$(free -m | awk '/Mem:/ { printf "%.1f/%.1f GB (%.0f%%)", \$3/1024, \$2/1024, (\$3/\$2)*100 }')"
echo "DISK_INFO:\$(df -h / | awk 'NR==2 { printf "%s/%s (%s)", \$3, \$2, \$5 }')"
echo "UPTIME:\$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print \$2}' | cut -d, -f1)"
''';

    final res = await executeCommand(
      host: host,
      command: script,
      password: host.authMethod == AuthMethod.password ? secret : null,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
    );

    if (!res.isSuccess || res.output.isEmpty) return null;
    return _parseVitalsOutput(res.output);
  }

  /// Fetches list of top running apps/processes for the active task manager card.
  Future<List<ProcessItem>> fetchProcesses(HostTarget host, {String? secret}) async {
    const cmd = "ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu 2>/dev/null | head -n 9 | tail -n +2";
    final res = await executeCommand(
      host: host,
      command: cmd,
      password: host.authMethod == AuthMethod.password ? secret : null,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
    );

    if (!res.isSuccess) return [];
    return _parseProcessesOutput(res.output);
  }

  /// Fetches current Lapdog security daemon status.
  Future<LapdogStatus> fetchLapdogStatus(HostTarget host, {String? secret}) async {
    const cmd = "lapdog status 2>/dev/null || ~/.local/bin/lapdog status 2>/dev/null";
    final res = await executeCommand(
      host: host,
      command: cmd,
      password: host.authMethod == AuthMethod.password ? secret : null,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
    );

    if (!res.isSuccess || res.output.isEmpty) {
      return const LapdogStatus(isInstalled: false);
    }
    return _parseLapdogOutput(res.output);
  }

  Future<SSHClient> _connectToIp({
    required String ip,
    required int port,
    required String username,
    String? password,
    String? privateKeyPem,
    required Duration timeout,
  }) async {
    final socket = await SSHSocket.connect(ip, port, timeout: timeout);

    List<SSHKeyPair>? identities;
    if (privateKeyPem != null && privateKeyPem.trim().isNotEmpty) {
      try {
        identities = SSHKeyPair.fromPem(privateKeyPem);
      } catch (_) {}
    }

    return SSHClient(
      socket,
      username: username,
      identities: identities,
      onPasswordRequest: password != null ? () => password : null,
    );
  }
}
