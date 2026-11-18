import 'package:flutter/foundation.dart';
import '../models/host_target.dart';
import 'ssh_service.dart';

class TerminalSessionController extends ChangeNotifier {
  final SshService _sshService;

  TerminalSessionController(this._sshService);

  bool _isConnecting = false;
  bool _isConnected = false;
  HostTarget? _connectedHost;
  String _buffer = '';
  double _fontSize = 12.0;
  final List<String> _history = [];

  bool get isConnecting => _isConnecting;
  bool get isConnected => _isConnected;
  HostTarget? get connectedHost => _connectedHost;
  String get buffer => _buffer;
  double get fontSize => _fontSize;
  List<String> get history => List.unmodifiable(_history);

  /// Returns true if an active PTY session is already established for [host].
  bool hasActiveSessionFor(HostTarget? host) {
    if (host == null) return false;
    return _isConnected && _connectedHost?.id == host.id;
  }

  void setFontSize(double size) {
    _fontSize = size.clamp(9.0, 18.0);
    notifyListeners();
  }

  void appendOutput(String text) {
    _buffer += text;
    if (_buffer.length > 40000) {
      _buffer = _buffer.substring(_buffer.length - 30000);
    }
    notifyListeners();
  }

  void clearBuffer() {
    _buffer = '';
    notifyListeners();
  }

  Future<bool> connect(
    HostTarget host, {
    String? secret,
    bool forceReconnect = false,
  }) async {
    if (_isConnecting) return false;

    // Reuse active PTY session if already connected to the same target host
    if (!forceReconnect && hasActiveSessionFor(host)) {
      _connectedHost = host;
      notifyListeners();
      return true;
    }

    _isConnecting = true;
    _connectedHost = host;
    appendOutput(
      '\r\n[CONNECTING] Connecting to ${host.name} (${host.username}@${host.tailscaleIp}:${host.port})...\r\n',
    );
    notifyListeners();

    final success = await _sshService.startInteractiveShell(
      host: host,
      password: host.authMethod == AuthMethod.password ? secret : null,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
      onOutput: (chunk) {
        appendOutput(chunk);
      },
      onDisconnected: () {
        _isConnected = false;
        _isConnecting = false;
        appendOutput(
          '\r\n[DISCONNECTED] SSH session closed on ${_connectedHost?.name ?? "remote host"}.\r\n',
        );
        notifyListeners();
      },
    );

    _isConnecting = false;
    _isConnected = success;

    if (success) {
      appendOutput(
        '[CONNECTED] PTY allocated on ${host.name} (xterm-256color) • Ready.\r\n',
      );
    } else {
      appendOutput(
        '[FAILED] Unable to establish SSH session to ${host.name} (${host.tailscaleIp}). Verify SSH service and network reachability.\r\n',
      );
    }

    notifyListeners();
    return success;
  }

  void sendInput(String input) {
    if (_isConnected) {
      _sshService.sendShellInput(input.endsWith('\n') ? input : '$input\n');
      if (input.trim().isNotEmpty) {
        _history.add(input.trim());
      }
    }
  }

  void sendRawKeystroke(String code) {
    if (_isConnected) {
      _sshService.sendShellInput(code);
    }
  }

  Future<void> disconnect() async {
    final hostName = _connectedHost?.name ?? 'host';
    await _sshService.disconnectShell();
    _isConnected = false;
    _isConnecting = false;
    appendOutput('\r\n[DISCONNECTED] Session on $hostName terminated by user.\r\n');
    notifyListeners();
  }
}
