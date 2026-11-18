import 'package:flutter/material.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';
import '../../models/vitals_data.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../services/terminal_session_controller.dart';
import '../widgets/vitals_card.dart';
import '../widgets/lapdog_card.dart';
import '../widgets/process_manager_card.dart';
import '../widgets/quick_controls_card.dart';
import 'host_config_dialog.dart';

class DeviceDetailScreen extends StatefulWidget {
  final HostTarget host;
  final StorageService storage;
  final SshService sshService;
  final TerminalSessionController terminalController;
  final VoidCallback onUpdated;

  const DeviceDetailScreen({
    super.key,
    required this.host,
    required this.storage,
    required this.sshService,
    required this.terminalController,
    required this.onUpdated,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late HostTarget _currentHost;
  VitalsData _vitals = VitalsData.empty();
  List<ProcessItem> _processes = [];
  LapdogStatus _lapdogStatus = const LapdogStatus();

  bool _isVitalsLoading = false;
  bool _isProcessLoading = false;
  bool _isLapdogToggling = false;
  bool _isExecutingAction = false;
  String? _executingLabel;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _currentHost = widget.host;
    _fetchDeviceTelemetry();
  }

  Future<void> _fetchDeviceTelemetry() async {
    setState(() {
      _isVitalsLoading = true;
      _isProcessLoading = true;
      _errorMessage = null;
    });

    final secret = await widget.storage.getHostCredential(_currentHost.id);

    try {
      final bundle = await widget.sshService.fetchTelemetryBundle(_currentHost, secret: secret);
      if (mounted) {
        setState(() {
          if (bundle != null) {
            _vitals = bundle.vitals;
            _processes = bundle.processes;
            _lapdogStatus = bundle.lapdog;
            _errorMessage = null;
          } else {
            _errorMessage = 'Host unreachable. Ensure Tailscale is active and device is awake.';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'SSH Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isVitalsLoading = false;
          _isProcessLoading = false;
        });
      }
    }
  }

  Future<void> _handleToggleAway(bool enableAway) async {
    setState(() => _isLapdogToggling = true);
    final secret = await widget.storage.getHostCredential(_currentHost.id);
    final cmd = enableAway ? 'lapdog away 2>/dev/null' : 'lapdog back 2>/dev/null';

    final res = await widget.sshService.executeCommand(
      host: _currentHost,
      command: cmd,
      privateKeyPem: _currentHost.authMethod == AuthMethod.privateKey ? secret : null,
      password: _currentHost.authMethod == AuthMethod.password ? secret : null,
    );

    setState(() {
      _isLapdogToggling = false;
      if (res.isSuccess) {
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
            res.isSuccess
                ? (enableAway ? 'Lap-Dog Away Mode ARMED' : 'Lap-Dog Away Mode DISARMED')
                : 'Failed to update Away Mode',
          ),
          backgroundColor: enableAway ? DeckColors.warning : DeckColors.healthy,
        ),
      );
    }
  }

  Future<void> _handleKillProcess(ProcessItem proc) async {
    final secret = await widget.storage.getHostCredential(_currentHost.id);
    await widget.sshService.executeCommand(
      host: _currentHost,
      command: 'kill -9 ${proc.pid}',
      privateKeyPem: _currentHost.authMethod == AuthMethod.privateKey ? secret : null,
      password: _currentHost.authMethod == AuthMethod.password ? secret : null,
    );

    setState(() {
      _processes.removeWhere((p) => p.pid == proc.pid);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Terminated ${proc.name} (PID ${proc.pid})')),
      );
    }
  }

  Future<void> _handleTriggerAction(String actionId, String label, String command) async {
    setState(() {
      _isExecutingAction = true;
      _executingLabel = label;
    });

    final secret = await widget.storage.getHostCredential(_currentHost.id);
    final res = await widget.sshService.executeCommand(
      host: _currentHost,
      command: command,
      privateKeyPem: _currentHost.authMethod == AuthMethod.privateKey ? secret : null,
      password: _currentHost.authMethod == AuthMethod.password ? secret : null,
    );

    setState(() {
      _isExecutingAction = false;
      _executingLabel = null;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.isSuccess ? '$label completed' : 'Execution failed: ${res.error}'),
          backgroundColor: res.isSuccess ? DeckColors.surfaceElevated : DeckColors.error,
        ),
      );
    }

