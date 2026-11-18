import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/host_target.dart';
import '../models/notification_settings.dart';

class StorageService {
  static const String _keyHosts = 'lapdeck_saved_hosts_v2';
  static const String _keyActiveHost = 'lapdeck_active_host_id';
  static const String _keyNotificationSettings = 'lapdeck_notification_settings_v1';
  static const String _keyInstalledCommitSha = 'lapdeck_installed_commit_sha';
  static const String _keyGithubToken = 'lapdeck_github_pat';
  static const String _secKeyPrefix = 'lapdeck_cred_';
  static const String _secConnectorTokenPrefix = 'lapdeck_connector_token_';
  static const String _keyGlobalConnectorToken = 'lapdeck_global_connector_token';

  /// Pre-shared secret matching telegram-antigravity-connector PEER_SECRET
  static const String defaultConnectorSecret = 'c9a6c340f06ed1536fc3ff6e822df3e7';

  /// Optional compile-time seeded SSH private key (`--dart-define=LAPDECK_DEFAULT_SSH_KEY=...`).
  /// Private keys are stored in Android Keystore via FlutterSecureStorage and never hardcoded in Git.
  static const String defaultPersonalKey = String.fromEnvironment(
    'LAPDECK_DEFAULT_SSH_KEY',
    defaultValue: '',
  );

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
    if (defaultPersonalKey.isNotEmpty) {
      final cred1 = await getHostCredential('host-surajworklaptop');
      if (cred1 == null || cred1.isEmpty) {
        await saveHostCredential('host-surajworklaptop', defaultPersonalKey);
      }
      final cred2 = await getHostCredential('host-mochirondesu');
      if (cred2 == null || cred2.isEmpty) {
        await saveHostCredential('host-mochirondesu', defaultPersonalKey);
      }
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

  /// Loads user notification toggle preferences.
  NotificationSettings loadNotificationSettings() {
    final raw = _prefs.getString(_keyNotificationSettings);
    if (raw == null || raw.isEmpty) {
      return const NotificationSettings();
    }
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return NotificationSettings.fromMap(map);
    } catch (_) {
      return const NotificationSettings();
    }
  }

  /// Persists user notification toggle preferences.
  Future<void> saveNotificationSettings(NotificationSettings settings) async {
    await _prefs.setString(
      _keyNotificationSettings,
      json.encode(settings.toMap()),
    );
  }

  /// Returns the currently recorded installed Git commit SHA (from compile-time or OTA record).
  String getInstalledCommitSha() {
    final compiled = AppVersionInfo.compiledCommitSha;
    if (compiled.isNotEmpty && compiled != 'local-HEAD') {
      return compiled;
    }
    final stored = _prefs.getString(_keyInstalledCommitSha);
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }
    return compiled;
  }

  /// Records the Git commit SHA of an OTA hotfix that was just downloaded and triggered for install.
  Future<void> setInstalledCommitSha(String sha) async {
    await _prefs.setString(_keyInstalledCommitSha, sha.trim());
  }

  /// Saves an optional GitHub Personal Access Token (PAT) in Android Keystore for private repo OTA checks.
  Future<void> saveGithubToken(String token) async {
    if (token.trim().isEmpty) {
      await _secureStorage.delete(key: _keyGithubToken);
    } else {
      await _secureStorage.write(key: _keyGithubToken, value: token.trim());
    }
  }

  /// Reads the optional GitHub PAT from Android Keystore.
  Future<String?> getGithubToken() async {
    return await _secureStorage.read(key: _keyGithubToken);
  }
}
