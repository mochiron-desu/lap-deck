import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host_target.dart';

class StorageService {
  static const String _keyHosts = 'lapdeck_saved_hosts_v2';
  static const String _keyActiveHost = 'lapdeck_active_host_id';
  static const String _secKeyPrefix = 'lapdeck_cred_';
  static const String _secConnectorTokenPrefix = 'lapdeck_connector_token_';
  static const String _keyGlobalConnectorToken = 'lapdeck_global_connector_token';

  /// Pre-shared secret matching telegram-antigravity-connector PEER_SECRET
  static const String defaultConnectorSecret = 'c9a6c340f06ed1536fc3ff6e822df3e7';

  static const String defaultPersonalKey = String.fromEnvironment('LAPDECK_DEFAULT_SSH_KEY', defaultValue: '');

  final SharedPreferences _prefs;
  final FlutterSecureStorage _secureStorage;

  StorageService(this._prefs, this._secureStorage);

  static Future<StorageService> init() async {
    final prefs = await SharedPreferences.getInstance();
    const secureStorage = FlutterSecureStorage(
      aOptions: AndroidOptions(),
    );
    final service = StorageService(prefs, secureStorage);
    await service._seedDefaultCredentials();
    return service;
  }

  Future<void> _seedDefaultCredentials() async {
    final cred1 = await getHostCredential('host-surajworklaptop');
    if (cred1 == null || cred1.isEmpty) {
      await saveHostCredential('host-surajworklaptop', defaultPersonalKey);
    }
    final cred2 = await getHostCredential('host-mochirondesu');
    if (cred2 == null || cred2.isEmpty) {
      await saveHostCredential('host-mochirondesu', defaultPersonalKey);
    }
    final savedToken = await _secureStorage.read(key: _keyGlobalConnectorToken);
    if (savedToken == null || savedToken.isEmpty) {
      await saveConnectorToken(defaultConnectorSecret);
    }
  }

  /// Loads all saved hosts. If none are stored, seeds default laptops.
  List<HostTarget> loadHosts() {
    final raw = _prefs.getString(_keyHosts);
    if (raw == null || raw.isEmpty) {
      final defaults = HostTarget.defaultHosts;
      saveHosts(defaults);
      return defaults;
    }

    try {
      final List<dynamic> list = json.decode(raw);
      final hosts = list
          .map((e) => HostTarget.fromMap(e as Map<String, dynamic>))
          .map((h) {
            // Auto-migrate legacy default Windows username if present
            if (h.id == 'host-mochirondesu' && h.username == 'suraj') {
              return h.copyWith(username: 'qwerk');
            }
            return h;
          })
          .toList();
      return hosts;
    } catch (_) {
      return HostTarget.defaultHosts;
    }
  }

  /// Persists the list of hosts.
  Future<void> saveHosts(List<HostTarget> hosts) async {
    final raw = json.encode(hosts.map((h) => h.toMap()).toList());
    await _prefs.setString(_keyHosts, raw);
  }

  /// Get active selected host ID.
  String? getActiveHostId() {
    return _prefs.getString(_keyActiveHost);
  }

  /// Set active selected host ID.
  Future<void> setActiveHostId(String id) async {
    await _prefs.setString(_keyActiveHost, id);
  }

  /// Securely saves password or private key for a given host.
  Future<void> saveHostCredential(String hostId, String secret) async {
    await _secureStorage.write(key: '$_secKeyPrefix$hostId', value: secret);
  }

  /// Retrieves securely saved credential.
  Future<String?> getHostCredential(String hostId) async {
    final cred = await _secureStorage.read(key: '$_secKeyPrefix$hostId');
    if (cred != null && cred.isNotEmpty) return cred;
    // Default fallback to personal ed25519 key if none stored
    return defaultPersonalKey;
  }

  /// Securely saves Telegram Antigravity Connector token (per host or globally).
  Future<void> saveConnectorToken(String token, [String? hostId]) async {
    if (hostId != null && hostId.isNotEmpty) {
      await _secureStorage.write(key: '$_secConnectorTokenPrefix$hostId', value: token);
    } else {
      await _secureStorage.write(key: _keyGlobalConnectorToken, value: token);
    }
  }

  /// Retrieves securely saved connector token, falling back to global token or default secret.
  Future<String> getConnectorToken([String? hostId]) async {
    if (hostId != null && hostId.isNotEmpty) {
      final hostToken = await _secureStorage.read(key: '$_secConnectorTokenPrefix$hostId');
      if (hostToken != null && hostToken.isNotEmpty) return hostToken;
    }
    final globalToken = await _secureStorage.read(key: _keyGlobalConnectorToken);
    if (globalToken != null && globalToken.isNotEmpty) return globalToken;
    return defaultConnectorSecret;
  }

  /// Deletes credential on host removal.
  Future<void> deleteHostCredential(String hostId) async {
    await _secureStorage.delete(key: '$_secKeyPrefix$hostId');
    await _secureStorage.delete(key: '$_secConnectorTokenPrefix$hostId');
  }
}
