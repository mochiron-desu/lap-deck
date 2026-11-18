import 'package:flutter/material.dart';
import '../../models/host_target.dart';
import '../../models/vitals_data.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../services/terminal_session_controller.dart';
import '../../services/connector_service.dart';
import '../../services/app_logger.dart';
import 'home_tab.dart';
import 'devices_tab.dart';
import 'connector_tab.dart';
import 'settings_tab.dart';

class AppScaffold extends StatefulWidget {
  final StorageService storage;
  final SshService sshService;
  final TerminalSessionController terminalController;
  final ConnectorService connectorService;

  AppScaffold({
    super.key,
    required this.storage,
    required this.sshService,
    required this.terminalController,
    ConnectorService? connectorService,
  }) : connectorService = connectorService ?? ConnectorService();

  @override
  State<AppScaffold> createState() => _AppScaffoldState();
}

class _AppScaffoldState extends State<AppScaffold> with WidgetsBindingObserver {
  int _currentTabIndex = 0;
  late List<HostTarget> _hosts;
  String? _selectedHostId;

  // Per-host cached telemetry keyed by stable host.id
  final Map<String, TelemetryBundle> _telemetryByHost = {};

  bool _isRefreshing = false;
  bool _localTailscaleActive = false;
  DateTime? _lastNetworkCheckAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hosts = widget.storage.loadHosts();
    final savedId = widget.storage.getActiveHostId();
    if (_hosts.isNotEmpty) {
      final match = _hosts.where((h) => h.id == savedId);
      _selectedHostId = match.isNotEmpty ? match.first.id : _hosts.first.id;
      widget.storage.setActiveHostId(_selectedHostId!);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshNetworkState();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Refresh reachability on resume without changing selected target
      _refreshNetworkState();
    }
  }

  HostTarget? get _activeHost {
    if (_hosts.isEmpty) return null;
    if (_selectedHostId != null) {
      for (final h in _hosts) {
        if (h.id == _selectedHostId) return h;
      }
    }
    return _hosts.first;
  }

  VitalsData get _activeVitals {
    final id = _activeHost?.id;
    if (id == null) return VitalsData.empty();
    return _telemetryByHost[id]?.vitals ?? VitalsData.empty();
  }

  LapdogStatus get _activeLapdogStatus {
    final id = _activeHost?.id;
    if (id == null) return const LapdogStatus();
    return _telemetryByHost[id]?.lapdog ?? const LapdogStatus();
  }

  Future<void> _refreshNetworkState({String? explicitTargetId}) async {
    if (_hosts.isEmpty) return;

    final targetIdToInspect = explicitTargetId ?? _activeHost?.id;
    final snapshotHosts = List<HostTarget>.from(_hosts);

    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _hosts = _hosts.map((h) {
          if (h.peerStatus == PeerStatus.unknown) {
            return h.copyWith(
              peerStatus: PeerStatus.connecting,
              sshStatus: ServiceStatus.connecting,
            );
          }
          return h;
        }).toList();
      });
    }

    try {
      AppLogger.info('AppScaffold', 'Probing network reachability across ${_hosts.length} peers...');
      // 1. Parallel live reachability test across all known peers
      final reachabilityResults = await Future.wait(
        snapshotHosts.map((h) => widget.sshService.checkReachability(h)),
      );

      bool anyTailscaleActive = false;
      final Map<String, HostReachability> reachById = {};
      for (int i = 0; i < snapshotHosts.length; i++) {
        final r = reachabilityResults[i];
        reachById[snapshotHosts[i].id] = r;
        AppLogger.debug(
          'AppScaffold',
          'Peer probe: ${snapshotHosts[i].name} -> online: ${r.isOnline}, ssh: ${r.sshPortStatus.name}, ping: ${r.latencyMs}ms',
        );
        if (r.localTailscaleActive || (r.isOnline && !r.isDirect)) {
          anyTailscaleActive = true;
        }
      }

      if (mounted) {
        setState(() {
          _localTailscaleActive = anyTailscaleActive;
          _lastNetworkCheckAt = DateTime.now();
          _hosts = _hosts.map((h) {
            final r = reachById[h.id];
            if (r == null) return h;
            return h.copyWith(
              isOnline: r.isOnline,
              peerStatus: r.peerStatus,
              sshStatus: r.sshPortStatus,
              pingMs: r.isOnline ? r.latencyMs : null,
              clearPing: !r.isOnline,
              isDirect: r.isDirect,
              lastChecked: r.checkedAt,
              lastError: r.errorDetail,
              clearError: r.errorDetail == null,
              agentStatus: r.sshPortStatus == ServiceStatus.available
                  ? h.agentStatus
                  : ServiceStatus.unavailable,
              lapdogDaemonStatus: r.sshPortStatus == ServiceStatus.available
                  ? h.lapdogDaemonStatus
                  : ServiceStatus.unavailable,
            );
          }).toList();
        });
      }

      // 2. Fetch telemetry bundle for the inspected target host if its SSH port is reachable
      if (targetIdToInspect != null) {
        HostTarget? targetHost;
        for (final h in _hosts) {
          if (h.id == targetIdToInspect) {
            targetHost = h;
            break;
          }
        }

        if (targetHost != null &&
            targetHost.peerStatus == PeerStatus.online &&
            targetHost.sshStatus == ServiceStatus.available) {
          final secret = await widget.storage.getHostCredential(targetHost.id);
          final bundle = await widget.sshService.fetchTelemetryBundle(
            targetHost,
            secret: secret,
          );

          if (mounted) {
            setState(() {
              if (bundle != null) {
                _telemetryByHost[targetHost!.id] = bundle;
                _hosts = _hosts.map((h) {
                  if (h.id != targetHost!.id) return h;
                  return h.copyWith(
                    sshStatus: ServiceStatus.available,
                    agentStatus: ServiceStatus.available,
                    lapdogDaemonStatus: bundle.lapdog.isInstalled
                        ? ServiceStatus.available
                        : ServiceStatus.unavailable,
                    lastConnected: bundle.fetchedAt,
                    clearError: true,
                  );
                }).toList();
              } else {
                // TCP port opened, but SSH auth or command execution failed.
                // Peer remains online; only SSH/Agent subsystem is marked unavailable.
                _hosts = _hosts.map((h) {
                  if (h.id != targetHost!.id) return h;
                  return h.copyWith(
                    sshStatus: ServiceStatus.unavailable,
                    agentStatus: ServiceStatus.unavailable,
                    lapdogDaemonStatus: ServiceStatus.unknown,
                    lastError:
                        'Host ${targetHost.name} is reachable on the network, but SSH authentication or telemetry execution failed.',
                  );
                }).toList();
              }
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastNetworkCheckAt = DateTime.now();
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  void _handleSelectHost(HostTarget host) {
    final previousId = _selectedHostId;
    setState(() {
      _selectedHostId = host.id;
    });
    widget.storage.setActiveHostId(host.id);
    if (previousId != host.id || !_telemetryByHost.containsKey(host.id)) {
      _refreshNetworkState(explicitTargetId: host.id);
    }
  }

  void _reloadHosts() {
    final loaded = widget.storage.loadHosts();
    setState(() {
      // Preserve live runtime telemetry/reachability for existing hosts by id
      final existingById = {for (final h in _hosts) h.id: h};
      _hosts = loaded.map((newH) {
        final prev = existingById[newH.id];
        if (prev == null) return newH;
        return newH.copyWith(
          isOnline: prev.isOnline,
          peerStatus: prev.peerStatus,
          sshStatus: prev.sshStatus,
          agentStatus: prev.agentStatus,
          lapdogDaemonStatus: prev.lapdogDaemonStatus,
          pingMs: prev.pingMs,
          isDirect: prev.isDirect,
          lastChecked: prev.lastChecked,
          lastConnected: prev.lastConnected,
          lastError: prev.lastError,
        );
      }).toList();

      // Only fallback if the selected device was explicitly deleted by the user
      if (_selectedHostId != null &&
          !_hosts.any((h) => h.id == _selectedHostId)) {
        _selectedHostId = _hosts.isNotEmpty ? _hosts.first.id : null;
        if (_selectedHostId != null) {
          widget.storage.setActiveHostId(_selectedHostId!);
        }
      }
    });
    _refreshNetworkState();
  }

  void _handleUpdateHostTelemetry(String hostId, TelemetryBundle bundle) {
    if (!mounted) return;
    setState(() {
      _telemetryByHost[hostId] = bundle;
      _hosts = _hosts.map((h) {
        if (h.id != hostId) return h;
        return h.copyWith(
          isOnline: true,
          peerStatus: PeerStatus.online,
          sshStatus: ServiceStatus.available,
          agentStatus: ServiceStatus.available,
          lapdogDaemonStatus: bundle.lapdog.isInstalled
              ? ServiceStatus.available
              : ServiceStatus.unavailable,
          lastChecked: bundle.fetchedAt,
          lastConnected: bundle.fetchedAt,
          clearError: true,
        );
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeHost = _activeHost;

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
              activeHost: activeHost,
              vitals: _activeVitals,
              lapdogStatus: _activeLapdogStatus,
              isVitalsLoading: _isRefreshing,
              localTailscaleActive: _localTailscaleActive,
              lastNetworkCheckAt: _lastNetworkCheckAt,
              storage: widget.storage,
              sshService: widget.sshService,
              terminalController: widget.terminalController,
              onSelectHost: _handleSelectHost,
              onRefresh: () => _refreshNetworkState(),
              onNavigateTab: (index) =>
                  setState(() => _currentTabIndex = index),
              onHostsUpdated: _reloadHosts,
              onTelemetryUpdated: _handleUpdateHostTelemetry,
            ),
            // Tab 1: Devices
            DevicesTab(
              hosts: _hosts,
              activeHost: activeHost,
              storage: widget.storage,
              sshService: widget.sshService,
              terminalController: widget.terminalController,
              onSelectHost: _handleSelectHost,
              onHostsUpdated: _reloadHosts,
              onRefresh: () => _refreshNetworkState(),
              isRefreshing: _isRefreshing,
            ),
            // Tab 2: Connector
            ConnectorTab(
              hosts: _hosts,
              activeHost: activeHost,
              storage: widget.storage,
              connectorService: widget.connectorService,
              sshService: widget.sshService,
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
          onDestinationSelected: (index) =>
              setState(() => _currentTabIndex = index),
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
              icon: Icon(Icons.cell_tower_outlined),
              selectedIcon: Icon(Icons.cell_tower),
              label: 'Connector',
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
