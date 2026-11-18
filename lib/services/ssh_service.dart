import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import '../models/host_target.dart';

class SshExecutionResult {
  final int? exitCode;
  final String output;
  final String error;
  final Duration duration;

  const SshExecutionResult({
    this.exitCode,
    required this.output,
    required this.error,
    required this.duration,
  });

  bool get isSuccess => exitCode == 0;
}

class SshService {
  SSHClient? _activeClient;
  SSHSession? _activeShellSession;
  StreamSubscription? _stdoutSub;
  StreamSubscription? _stderrSub;
  HostTarget? _connectedHost;

  bool get isConnected => _activeClient != null && !(_activeClient?.isClosed ?? true);
  HostTarget? get connectedHost => _connectedHost;

  /// Executes a single command on the target host and returns the aggregated output.
  Future<SshExecutionResult> executeCommand({
    required HostTarget host,
    required String command,
    String? password,
    String? privateKeyPem,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final stopwatch = Stopwatch()..start();
    SSHClient? tempClient;

    try {
      tempClient = await _createClient(
        host: host,
        password: password,
        privateKeyPem: privateKeyPem,
        timeout: timeout,
      );

      final session = await tempClient.execute(command).timeout(timeout);
      
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
        output: stdoutBuffer.toString(),
        error: stderrBuffer.toString(),
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      return SshExecutionResult(
        exitCode: -1,
        output: '',
        error: 'SSH Execution Failed: ${e.toString()}',
        duration: stopwatch.elapsed,
      );
    } finally {
      tempClient?.close();
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

      final client = await _createClient(
        host: host,
        password: password,
        privateKeyPem: privateKeyPem,
        timeout: const Duration(seconds: 10),
      );

      _activeClient = client;
      _connectedHost = host;

      final session = await client.shell(
        pty: SSHPtyConfig(
          width: width,
          height: height,
          type: 'xterm-256color',
        ),
      );

      _activeShellSession = session;

      _stdoutSub = session.stdout.listen(
        (data) {
          final text = utf8.decode(data, allowMalformed: true);
          onOutput(text);
        },
        onError: (err) {
          onOutput('\r\n[STREAM ERROR]: $err\r\n');
        },
        onDone: () {
          onOutput('\r\n[SESSION TERMINATED BY HOST]\r\n');
          disconnect();
          onDisconnected();
        },
      );

      _stderrSub = session.stderr.listen((data) {
        final text = utf8.decode(data, allowMalformed: true);
        onOutput(text);
      });

      return true;
    } catch (e) {
      onOutput('\r\n[CONNECTION FAILED]: ${e.toString()}\r\n');
      disconnect();
      return false;
    }
  }

  /// Send user keystroke or string into the live shell session.
  void sendShellInput(String input) {
    if (_activeShellSession != null && isConnected) {
      _activeShellSession!.write(Uint8List.fromList(utf8.encode(input)));
    }
  }

  /// Close and cleanup existing SSH sessions.
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
    _connectedHost = null;
  }

  /// Establish raw SSHSocket and authenticate.
  Future<SSHClient> _createClient({
    required HostTarget host,
    String? password,
    String? privateKeyPem,
    required Duration timeout,
  }) async {
    final socket = await SSHSocket.connect(
      host.tailscaleIp,
      host.port,
      timeout: timeout,
    );

    List<SSHKeyPair>? identities;
    if (privateKeyPem != null && privateKeyPem.trim().isNotEmpty) {
      try {
        identities = SSHKeyPair.fromPem(privateKeyPem);
      } catch (e) {
        // Fallback or rethrow if key format invalid
      }
    }

    return SSHClient(
      socket,
      username: host.username,
      identities: identities,
      onPasswordRequest: password != null ? () => password : null,
      onAuthenticated: () {},
    );
  }
}
