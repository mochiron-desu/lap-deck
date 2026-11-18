import 'package:flutter_test/flutter_test.dart';
import 'package:lap_deck/models/host_target.dart';
import 'package:lap_deck/models/command_action.dart';

void main() {
  test('HostTarget default hosts are valid', () {
    final hosts = HostTarget.defaultHosts;
    expect(hosts.length, 2);
    expect(hosts[0].name, 'surajworklaptop');
    expect(hosts[0].tailscaleIp, '100.118.7.117');
    expect(hosts[1].name, 'mochirondesu');
    expect(hosts[1].tailscaleIp, '100.79.206.82');
  });

  test('CommandAction default actions contain lapdog and telemetry', () {
    final actions = CommandAction.defaultActions;
    expect(actions.isNotEmpty, true);
    expect(actions.any((a) => a.id == 'act-lapdog-status'), true);
    expect(actions.any((a) => a.id == 'act-sys-telemetry'), true);
  });
}
