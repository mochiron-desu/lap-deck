import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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
import 'terminal_tab.dart';

class DeviceDetailScreen extends StatefulWidget {
  final HostTarget host;
  final bool isGlobalTarget;
  final StorageService storage;
  final SshService sshService;
  final TerminalSessionController terminalController;
  final VoidCallback onUpdated;
  final VoidCallback? onSelectAsTarget;
  final Function(TelemetryBundle bundle)? onTelemetryUpdated;

  const DeviceDetailScreen({
    super.key,
    required this.host,
    this.isGlobalTarget = false,
    required this.storage,
    required this.sshService,
    required this.terminalController,
    required this.onUpdated,
    this.onSelectAsTarget,
    this.onTelemetryUpdated,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late HostTarget _currentHost;
  late bool _isGlobalTarget;
  VitalsData _vitals = VitalsData.empty();
  List<ProcessItem> _processes = [];
  LapdogStatus _lapdogStatus = const LapdogStatus();

  bool _isVitalsLoading = false;
  bool _isProcessLoading = false;
  bool _isLapdogToggling = false;
  bool _isExecutingAction = false;
  String? _executingLabel;
  OperationFeedback? _operationFeedback;

  @override
  void initState() {
    super.initState();
    _currentHost = widget.host;
    _isGlobalTarget = widget.isGlobalTarget;
    _fetchDeviceTelemetry();
  }

  Future<void> _fetchDeviceTelemetry() async {
    final target = _currentHost;
    setState(() {
      _isVitalsLoading = true;
      _isProcessLoading = true;
      _currentHost = _currentHost.copyWith(
        peerStatus: PeerStatus.connecting,
        sshStatus: ServiceStatus.connecting,
      );
    });

    try {
      // 1. Check live reachability for this specific device
      final reach = await widget.sshService.checkReachability(target);

      if (!reach.isOnline) {
        if (mounted) {
          setState(() {
            _currentHost = _currentHost.copyWith(
              isOnline: false,
              peerStatus: reach.peerStatus,
              sshStatus: ServiceStatus.unavailable,
              agentStatus: ServiceStatus.unavailable,
              lapdogDaemonStatus: ServiceStatus.unavailable,
              clearPing: true,
              lastChecked: reach.checkedAt,
              lastError: reach.errorDetail,
            );
          });
        }
        return;
      }

      if (reach.sshPortStatus != ServiceStatus.available) {
        if (mounted) {
          setState(() {
            _currentHost = _currentHost.copyWith(
              isOnline: true,
              peerStatus: PeerStatus.online,
              sshStatus: ServiceStatus.unavailable,
              agentStatus: ServiceStatus.unavailable,
              lapdogDaemonStatus: ServiceStatus.unavailable,
              pingMs: reach.latencyMs,
              isDirect: reach.isDirect,
              lastChecked: reach.checkedAt,
              lastError: reach.errorDetail,
            );
          });
        }
        return;
      }

      // 2. Fetch telemetry bundle over SSH
      final secret = await widget.storage.getHostCredential(target.id);
      final bundle = await widget.sshService.fetchTelemetryBundle(
        target,
        secret: secret,
      );

      if (mounted) {
        setState(() {
          if (bundle != null) {
            _vitals = bundle.vitals;
            _processes = bundle.processes;
            _lapdogStatus = bundle.lapdog;
            _currentHost = _currentHost.copyWith(
              isOnline: true,
              peerStatus: PeerStatus.online,
              sshStatus: ServiceStatus.available,
              agentStatus: ServiceStatus.available,
              lapdogDaemonStatus: bundle.lapdog.isInstalled
                  ? ServiceStatus.available
                  : ServiceStatus.unavailable,
              pingMs: reach.latencyMs,
              isDirect: reach.isDirect,
              lastChecked: bundle.fetchedAt,
              lastConnected: bundle.fetchedAt,
              clearError: true,
            );
            widget.onTelemetryUpdated?.call(bundle);
          } else {
            _currentHost = _currentHost.copyWith(
              isOnline: true,
              peerStatus: PeerStatus.online,
              sshStatus: ServiceStatus.unavailable,
              agentStatus: ServiceStatus.unavailable,
              pingMs: reach.latencyMs,
              isDirect: reach.isDirect,
              lastChecked: DateTime.now(),
              lastError:
                  'Host ${target.name} is reachable on TCP port ${target.port}, but SSH authentication or telemetry failed.',
            );
          }
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
    if (_isLapdogToggling) return;
    final target = _currentHost;
    final opName = enableAway ? 'Arm Away Mode' : 'Disarm Away Mode';

    setState(() {
      _isLapdogToggling = true;
      _operationFeedback = OperationFeedback(
        id: 'away-${DateTime.now().millisecondsSinceEpoch}',
        operationName: opName,
        targetHostId: target.id,
        targetHostName: target.name,
        state: OperationLifecycleState.inProgress,
        summary: 'Updating Lapdog security mode on ${target.name}...',
        timestamp: DateTime.now(),
      );
    });

    final secret = await widget.storage.getHostCredential(target.id);
    final modeArg = enableAway ? 'away' : 'back';
    final cmd =
        'lapdog $modeArg 2>/dev/null || ~/.local/bin/lapdog $modeArg 2>/dev/null';

    final res = await widget.sshService.executeCommand(
      host: target,
      command: cmd,
      privateKeyPem:
          target.authMethod == AuthMethod.privateKey ? secret : null,
      password: target.authMethod == AuthMethod.password ? secret : null,
    );

    if (!mounted) return;

    setState(() {
      _isLapdogToggling = false;
      if (res.isTimeout) {
        _operationFeedback = OperationFeedback(
          id: 'away-${DateTime.now().millisecondsSinceEpoch}',
          operationName: opName,
          targetHostId: target.id,
          targetHostName: target.name,
          state: OperationLifecycleState.resultUnknown,
          summary:
              'Request sent to ${target.name}, but confirmation timed out. Verify state below.',
          timestamp: DateTime.now(),
        );
      } else if (res.isConnectionFailure) {
        _operationFeedback = OperationFeedback(
          id: 'away-${DateTime.now().millisecondsSinceEpoch}',
          operationName: opName,
          targetHostId: target.id,
          targetHostName: target.name,
          state: OperationLifecycleState.targetUnavailable,
          summary: '${target.name} is unreachable over SSH.',
          timestamp: DateTime.now(),
        );
      } else if (res.isSuccess) {
        _lapdogStatus = LapdogStatus(
          isInstalled: true,
          isAwayArmed: enableAway,
          sentHistory: _lapdogStatus.sentHistory,
          pendingEvents: _lapdogStatus.pendingEvents,
          version: _lapdogStatus.version,
          lastChecked: DateTime.now(),
          isVerified: true,
        );
        _operationFeedback = OperationFeedback(
          id: 'away-${DateTime.now().millisecondsSinceEpoch}',
          operationName: opName,
          targetHostId: target.id,
          targetHostName: target.name,
          state: OperationLifecycleState.successful,
          summary:
              'Confirmed on ${target.name}: Lapdog is now ${enableAway ? "Away Armed" : "in Home Mode"}.',
          timestamp: DateTime.now(),
        );
      } else {
        _operationFeedback = OperationFeedback(
          id: 'away-${DateTime.now().millisecondsSinceEpoch}',
          operationName: opName,
          targetHostId: target.id,
          targetHostName: target.name,
          state: OperationLifecycleState.failed,
          summary: 'Failed to update Lapdog mode on ${target.name}.',
          technicalDetails: res.error,
          timestamp: DateTime.now(),
        );
      }
    });

    _fetchDeviceTelemetry();
  }

  Future<void> _handleKillProcess(ProcessItem proc) async {
    final target = _currentHost;
    final secret = await widget.storage.getHostCredential(target.id);
    final res = await widget.sshService.executeCommand(
      host: target,
      command: 'kill -9 ${proc.pid}',
      privateKeyPem:
          target.authMethod == AuthMethod.privateKey ? secret : null,
      password: target.authMethod == AuthMethod.password ? secret : null,
    );

    if (!mounted) return;
    if (res.isSuccess) {
      setState(() {
        _processes.removeWhere((p) => p.pid == proc.pid);
        _operationFeedback = OperationFeedback(
          id: 'kill-${DateTime.now().millisecondsSinceEpoch}',
          operationName: 'Terminate Process',
          targetHostId: target.id,
          targetHostName: target.name,
          state: OperationLifecycleState.successful,
          summary:
              'Terminated ${proc.name} (PID ${proc.pid}) on ${target.name}.',
          timestamp: DateTime.now(),
        );
      });
    } else {
      setState(() {
        _operationFeedback = OperationFeedback(
          id: 'kill-${DateTime.now().millisecondsSinceEpoch}',
          operationName: 'Terminate Process',
          targetHostId: target.id,
          targetHostName: target.name,
          state: res.isTimeout
              ? OperationLifecycleState.resultUnknown
              : OperationLifecycleState.failed,
          summary:
              'Could not verify termination of ${proc.name} (PID ${proc.pid}) on ${target.name}.',
          technicalDetails: res.error,
          timestamp: DateTime.now(),
        );
      });
    }
  }

  Future<void> _handleTriggerAction(
    String actionId,
    String label,
    String command,
  ) async {
    if (_isExecutingAction) return;
    final target = _currentHost;

    setState(() {
      _isExecutingAction = true;
      _executingLabel = label;
      _operationFeedback = OperationFeedback(
        id: 'act-${DateTime.now().millisecondsSinceEpoch}',
        operationName: label,
        targetHostId: target.id,
        targetHostName: target.name,
        state: OperationLifecycleState.inProgress,
        summary: 'Executing $label on ${target.name}...',
        timestamp: DateTime.now(),
      );
    });

    final reach = await widget.sshService.checkReachability(target);
    if (!reach.isOnline || reach.sshPortStatus != ServiceStatus.available) {
      if (mounted) {
        setState(() {
          _isExecutingAction = false;
          _executingLabel = null;
          _operationFeedback = OperationFeedback(
            id: 'act-${DateTime.now().millisecondsSinceEpoch}',
            operationName: label,
            targetHostId: target.id,
            targetHostName: target.name,
            state: OperationLifecycleState.targetUnavailable,
            summary:
                'Cannot execute $label: ${target.name} (${target.tailscaleIp}) is ${reach.peerStatus == PeerStatus.online ? "SSH unavailable" : "unreachable"}.',
            timestamp: DateTime.now(),
          );
        });
      }
      return;
    }

    final secret = await widget.storage.getHostCredential(target.id);
    final res = await widget.sshService.executeCommand(
      host: target,
      command: command,
      privateKeyPem:
          target.authMethod == AuthMethod.privateKey ? secret : null,
      password: target.authMethod == AuthMethod.password ? secret : null,
    );

    if (!mounted) return;

    setState(() {
      _isExecutingAction = false;
      _executingLabel = null;
      if (res.isTimeout) {
        _operationFeedback = OperationFeedback(
          id: 'act-${DateTime.now().millisecondsSinceEpoch}',
          operationName: label,
          targetHostId: target.id,
          targetHostName: target.name,
          state: OperationLifecycleState.resultUnknown,
          summary:
              '$label sent to ${target.name}, but confirmation timed out. Outcome is unknown.',
          technicalDetails: res.error,
          timestamp: DateTime.now(),
        );
      } else if (res.isSuccess) {
        _operationFeedback = OperationFeedback(
          id: 'act-${DateTime.now().millisecondsSinceEpoch}',
          operationName: label,
          targetHostId: target.id,
          targetHostName: target.name,
          state: OperationLifecycleState.successful,
          summary: 'Confirmed: $label completed on ${target.name}.',
          timestamp: DateTime.now(),
        );
      } else {
        _operationFeedback = OperationFeedback(
          id: 'act-${DateTime.now().millisecondsSinceEpoch}',
          operationName: label,
          targetHostId: target.id,
          targetHostName: target.name,
          state: OperationLifecycleState.failed,
          summary: '$label failed on ${target.name}.',
          technicalDetails: res.error,
          timestamp: DateTime.now(),
        );
      }
    });

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

  void _openTerminal() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => TerminalTab(
          hosts: [_currentHost],
          activeHost: _currentHost,
          controller: widget.terminalController,
          storage: widget.storage,
          onSelectHost: (_) {},
        ),
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
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.terminal, size: 20),
            tooltip: 'Open Terminal',
            onPressed: _openTerminal,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: _isVitalsLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DeckColors.primaryAccent,
                    ),
                  )
                : const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh Telemetry',
            onPressed: _isVitalsLoading ? null : _fetchDeviceTelemetry,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
                // Operation Feedback Banner if active
                if (_operationFeedback != null) ...[
                  _buildOperationFeedbackBanner(_operationFeedback!),
                  const SizedBox(height: 14),
                ],

                // Connectivity Issue Alert if subsystem failed
                if (_currentHost.lastError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DeckColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DeckColors.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 16,
                          color: DeckColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _currentHost.lastError!,
                            style: const TextStyle(
                              fontSize: 11,
                              color: DeckColors.error,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Overview Header Card with Independent Health States & Target Selection
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
                  hostName: _currentHost.name,
                  status: _lapdogStatus,
                  isToggling: _isLapdogToggling,
                  onToggleAway: _handleToggleAway,
                ),
                const SizedBox(height: 20),

                // Device Controls explicitly bound to this host
                QuickControlsCard(
                  host: _currentHost,
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

  Widget _buildOperationFeedbackBanner(OperationFeedback op) {
    final Color stateColor = switch (op.state) {
      OperationLifecycleState.ready => DeckColors.informational,
      OperationLifecycleState.inProgress => DeckColors.primaryAccent,
      OperationLifecycleState.successful => DeckColors.healthy,
      OperationLifecycleState.failed => DeckColors.error,
      OperationLifecycleState.timedOut ||
      OperationLifecycleState.resultUnknown =>
        DeckColors.warning,
      OperationLifecycleState.targetUnavailable => DeckColors.error,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: stateColor.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  op.state.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: stateColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${op.operationName} · ${op.targetHostName}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: DeckColors.primaryText,
                      ),
                ),
              ),
              if (!op.isBusy)
                IconButton(
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.close,
                    size: 15,
                    color: DeckColors.mutedText,
                  ),
                  onPressed: () => setState(() => _operationFeedback = null),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            op.summary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DeckColors.secondaryText,
                ),
          ),
          if (op.technicalDetails != null &&
              op.technicalDetails!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              op.technicalDetails!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: DeckColors.mutedText,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewCard() {
    final reachColor = switch (_currentHost.peerStatus) {
      PeerStatus.online => DeckColors.healthy,
      PeerStatus.connecting => DeckColors.informational,
      PeerStatus.unreachable || PeerStatus.offline => DeckColors.error,
      PeerStatus.unknown => DeckColors.mutedText,
    };

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
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          _currentHost.name,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        if (_isGlobalTarget)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: DeckColors.primaryAccent
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Selected',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: DeckColors.primaryAccent,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_currentHost.osDisplayName} · ${_currentHost.roleDisplayName}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DeckColors.secondaryText,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: reachColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _currentHost.hasFreshLatency
                      ? '${_currentHost.reachabilityLabel} · ${_currentHost.pingMs} ms'
                      : _currentHost.reachabilityLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: reachColor,
                      ),
                ),
              ),
            ],
          ),
          if (!_isGlobalTarget && widget.onSelectAsTarget != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  widget.onSelectAsTarget!();
                  setState(() => _isGlobalTarget = true);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Global target updated to ${_currentHost.name}',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.ads_click, size: 16),
                label: Text('Set ${_currentHost.name} as Global Target'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: DeckColors.primaryAccent,
                  side: const BorderSide(color: DeckColors.primaryAccent),
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openTerminal,
              icon: const Icon(Icons.terminal, size: 16),
              label: Text('Open Terminal on ${_currentHost.name}'),
              style: ElevatedButton.styleFrom(
                backgroundColor: DeckColors.surfaceElevated,
                foregroundColor: DeckColors.primaryAccent,
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: DeckColors.borderSubtle),
                ),
              ),
            ),
          ),
          const Divider(color: DeckColors.borderSubtle, height: 24),
          // Independent Health States
          _buildDetailRow(
            'Host Reachability',
            _currentHost.reachabilityLabel,
            valueColor: reachColor,
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            'SSH Service',
            _currentHost.sshStatusLabel,
            valueColor: _serviceColor(_currentHost.sshStatus),
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            'LAPDECK Telemetry Agent',
            _currentHost.agentStatusLabel,
            valueColor: _serviceColor(_currentHost.agentStatus),
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            'Lapdog Security Daemon',
            _currentHost.lapdogStatusLabel,
            valueColor: _serviceColor(_currentHost.lapdogDaemonStatus),
          ),
          const Divider(color: DeckColors.borderSubtle, height: 24),
          // Secondary Technical Identifiers
          _buildDetailRow('Tailscale Mesh IP', _currentHost.tailscaleIp),
          if (_currentHost.directIp != null) ...[
            const SizedBox(height: 8),
            _buildDetailRow('Local LAN Route', _currentHost.directIp!),
          ],
          const SizedBox(height: 8),
          _buildDetailRow(
            'SSH User & Port',
            '${_currentHost.username} (Port ${_currentHost.port})',
          ),
          const SizedBox(height: 8),
          _buildDetailRow(
            'Auth Strategy',
            _currentHost.authMethod == AuthMethod.privateKey
                ? 'Ed25519 Keystore Key'
                : (_currentHost.authMethod == AuthMethod.password
                    ? 'Password Auth'
                    : 'Tailscale SSH'),
          ),
          if (_currentHost.lastChecked != null) ...[
            const SizedBox(height: 8),
            _buildDetailRow(
              'Last Health Check',
              DateFormat('HH:mm:ss').format(_currentHost.lastChecked!),
            ),
          ],
        ],
      ),
    );
  }

  Color _serviceColor(ServiceStatus s) {
    return switch (s) {
      ServiceStatus.available => DeckColors.healthy,
      ServiceStatus.connecting => DeckColors.informational,
      ServiceStatus.unavailable => DeckColors.error,
      ServiceStatus.unknown => DeckColors.mutedText,
    };
  }

  Widget _buildDetailRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: DeckColors.secondaryText,
              ),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: valueColor ?? DeckColors.primaryText,
              ),
        ),
      ],
    );
  }
}
