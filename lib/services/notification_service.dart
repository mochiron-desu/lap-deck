import 'package:flutter/services.dart';
import '../models/host_target.dart';
import '../models/notification_settings.dart';
import '../models/vitals_data.dart';
import 'app_logger.dart';
import 'storage_service.dart';

/// Native Android notification bridge and state-transition deduplication service.
/// Communicates with MainActivity.kt over 'com.mochirondesu.lap_deck/platform'.
class NotificationService {
  static const MethodChannel _channel = MethodChannel(
    'com.mochirondesu.lap_deck/platform',
  );

  static const String channelDevices = 'lapdeck_devices';
  static const String channelErrors = 'lapdeck_errors';
  static const String channelSecurity = 'lapdeck_security';
  static const String channelAi = 'lapdeck_ai';
  static const String channelUpdates = 'lapdeck_updates';

  final StorageService? _storage;

  // Deduplication tracking maps (keyed by host.id)
  final Map<String, PeerStatus> _lastKnownPeerStatus = {};
  final Map<String, ServiceStatus> _lastKnownSshStatus = {};
  final Map<String, int> _lastKnownPendingEvents = {};
  final Map<String, bool> _lastKnownAwayArmed = {};
  String? _lastNotifiedUpdateSha;

  NotificationService([this._storage]);

  NotificationSettings get settings =>
      _storage?.loadNotificationSettings() ?? const NotificationSettings();

  /// Checks whether Android notification permissions are currently granted.
  Future<bool> areNotificationsGranted() async {
    try {
      final res = await _channel.invokeMethod<bool>('areNotificationsGranted');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Requests Android 13+ POST_NOTIFICATIONS runtime permission.
  Future<bool> requestPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>(
        'requestNotificationPermission',
      );
      return res ?? false;
    } catch (e) {
      AppLogger.warning(
        'NotificationService',
        'Permission request failed: $e',
      );
      return false;
    }
  }

  /// Dispatches a raw native Android notification if master toggle is enabled.
  Future<bool> showRawNotification({
    required int id,
    required String channelId,
    required String title,
    required String body,
    bool bypassMasterCheck = false,
  }) async {
    if (!bypassMasterCheck && !settings.masterEnabled) {
      return false;
    }
    try {
      final res = await _channel.invokeMethod<bool>('showNotification', {
        'id': id,
        'channelId': channelId,
        'title': title,
        'body': body,
      });
      return res ?? false;
    } catch (e) {
      AppLogger.debug(
        'NotificationService',
        'Native notification skipped or unsupported on platform: $e',
      );
      return false;
    }
  }

  /// Sends a one-tap test notification from SettingsTab.
  Future<bool> sendTestNotification() async {
    final granted = await areNotificationsGranted();
    if (!granted) {
      final newlyGranted = await requestPermission();
      if (!newlyGranted) return false;
    }
    return showRawNotification(
      id: 9900,
      channelId: channelDevices,
      title: 'LapDeck Command Surface',
      body:
          'Native Android notifications are active for peer telemetry, security events, AI turns, and Git hotfixes.',
      bypassMasterCheck: true,
    );
  }

  /// Evaluates a freshly probed host list and emits notifications strictly on real state transitions.
  /// Pure comparison logic is exposed via [evaluateHostTransition] for unit testability.
  Future<void> processHostUpdates(
    List<HostTarget> updatedHosts, {
    Map<String, LapdogStatus> lapdogByHost = const {},
  }) async {
    final cfg = settings;
    if (!cfg.masterEnabled) return;

    for (final host in updatedHosts) {
      final transition = evaluateHostTransition(
        host,
        lapdog: lapdogByHost[host.id],
        cfg: cfg,
      );
      if (transition != null) {
        await showRawNotification(
          id: transition.id,
          channelId: transition.channelId,
          title: transition.title,
          body: transition.body,
        );
      }
    }
  }

