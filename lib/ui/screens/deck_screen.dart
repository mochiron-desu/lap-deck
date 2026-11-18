import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';
import '../../models/vitals_data.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../widgets/deck_header.dart';
import '../widgets/host_rack_selector.dart';
import '../widgets/vitals_card.dart';
import '../widgets/lapdog_card.dart';
import '../widgets/process_manager_card.dart';
import '../widgets/quick_controls_card.dart';
import 'host_config_dialog.dart';

class DeckScreen extends StatefulWidget {
  final StorageService storage;
  final SshService sshService;

  const DeckScreen({
    super.key,
    required this.storage,
    required this.sshService,
  });

  @override
  State<DeckScreen> createState() => _DeckScreenState();
}

class _DeckScreenState extends State<DeckScreen> {
  late List<HostTarget> _hosts;
  HostTarget? _activeHost;
  VitalsData _vitals = VitalsData.empty();
  List<ProcessItem> _processes = [];
  LapdogStatus _lapdogStatus = const LapdogStatus();

  bool _isVitalsLoading = false;
  bool _isProcessLoading = false;
  bool _isLapdogToggling = false;
  bool _isExecutingAction = false;
  String? _executingLabel;
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
    // Auto-fetch data on startup
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAllData();
    });
  }

  Future<void> _refreshAllData() async {
    final host = _activeHost;
    if (host == null) return;

    setState(() {
      _isVitalsLoading = true;
      _isProcessLoading = true;
      _connectionError = null;
    });

    final secret = await widget.storage.getHostCredential(host.id);

    try {
      // 1. Fetch vitals
      final vitals = await widget.sshService.fetchVitals(host, secret: secret);
      if (vitals != null) {
        setState(() {
          _vitals = vitals;
          _connectionError = null;
        });
      } else {
        setState(() {
          _connectionError = 'Connection failed. Ensure Tailscale VPN is connected on your phone.';
        });
      }

      // 2. Fetch processes
      final procs = await widget.sshService.fetchProcesses(host, secret: secret);
      setState(() => _processes = procs);

      // 3. Fetch Lapdog state
      final lapdog = await widget.sshService.fetchLapdogStatus(host, secret: secret);
      setState(() => _lapdogStatus = lapdog);
    } catch (e) {
      setState(() {
        _connectionError = 'SSH Timeout. Ensure Tailscale is active on phone and laptop is powered on.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isVitalsLoading = false;
          _isProcessLoading = false;
        });
      }
    }
  }

  Future<void> _handleSelectHost(HostTarget host) async {
    setState(() {
      _activeHost = host;
      _vitals = VitalsData.empty();
      _processes = [];
      _lapdogStatus = const LapdogStatus();
    });
    await widget.storage.setActiveHostId(host.id);
    _refreshAllData();
  }

  Future<void> _handleToggleAway(bool enableAway) async {
    final host = _activeHost;
    if (host == null) return;

    setState(() => _isLapdogToggling = true);
    final secret = await widget.storage.getHostCredential(host.id);
    final cmd = enableAway ? 'lapdog away 2>/dev/null' : 'lapdog back 2>/dev/null';

    final res = await widget.sshService.executeCommand(
      host: host,
      command: cmd,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
      password: host.authMethod == AuthMethod.password ? secret : null,
    );

    final success = res.isSuccess;
    setState(() {
      _isLapdogToggling = false;
      if (success) {
        _lapdogStatus = LapdogStatus(
          isInstalled: true,
          isAwayArmed: enableAway,
          sentHistory: _lapdogStatus.sentHistory,
        );
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (enableAway
                    ? 'Lap-Dog Away Mode is now ARMED. Alerts enabled.'
                    : 'Lap-Dog Away Mode DISARMED. Normal home mode.')
                : 'Failed to toggle Lap-Dog: ${res.error}',
          ),
          backgroundColor: success
              ? (enableAway ? DeckColors.cautionAmber : DeckColors.phosphorGreen)
              : DeckColors.alertCrimson,
        ),
      );
    }
  }

  Future<void> _handleKillProcess(ProcessItem proc) async {
    final host = _activeHost;
    if (host == null) return;

    final secret = await widget.storage.getHostCredential(host.id);
    await widget.sshService.executeCommand(
      host: host,
      command: 'kill -9 ${proc.pid}',
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
      password: host.authMethod == AuthMethod.password ? secret : null,
    );

    setState(() {
      _processes.removeWhere((p) => p.pid == proc.pid);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terminated ${proc.name} (PID ${proc.pid})'),
          backgroundColor: DeckColors.surfaceElevated,
        ),
      );
    }
  }

  Future<void> _handleTriggerAction(String actionId, String label, String command) async {
    final host = _activeHost;
    if (host == null) return;

    setState(() {
      _isExecutingAction = true;
      _executingLabel = label;
    });

    final secret = await widget.storage.getHostCredential(host.id);
    final res = await widget.sshService.executeCommand(
      host: host,
      command: command,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
      password: host.authMethod == AuthMethod.password ? secret : null,
    );

    setState(() {
      _isExecutingAction = false;
      _executingLabel = null;
    });

    if (mounted) {
      final success = res.isSuccess;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '$label completed successfully' : 'Execution failed: ${res.error}'),
          backgroundColor: success ? DeckColors.surfaceElevated : DeckColors.alertCrimson,
        ),
      );
    }

    // Refresh telemetry if power or lapdog was modified
    if (actionId.contains('lapdog') || actionId.contains('sync')) {
      _refreshAllData();
    }
  }

  void _openHostDialog({HostTarget? hostToEdit}) {
    showDialog(
      context: context,
      builder: (ctx) => HostConfigDialog(
        initialHost: hostToEdit,
        onSave: (updatedHost, secret) async {
          final index = _hosts.indexWhere((h) => h.id == updatedHost.id);
          if (index >= 0) {
            _hosts[index] = updatedHost;
          } else {
            _hosts.add(updatedHost);
          }
          await widget.storage.saveHosts(_hosts);
          if (secret != null) {
            await widget.storage.saveHostCredential(updatedHost.id, secret);
          }
          setState(() => _activeHost = updatedHost);
          _refreshAllData();
        },
        onDelete: (hostId) async {
          _hosts.removeWhere((h) => h.id == hostId);
          await widget.storage.saveHosts(_hosts);
          await widget.storage.deleteHostCredential(hostId);
          setState(() {
            _activeHost = _hosts.isNotEmpty ? _hosts.first : null;
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Tactical Header
          DeckHeader(
            activeHost: _activeHost,
            onRefresh: _refreshAllData,
            onAddHost: () => _openHostDialog(),
          ),

          // Connection Diagnostic Alert Banner (if host unreachable)
          if (_connectionError != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: DeckColors.alertCrimson.withValues(alpha: 0.15),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 16, color: DeckColors.alertCrimson),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _connectionError!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: DeckColors.alertCrimson,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: _refreshAllData,
                    child: const Padding(
                      padding: EdgeInsets.all(4.0),
                      child: Text(
                        'RETRY',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: DeckColors.alertCrimson),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Main Control Panel Body (Scrollable Dashboard)
          Expanded(
            child: RefreshIndicator(
              color: DeckColors.accentOrange,
              backgroundColor: DeckColors.surfaceRack,
              onRefresh: _refreshAllData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section 1: Peer Host Rack Selector
                    HostRackSelector(
                      hosts: _hosts,
                      activeHost: _activeHost,
                      onSelectHost: _handleSelectHost,
                      onEditHost: (host) => _openHostDialog(hostToEdit: host),
                    ),
                    const SizedBox(height: 16),

                    // Section 2: Live Vitals Dashboard
                    VitalsCard(
                      vitals: _vitals,
                      isLoading: _isVitalsLoading,
                      onRefresh: _refreshAllData,
                    ),
                    const SizedBox(height: 16),

                    // Section 3: Lap-Dog Security Hub
                    LapdogCard(
                      status: _lapdogStatus,
                      isToggling: _isLapdogToggling,
                      onToggleAway: _handleToggleAway,
                    ),
                    const SizedBox(height: 16),

                    // Section 4: One-Touch Quick Controls
                    QuickControlsCard(
                      isExecuting: _isExecutingAction,
                      executingLabel: _executingLabel,
                      onTrigger: _handleTriggerAction,
                    ),
                    const SizedBox(height: 16),

                    // Section 5: Active Process Manager
                    ProcessManagerCard(
                      processes: _processes,
                      isLoading: _isProcessLoading,
                      onKillProcess: _handleKillProcess,
                      onRefresh: _refreshAllData,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
