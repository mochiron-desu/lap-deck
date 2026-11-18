import 'package:flutter_test/flutter_test.dart';
import 'package:lap_deck/models/host_target.dart';
import 'package:lap_deck/models/command_action.dart';
import 'package:lap_deck/models/notification_settings.dart';
import 'package:lap_deck/models/remote_file_item.dart';
import 'package:lap_deck/models/vitals_data.dart';
import 'package:lap_deck/models/connector_models.dart';
import 'package:lap_deck/services/app_logger.dart';
import 'package:lap_deck/services/notification_service.dart';

void main() {
  test('HostTarget default hosts do not hardcode online or stale latency', () {
    final hosts = HostTarget.defaultHosts;
    expect(hosts.length, 2);
    expect(hosts[0].name, 'surajworklaptop');
    expect(hosts[0].tailscaleIp, '100.118.7.117');
    expect(hosts[0].peerStatus, PeerStatus.unknown);
    expect(hosts[0].sshStatus, ServiceStatus.unknown);
    expect(hosts[0].hasFreshLatency, isFalse);
    expect(hosts[0].lockActionTitle, 'Lock Linux Session');

    expect(hosts[1].name, 'mochirondesu');
    expect(hosts[1].tailscaleIp, '100.79.206.82');
    expect(hosts[1].osDisplayName, 'Windows 11 / WSL2');
    expect(hosts[1].lockActionTitle, 'Lock Windows Session');
    expect(hosts[1].lockSessionCommand, contains('LockWorkStation'));
    expect(hosts[1].lockSessionCommand, contains('schtasks.exe'));
    expect(hosts[1].lockSessionCommand, isNot(contains('2>nul &')));
    expect(hosts[1].killProcessCommand(4321), contains('Stop-Process -Id 4321'));
    expect(hosts[0].killProcessCommand(4321), 'kill -9 4321');
  });

  test('Independent peer and SSH states are not conflated', () {
    final peerOnlineSshDown = HostTarget.defaultHosts[1].copyWith(
      peerStatus: PeerStatus.online,
      sshStatus: ServiceStatus.unavailable,
      pingMs: 4,
      lastChecked: DateTime.now(),
    );
    expect(peerOnlineSshDown.isOnline, isTrue);
    expect(peerOnlineSshDown.reachabilityLabel, 'Online');
    expect(peerOnlineSshDown.sshStatusLabel, 'Unavailable');
    expect(peerOnlineSshDown.hasFreshLatency, isTrue);

    final unreachableHost = peerOnlineSshDown.copyWith(
      peerStatus: PeerStatus.unreachable,
      clearPing: true,
    );
    expect(unreachableHost.isOnline, isFalse);
    expect(unreachableHost.reachabilityLabel, 'Unreachable');
    expect(unreachableHost.hasFreshLatency, isFalse);
  });

  test('OperationLifecycleState exposes all required feedback labels', () {
    expect(OperationLifecycleState.ready.label, 'Ready');
    expect(OperationLifecycleState.inProgress.label, 'In progress');
    expect(OperationLifecycleState.successful.label, 'Successful');
    expect(OperationLifecycleState.failed.label, 'Failed');
    expect(OperationLifecycleState.timedOut.label, 'Timed out');
    expect(OperationLifecycleState.resultUnknown.label, 'Result unknown');
    expect(
      OperationLifecycleState.targetUnavailable.label,
      'Target unavailable',
    );
  });

  test('CommandAction default actions contain lapdog and telemetry', () {
    final actions = CommandAction.defaultActions;
    expect(actions.isNotEmpty, true);
    expect(actions.any((a) => a.id == 'act-lapdog-status'), true);
    expect(actions.any((a) => a.id == 'act-sys-telemetry'), true);
  });

  test('Connector models deserialize correctly from JSON', () {
    final healthJson = {
      'ok': true,
      'hostname': 'surajworklaptop',
      'role': 'main',
      'is_telegram_main': true,
      'role_description': 'Telegram Main (Active Poller)',
      'os': 'linux',
      'platform': 'Linux 7.0',
      'version': '2.22.2',
      'uptime_seconds': 7200,
      'lan_ip': '192.168.1.100',
      'tailscale_ip': '100.118.7.117',
      'cpu_percent': 12.5,
      'ram': {'percent': 45.0},
      'model': 'gemini-3.8-flash-medium',
    };

    final health = ConnectorHealthData.fromJson(healthJson);
    expect(health.ok, isTrue);
    expect(health.hostname, 'surajworklaptop');
    expect(health.isTelegramMain, isTrue);
    expect(health.role, 'main');
    expect(health.uptimeHuman, '2h 0m');
    expect(health.cpuPercent, 12.5);
    expect(health.ramPercent, 45.0);
    expect(health.model, 'gemini-3.8-flash-medium');

    final apiJson = {
      'path': '/api/peer/lifecycle',
      'method': 'POST',
      'category': 'Lifecycle',
      'summary': 'Lifecycle control',
      'description': 'User-initiated start/stop',
      'parameters': {
        'action': {'type': 'string', 'required': true},
      },
    };

    final api = ConnectorApiItem.fromJson(apiJson);
    expect(api.path, '/api/peer/lifecycle');
    expect(api.method, 'POST');
    expect(api.category, 'Lifecycle');
    expect(api.parameters.containsKey('action'), isTrue);

    final errorJson = {
      'id': 'err-1',
      'timestamp': '2026-11-18 17:00:00',
      'level': 'ERROR',
      'category': 'AI',
      'message': 'Token limit exceeded',
      'exception': 'ContextOverflowError',
    };

    final err = ConnectorErrorItem.fromJson(errorJson);
    expect(err.id, 'err-1');
    expect(err.category, 'AI');
    expect(err.exception, 'ContextOverflowError');

    final mediaJson = {
      'id': 'act-1',
      'timestamp': '2026-11-18 17:05:00',
      'user_id': '987654',
      'user_name': 'tester',
      'command': '/yt',
      'target': 'https://youtube.com/watch?v=123',
      'status': 'completed',
      'details': {'duration': '3:20'},
    };

    final media = MediaActivityItem.fromJson(mediaJson);
    expect(media.id, 'act-1');
    expect(media.command, '/yt');
    expect(media.status, 'completed');
  });

  test('AppLogger records, filters, and formats log entries correctly', () {
    AppLogger.debug('TestTag', 'Debug message');
    AppLogger.info('TestTag', 'Info message');
    AppLogger.warning('TestTag', 'Warning message');
    AppLogger.error('TestTag', 'Error message', 'SimulatedException');

    final all = AppLogger.instance.getRecentEntries(tagFilter: 'TestTag');
    expect(all.length, 4);

    final errorsOnly = AppLogger.instance.getRecentEntries(
      minLevel: LogLevel.warning,
      tagFilter: 'TestTag',
    );
    expect(errorsOnly.length, 2);

    final errorEntry = errorsOnly.firstWhere((e) => e.level == LogLevel.error);
    expect(errorEntry.error, 'SimulatedException');
    expect(errorEntry.format(), contains('SimulatedException'));
  });

  test('ConnectorPeerNodeState and ConnectorTargetConfig derive live roles and targets', () {
    final hostLinux = HostTarget.defaultHosts[0];
    final hostWin = HostTarget.defaultHosts[1];

    final mainHealth = ConnectorHealthData.fromJson({
      'ok': true,
      'hostname': 'MochironDesu',
      'role': 'main',
      'is_telegram_main': true,
      'os': 'windows',
      'platform': 'Windows 10',
      'version': '2.23.1',
      'uptime_seconds': 3600,
      'lan_ip': '192.168.29.61',
      'tailscale_ip': '100.79.206.82',
      'cpu_percent': 11.9,
      'ram': {'total_mb': 16295, 'available_mb': 4536, 'percent': 72.2},
      'disk': {'total_gb': 931.5, 'free_gb': 295.4, 'percent': 68.3},
      'workspace': 'D:\\',
      'active_node': 'windows',
    });

    final standbyHealth = ConnectorHealthData.fromJson({
      'ok': true,
      'hostname': 'surajWorkLaptop',
      'role': 'standby',
      'is_telegram_main': false,
      'os': 'linux',
      'platform': 'Linux 7.0',
      'version': '2.23.0',
      'uptime_seconds': 7200,
      'lan_ip': '10.8.0.45',
      'tailscale_ip': '100.118.7.117',
      'cpu_percent': 5.5,
      'ram': {'total_mb': 15681, 'available_mb': 3347, 'percent': 78.7},
      'workspace': '/home/surajwork/Coding/misc/lap-deck',
      'active_node': 'linux',
    });

    final mainPeer = ConnectorPeerNodeState(
      host: hostWin,
      connectionState: ConnectorPeerConnectionState.online,
      health: mainHealth,
    );
    final standbyPeer = ConnectorPeerNodeState(
      host: hostLinux,
      connectionState: ConnectorPeerConnectionState.online,
      health: standbyHealth,
    );
    final stoppedPeer = ConnectorPeerNodeState(
      host: hostLinux,
      connectionState: ConnectorPeerConnectionState.userStopped,
    );

    expect(mainPeer.isOnline, isTrue);
    expect(mainPeer.isMain, isTrue);
    expect(mainPeer.isStandby, isFalse);
    expect(mainPeer.roleLabel, 'MAIN');
    expect(mainPeer.displayHostname, 'MochironDesu');

    expect(standbyPeer.isOnline, isTrue);
    expect(standbyPeer.isMain, isFalse);
    expect(standbyPeer.isStandby, isTrue);
    expect(standbyPeer.roleLabel, 'STANDBY');

    expect(stoppedPeer.isOnline, isFalse);
    expect(stoppedPeer.isUserStopped, isTrue);
    expect(stoppedPeer.roleLabel, 'USER STOPPED');

    final targetCfg = ConnectorTargetConfig.fromJson({
      'ok': true,
      'hostname': 'surajWorkLaptop',
      'os': 'linux',
      'active_node': 'linux',
      'workspace': '/home/surajwork/Coding/misc/lap-deck',
      'available_workspaces': [
        {
          'path': '/home/surajwork/Coding/misc/lap-deck',
          'name': 'lap-deck',
          'is_git': true,
          'is_current': true,
        },
      ],
    });
    expect(targetCfg.activeNode, 'linux');
    expect(targetCfg.availableWorkspaces.length, 1);
    expect(targetCfg.availableWorkspaces.first.isGit, isTrue);
  });

  test('VitalsData holds and propagates workstation screen lock state', () {
    final empty = VitalsData.empty();
    expect(empty.isScreenLocked, isNull);

    final locked = empty.copyWith(isScreenLocked: true);
    expect(locked.isScreenLocked, isTrue);

    final unlocked = locked.copyWith(isScreenLocked: false);
    expect(unlocked.isScreenLocked, isFalse);

    final cleared = unlocked.copyWith(clearScreenLocked: true);
    expect(cleared.isScreenLocked, isNull);
  });

  test('RemoteFileItem formats sizes and detects hidden files correctly', () {
    const dir = RemoteFileItem(
      name: 'Documents',
      path: '/home/user/Documents',
      isDirectory: true,
      size: 4096,
    );
    expect(dir.formattedSize, '--');
    expect(dir.isHidden, isFalse);

    const smallFile = RemoteFileItem(
      name: 'notes.txt',
      path: '/home/user/notes.txt',
      isDirectory: false,
      size: 512,
    );
    expect(smallFile.formattedSize, '512 B');
    expect(smallFile.isHidden, isFalse);

    const kbFile = RemoteFileItem(
      name: 'image.png',
      path: '/home/user/image.png',
      isDirectory: false,
      size: 153600,
    );
    expect(kbFile.formattedSize, '150.0 KB');

    const mbFile = RemoteFileItem(
      name: 'archive.tar.gz',
      path: '/home/user/archive.tar.gz',
      isDirectory: false,
      size: 10485760,
    );
    expect(mbFile.formattedSize, '10.0 MB');

    const dotFile = RemoteFileItem(
      name: '.bashrc',
      path: '/home/user/.bashrc',
      isDirectory: false,
      size: 3500,
    );
    expect(dotFile.isHidden, isTrue);
  });

  test('AiStreamEvent and AiConversationTurn parse NDJSON streaming payloads', () {
    final initEvent = AiStreamEvent.fromJson({
      'event': 'init',
      'conversation_id': '37c80d7e-6544-41b3-a072-e7a1cc7ea230',
    });
    expect(initEvent.event, 'init');
    expect(initEvent.conversationId, '37c80d7e-6544-41b3-a072-e7a1cc7ea230');

    final streamEvent = AiStreamEvent.fromJson({
      'event': 'stream',
      'accumulated_text': 'Inspecting workspace...',
      'current_tool': 'bash: git status',
    });
    expect(streamEvent.event, 'stream');
    expect(streamEvent.accumulatedText, 'Inspecting workspace...');
    expect(streamEvent.currentTool, 'bash: git status');

    final finalEvent = AiStreamEvent.fromJson({
      'event': 'final',
      'ok': true,
      'status': 'success',
      'conversation_id': '37c80d7e-6544-41b3-a072-e7a1cc7ea230',
      'response_text': 'All checks passed.',
      'total_tokens': 4120,
      'duration_seconds': 8.4,
    });
    expect(finalEvent.ok, isTrue);
    expect(finalEvent.responseText, 'All checks passed.');
    expect(finalEvent.totalTokens, 4120);

    final turn = AiConversationTurn.fromJson({
      'step_index': 2,
      'prompt': 'Run flutter test',
      'response': 'All tests passed.',
      'thinking': 'Checking unit tests in test/widget_test.dart',
      'tools': ['run_command', 'read_file'],
      'status': 'completed',
    });
    expect(turn.stepIndex, 2);
    expect(turn.prompt, 'Run flutter test');
    expect(turn.tools, ['run_command', 'read_file']);
    expect(turn.status, AiTurnStatus.completed);
  });

  test('OtaUpdateInfo compares installed and remote Git commit SHAs accurately', () {
    final upToDate = OtaUpdateInfo(
      state: OtaUpdateState.upToDate,
      installedCommitSha: 'a1b2c3d',
      latestCommitSha: 'a1b2c3d4e5f60718293a4b5c6d7e8f9012345678',
      checkedAt: DateTime.now(),
    );
    expect(upToDate.hasNewerCommit, isFalse);
    expect(upToDate.shortInstalledSha, 'a1b2c3d');
    expect(upToDate.shortLatestSha, 'a1b2c3d');

    final updateReady = OtaUpdateInfo(
      state: OtaUpdateState.updateAvailable,
      installedCommitSha: 'a1b2c3d',
      latestCommitSha: 'f9e8d7c6b5a432109876543210fedcba98765432',
      latestCommitMessage: 'fix: normalize quick action heights',
      apkDownloadUrl: 'https://github.com/mochiron-desu/lap-deck/releases/download/hotfix-latest/lapdeck-hotfix.apk',
      apkSizeBytes: 24 * 1024 * 1024,
      checkedAt: DateTime.now(),
    );
    expect(updateReady.hasNewerCommit, isTrue);
    expect(updateReady.hasDirectApkAsset, isTrue);
    expect(updateReady.shortLatestSha, 'f9e8d7c');
    expect(updateReady.formattedApkSize, '24.0 MB');
  });

  test('NotificationService deduplicates host states and fires only on real transitions', () {
    final service = NotificationService();
    const cfg = NotificationSettings(
      masterEnabled: true,
      peerStatusTransitions: true,
      subsystemAndConnectorErrors: true,
      lapdogSecurityEvents: true,
    );

    final baseHost = HostTarget.defaultHosts[0];

    // 1. Initial unknown/connecting probes never trigger notifications
    expect(service.evaluateHostTransition(baseHost, cfg: cfg), isNull);
    expect(
      service.evaluateHostTransition(
        baseHost.copyWith(peerStatus: PeerStatus.connecting),
        cfg: cfg,
      ),
      isNull,
    );

    // 2. First verified online baseline is recorded silently without false transition alert
    final onlineHost = baseHost.copyWith(
      peerStatus: PeerStatus.online,
      sshStatus: ServiceStatus.available,
      pingMs: 8,
    );
    expect(service.evaluateHostTransition(onlineHost, cfg: cfg), isNull);

    // 3. Repeated online polls do not spam
    expect(service.evaluateHostTransition(onlineHost, cfg: cfg), isNull);

    // 4. Transition from Online -> Unreachable triggers offline alert
    final offlineHost = onlineHost.copyWith(
      peerStatus: PeerStatus.unreachable,
      sshStatus: ServiceStatus.unavailable,
    );
    final offlineAlert = service.evaluateHostTransition(offlineHost, cfg: cfg);
    expect(offlineAlert, isNotNull);
    expect(offlineAlert!.channelId, NotificationService.channelDevices);
    expect(offlineAlert.title, contains('went Offline'));

    // 5. Transition from Unreachable -> Online triggers online alert
    final backOnlineAlert = service.evaluateHostTransition(onlineHost, cfg: cfg);
    expect(backOnlineAlert, isNotNull);
    expect(backOnlineAlert!.title, contains('is Online'));

    // 6. Peer remains Online, but SSH drops to Unavailable -> triggers subsystem error alert
    final sshDownHost = onlineHost.copyWith(
      sshStatus: ServiceStatus.unavailable,
    );
    final sshAlert = service.evaluateHostTransition(sshDownHost, cfg: cfg);
    expect(sshAlert, isNotNull);
    expect(sshAlert!.channelId, NotificationService.channelErrors);
    expect(sshAlert.title, contains('SSH Unavailable'));

    // 7. Lapdog pending events increase -> triggers security alert
    const lapdog1 = LapdogStatus(
      isInstalled: true,
      isAwayArmed: true,
      pendingEvents: 2,
    );
    final securityAlert = service.evaluateHostTransition(
      onlineHost,
      lapdog: lapdog1,
      cfg: cfg,
    );
    expect(securityAlert, isNotNull);
    expect(securityAlert!.channelId, NotificationService.channelSecurity);
    expect(securityAlert.title, contains('Lapdog Security Alert'));
  });
}
