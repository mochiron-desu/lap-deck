import 'package:flutter_test/flutter_test.dart';
import 'package:lap_deck/models/host_target.dart';
import 'package:lap_deck/models/command_action.dart';
import 'package:lap_deck/models/vitals_data.dart';
import 'package:lap_deck/models/connector_models.dart';
import 'package:lap_deck/services/app_logger.dart';

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
}
