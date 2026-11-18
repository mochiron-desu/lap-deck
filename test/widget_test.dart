import 'package:flutter_test/flutter_test.dart';
import 'package:lap_deck/models/host_target.dart';
import 'package:lap_deck/models/command_action.dart';
import 'package:lap_deck/models/vitals_data.dart';

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
}
