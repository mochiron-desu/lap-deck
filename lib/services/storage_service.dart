import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host_target.dart';

class StorageService {
  static const String _keyHosts = 'lapdeck_saved_hosts_v2';
  static const String _keyActiveHost = 'lapdeck_active_host_id';
  static const String _secKeyPrefix = 'lapdeck_cred_';

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
      return list.map((e) => HostTarget.fromMap(e as Map<String, dynamic>)).toList();
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

  /// Deletes credential on host removal.
  Future<void> deleteHostCredential(String hostId) async {
    await _secureStorage.delete(key: '$_secKeyPrefix$hostId');
  }
}