    _fetchDeviceTelemetry();
  }

  void _openEditDialog() {
    showDialog(
      context: context,
      builder: (ctx) => HostConfigDialog(
        initialHost: _currentHost,
        onSave: (updated, secret) async {
          final hosts = widget.storage.loadHosts();
          final idx = hosts.indexWhere((h) => h.id == updated.id);
          if (idx >= 0) {
            hosts[idx] = updated;
            await widget.storage.saveHosts(hosts);
          }
          if (secret != null) {
            await widget.storage.saveHostCredential(updated.id, secret);
          }
          setState(() => _currentHost = updated);
          widget.onUpdated();
          _fetchDeviceTelemetry();
        },
        onDelete: (id) async {
          final hosts = widget.storage.loadHosts();
          hosts.removeWhere((h) => h.id == id);
          await widget.storage.saveHosts(hosts);
          await widget.storage.deleteHostCredential(id);
          widget.onUpdated();
          if (mounted) Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_currentHost.name),
        backgroundColor: DeckColors.background,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh Telemetry',
            onPressed: _fetchDeviceTelemetry,
          ),
          IconButton(
            icon: const Icon(Icons.tune, size: 20),
            tooltip: 'Configure Node',
            onPressed: _openEditDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: DeckColors.primaryAccent,
          backgroundColor: DeckColors.surfaceElevated,
          onRefresh: _fetchDeviceTelemetry,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Error Alert if unreachable
                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DeckColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DeckColors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, size: 16, color: DeckColors.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 11, color: DeckColors.error, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Overview Header Card
                _buildOverviewCard(),
                const SizedBox(height: 20),

                // Live Vitals
                VitalsCard(
                  vitals: _vitals,
                  isLoading: _isVitalsLoading,
                  onRefresh: _fetchDeviceTelemetry,
                ),
                const SizedBox(height: 20),

                // Lap-Dog Security Hub
                LapdogCard(
                  status: _lapdogStatus,
                  isToggling: _isLapdogToggling,
                  onToggleAway: _handleToggleAway,
                ),
                const SizedBox(height: 20),

                // One-Touch Controls
                QuickControlsCard(
                  isExecuting: _isExecutingAction,
                  executingLabel: _executingLabel,
                  onTrigger: _handleTriggerAction,
                ),
                const SizedBox(height: 20),

                // Process Manager
                ProcessManagerCard(
                  processes: _processes,
                  isLoading: _isProcessLoading,
                  onKillProcess: _handleKillProcess,
                  onRefresh: _fetchDeviceTelemetry,
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (_currentHost.os) {
                  HostOs.linux => Icons.terminal,
                  HostOs.windows => Icons.window,
                  HostOs.macos => Icons.laptop_mac,
                },
                size: 24,
                color: DeckColors.primaryAccent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentHost.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _currentHost.description ?? 'Workstation node',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeckColors.mutedText),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _currentHost.isOnline
                      ? DeckColors.healthy.withValues(alpha: 0.12)
                      : DeckColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _currentHost.isOnline ? '${_currentHost.pingMs ?? 50} ms' : 'Offline',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _currentHost.isOnline ? DeckColors.healthy : DeckColors.error,
                  ),
                ),
              ),
            ],
          ),
          const Divider(color: DeckColors.borderSubtle, height: 24),
          _buildDetailRow('Tailscale Mesh IP', _currentHost.tailscaleIp),
          if (_currentHost.directIp != null) ...[
            const SizedBox(height: 8),
            _buildDetailRow('Local LAN Route', _currentHost.directIp!),
          ],
          const SizedBox(height: 8),
          _buildDetailRow('SSH User & Port', '${_currentHost.username} (Port ${_currentHost.port})'),
          const SizedBox(height: 8),
          _buildDetailRow(
            'Auth Strategy',
            _currentHost.authMethod == AuthMethod.privateKey
                ? 'Ed25519 Keystore Key'
                : (_currentHost.authMethod == AuthMethod.password ? 'Password Auth' : 'Tailscale SSH'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeckColors.secondaryText),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: DeckColors.primaryText,
          ),
        ),
      ],
    );
  }
}