  /// Evaluates state changes for a single host and updates internal deduplication caches.
  /// Returns a notification payload only when a genuine transition occurs.
  ({int id, String channelId, String title, String body})?
      evaluateHostTransition(
    HostTarget host, {
    LapdogStatus? lapdog,
    NotificationSettings? cfg,
  }) {
    final activeCfg = cfg ?? settings;
    if (!activeCfg.masterEnabled) return null;

    // Ignore transient unknown/connecting states
    if (host.peerStatus == PeerStatus.unknown ||
        host.peerStatus == PeerStatus.connecting) {
      return null;
    }

    final prevPeer = _lastKnownPeerStatus[host.id];
    final prevSsh = _lastKnownSshStatus[host.id];

    _lastKnownPeerStatus[host.id] = host.peerStatus;
    if (host.sshStatus != ServiceStatus.unknown &&
        host.sshStatus != ServiceStatus.connecting) {
      _lastKnownSshStatus[host.id] = host.sshStatus;
    }

    ({int id, String channelId, String title, String body})? alert;

    // 1. Peer Online <-> Offline / Unreachable transitions
    if (prevPeer != null && prevPeer != host.peerStatus) {
      if (host.peerStatus == PeerStatus.online &&
          activeCfg.peerStatusTransitions) {
        final rtt = host.pingMs != null ? ' (${host.pingMs} ms)' : '';
        alert = (
          id: host.id.hashCode & 0x7FFFFFFF,
          channelId: channelDevices,
          title: '${host.name} is Online',
          body:
              '${host.osDisplayName} workstation reachable over ${host.isDirect ? "Direct LAN" : "Tailscale Mesh"}$rtt.',
        );
      } else if ((host.peerStatus == PeerStatus.unreachable ||
              host.peerStatus == PeerStatus.offline) &&
          prevPeer == PeerStatus.online &&
          activeCfg.peerStatusTransitions) {
        alert = (
          id: host.id.hashCode & 0x7FFFFFFF,
          channelId: channelDevices,
          title: '${host.name} went Offline',
          body: host.lastError ??
              'Workstation ${host.name} (${host.tailscaleIp}) is no longer responding to network probes.',
        );
      }
    }

    // 2. Subsystem Error: Peer is Online, but SSH transitioned to Unavailable
    if (alert == null &&
        host.peerStatus == PeerStatus.online &&
        host.sshStatus == ServiceStatus.unavailable &&
        prevSsh != ServiceStatus.unavailable &&
        activeCfg.subsystemAndConnectorErrors) {
      alert = (
        id: (host.id.hashCode ^ 0x1111) & 0x7FFFFFFF,
        channelId: channelErrors,
        title: 'SSH Unavailable on ${host.name}',
        body: host.lastError ??
            'Peer ${host.name} is reachable on the network, but SSH daemon port ${host.port} or authentication failed.',
      );
    }

    // 3. Lapdog security events or Away mode transitions
    if (lapdog != null && lapdog.isInstalled) {
      final prevPending = _lastKnownPendingEvents[host.id] ?? 0;
      final prevArmed = _lastKnownAwayArmed[host.id];
      _lastKnownPendingEvents[host.id] = lapdog.pendingEvents;
      _lastKnownAwayArmed[host.id] = lapdog.isAwayArmed;

      if (alert == null &&
          activeCfg.lapdogSecurityEvents &&
          lapdog.pendingEvents > prevPending) {
        final diff = lapdog.pendingEvents - prevPending;
        alert = (
          id: (host.id.hashCode ^ 0x2222) & 0x7FFFFFFF,
          channelId: channelSecurity,
          title: 'Lapdog Security Alert · ${host.name}',
          body:
              '$diff new security event(s) detected on ${host.name} (${lapdog.pendingEvents} pending in queue).',
        );
      } else if (alert == null &&
          activeCfg.lapdogSecurityEvents &&
          prevArmed != null &&
          prevArmed != lapdog.isAwayArmed) {
        alert = (
          id: (host.id.hashCode ^ 0x2223) & 0x7FFFFFFF,
          channelId: channelSecurity,
          title:
              'Lapdog ${lapdog.isAwayArmed ? "Away Armed" : "Disarmed"} · ${host.name}',
          body: lapdog.isAwayArmed
              ? 'Away Mode is now ARMED on ${host.name}.'
              : 'Away Mode returned to Home Mode on ${host.name}.',
        );
      }
    }

    return alert;
  }

  /// Emits a notification when an operation fails or times out.
  Future<void> notifyOperationError({
    required String hostName,
    required String operationName,
    required String details,
  }) async {
    final cfg = settings;
    if (!cfg.masterEnabled || !cfg.subsystemAndConnectorErrors) return;
    await showRawNotification(
      id: (hostName.hashCode ^ operationName.hashCode) & 0x7FFFFFFF,
      channelId: channelErrors,
      title: '$operationName Failed · $hostName',
      body: details,
    );
  }

  /// Emits a notification when an Antigravity AI turn finishes or errors out.
  Future<void> notifyAiTurnFinished({
    required String hostName,
    required bool isSuccess,
    required String summary,
  }) async {
    final cfg = settings;
    if (!cfg.masterEnabled || !cfg.aiTurnCompletion) return;
    final cleanSummary =
        summary.length > 140 ? '${summary.substring(0, 137)}...' : summary;
    await showRawNotification(
      id: (hostName.hashCode ^ 0x4444) & 0x7FFFFFFF,
      channelId: channelAi,
      title: isSuccess
          ? 'AI Turn Completed · $hostName'
          : 'AI Turn Failed · $hostName',
      body: cleanSummary,
    );
  }

  /// Emits a notification once per new remote Git commit when an OTA hotfix is available.
  Future<void> notifyOtaUpdateAvailable(OtaUpdateInfo info) async {
    final cfg = settings;
    if (!cfg.masterEnabled || !cfg.otaUpdateAvailable) return;
    if (!info.hasNewerCommit || info.latestCommitSha == null) return;
    if (_lastNotifiedUpdateSha == info.latestCommitSha) return;

    _lastNotifiedUpdateSha = info.latestCommitSha;
    final msg = info.latestCommitMessage?.split('\n').first ?? 'New Git commit';
    await showRawNotification(
      id: 8801,
      channelId: channelUpdates,
      title: 'LapDeck Git Hotfix Available (${info.shortLatestSha})',
      body: '$msg — Tap to pull and install the update in-place.',
    );
  }
}
