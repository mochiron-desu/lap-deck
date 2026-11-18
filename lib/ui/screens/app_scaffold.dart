import 'package:flutter/material.dart';
import '../../models/host_target.dart';
import '../../models/vitals_data.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../services/terminal_session_controller.dart';
import 'home_tab.dart';
import 'devices_tab.dart';
import 'terminal_tab.dart';
import 'settings_tab.dart';

class AppScaffold extends StatefulWidget {
  final StorageService storage;
  final SshService sshService;
  final TerminalSessionController terminalController;

  const AppScaffold({
    super.key,
    required this.storage,
    required this.sshService,
    required this.terminalController,
  });

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> {
  int _currentTabIndex = 0;
  late List<HostTarget> _hosts;
  HostTarget? _activeHost;
  VitalsData _vitals = VitalsData.empty();
  LapdogStatus _lapdogStatus = const LapdogStatus();

  bool _isVitalsLoading = false;
  String? _connectionError;

  @override
  void initState() {
    super.initState();
    _hosts = widget.storage.loadHosts();
    final activeId = widget.storage.getActiveHostId();
    if (_hosts.isNotEmpty) {
      _activeHost = _hosts.firstWhere(
        (h) => h.id == activeId,
        orElse: () => _hosts.first,
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNetworkState();
    });
  }

  Future<void> _refreshNetworkState() async {
    final host = _activeHost;
    if (host == null) return;

    setState(() {
      _isVitalsLoading = true;
      _connectionError = null;
    });

    final secret = await widget.storage.getHostCredential(host.id);

    try {
      // 1. Parallel live reachability test across all known nodes
      final reachabilityResults = await Future.wait(
        _hosts.map((h) => widget.sshService.checkReachability(h)),
      );

      final updatedHosts = <HostTarget>[];
      for (int i = 0; i < _hosts.length; i++) {
        final res = reachabilityResults[i];
        updatedHosts.add(_hosts[i].copyWith(
          isOnline: res.isOnline,
          pingMs: res.latencyMs,
          isDirect: res.isDirect,
        ));
      }

      final updatedActive = updatedHosts.firstWhere(
        (h) => h.id == host.id,
        orElse: () => updatedHosts.first,
      );

      // 2. Fetch full telemetry bundle only if target host is reachable
      TelemetryBundle? bundle;
      if (updatedActive.isOnline) {
        bundle = await widget.sshService.fetchTelemetryBundle(updatedActive, secret: secret);
      }

      if (mounted) {
        setState(() {
          _hosts = updatedHosts;
          _activeHost = updatedActive;
          if (bundle != null) {
            _vitals = bundle.vitals;
            _lapdogStatus = bundle.lapdog;
            _connectionError = null;
          } else if (!updatedActive.isOnline) {
            _vitals = VitalsData.empty();
            _connectionError = 'Cannot reach ${updatedActive.name} (${updatedActive.tailscaleIp}). Check Tailscale VPN.';
          } else {
            _connectionError = 'Failed to fetch telemetry from ${updatedActive.name}.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _connectionError = 'Timeout reaching ${host.name}. Ensure device is online on Tailscale.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isVitalsLoading = false);
      }
    }
  }

  void _handleSelectHost(HostTarget host) {
    setState(() => _activeHost = host);
    widget.storage.setActiveHostId(host.id);
    _refreshNetworkState();
  }

  void _reloadHosts() {
    setState(() {
      _hosts = widget.storage.loadHosts();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentTabIndex == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _currentTabIndex != 0) {
          setState(() => _currentTabIndex = 0);
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: _currentTabIndex,
          children: [
            // Tab 0: Home
            HomeTab(
              hosts: _hosts,
              activeHost: _activeHost,
              vitals: _vitals,
              lapdogStatus: _lapdogStatus,
              isVitalsLoading: _isVitalsLoading,
              connectionError: _connectionError,
              storage: widget.storage,
              sshService: widget.sshService,
              terminalController: widget.terminalController,
              onSelectHost: _handleSelectHost,
              onRefresh: _refreshNetworkState,
              onNavigateTab: (index) => setState(() => _currentTabIndex = index),
              onHostsUpdated: _reloadHosts,
            ),
            // Tab 1: Devices
            DevicesTab(
              hosts: _hosts,
              activeHost: _activeHost,
              storage: widget.storage,
              sshService: widget.sshService,
              terminalController: widget.terminalController,
              onSelectHost: _handleSelectHost,
              onHostsUpdated: _reloadHosts,
            ),
            // Tab 2: Terminal
            TerminalTab(
              hosts: _hosts,
              activeHost: _activeHost,
              controller: widget.terminalController,
              storage: widget.storage,
              onSelectHost: _handleSelectHost,
            ),
            // Tab 3: Settings
            SettingsTab(
              storage: widget.storage,
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentTabIndex,
          onDestinationSelected: (index) => setState(() => _currentTabIndex = index),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home',
            ),
            NavigationDestination(
              icon: Icon(Icons.devices_outlined),
              selectedIcon: Icon(Icons.devices),
              label: 'Devices',
            ),
            NavigationDestination(
              icon: Icon(Icons.terminal_outlined),
              selectedIcon: Icon(Icons.terminal),
              label: 'Terminal',
            ),
            NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings',
            ),
          ],
        ),
      ),
    );
  }
}
