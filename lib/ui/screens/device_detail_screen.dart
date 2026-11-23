import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';
import '../../models/vitals_data.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../services/terminal_session_controller.dart';
import '../../services/connector_service.dart';
import '../widgets/vitals_card.dart';
import '../widgets/lapdog_card.dart';
import '../widgets/process_manager_card.dart';
import '../widgets/quick_controls_card.dart';
import 'ai_chat_screen.dart';
import 'host_config_dialog.dart';
import 'remote_file_explorer_screen.dart';
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
    final cmd = target.os == HostOs.windows
        ? 'if (Get-Command lapdog -ErrorAction SilentlyContinue) { lapdog $modeArg } else { Write-Error "Lapdog is not installed on Windows."; exit 127 }'
        : 'lapdog $modeArg 2>/dev/null || ~/.local/bin/lapdog $modeArg 2>/dev/null';

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
      command: target.killProcessCommand(proc.pid),
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

  void _openFileExplorer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => RemoteFileExplorerScreen(
          host: _currentHost,
          sshService: widget.sshService,
          storageService: widget.storage,
        ),
      ),
    );
  }

  Future<void> _checkLockState() async {
    final secret = await widget.storage.getHostCredential(_currentHost.id);
    final isLocked = await widget.sshService.checkWorkstationLockState(
      _currentHost,
      secret: secret,
    );
    if (!mounted) return;
    setState(() {
      _vitals = _vitals.copyWith(isScreenLocked: isLocked);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: DeckColors.surfaceElevated,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        content: Text(
          isLocked == true
              ? '${_currentHost.name} session is LOCKED'
              : (isLocked == false
                  ? '${_currentHost.name} session is UNLOCKED'
                  : 'Unable to determine session lock state on ${_currentHost.name}'),
          style: TextStyle(
            color: isLocked == true ? DeckColors.healthy : DeckColors.primaryAccent,
          ),
        ),
      ),
    );
  }

  void _openScreengrab() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ScreengrabBottomSheet(
        host: _currentHost,
        sshService: widget.sshService,
        storage: widget.storage,
        isLocked: _vitals.isScreenLocked,
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
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.folder_open, size: 20),
            tooltip: 'Remote Files',
            onPressed: _openFileExplorer,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.screenshot_monitor, size: 20),
            tooltip: 'Workstation Display',
            onPressed: _openScreengrab,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            icon: const Icon(Icons.terminal, size: 20),
            tooltip: 'Open Terminal',
            onPressed: _openTerminal,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
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
          // Action Buttons: Terminal, File Explorer, Display, AI Console
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openTerminal,
                  icon: const Icon(Icons.terminal, size: 16),
                  label: const Text('Terminal'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DeckColors.surfaceElevated,
                    foregroundColor: DeckColors.primaryAccent,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: DeckColors.borderSubtle),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openFileExplorer,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Files'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DeckColors.surfaceElevated,
                    foregroundColor: DeckColors.informational,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: DeckColors.borderSubtle),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _openScreengrab,
                  icon: const Icon(Icons.screenshot_monitor, size: 16),
                  label: const Text('Display'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DeckColors.surfaceElevated,
                    foregroundColor: DeckColors.healthy,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: DeckColors.borderSubtle),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AiChatScreen(
                          initialHost: _currentHost,
                          availableHosts: widget.storage.loadHosts(),
                          storage: widget.storage,
                          connectorService: ConnectorService(),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.smart_toy_outlined, size: 16),
                  label: const Text('AI Console'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DeckColors.surfaceElevated,
                    foregroundColor: DeckColors.primaryAccent,
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: const BorderSide(color: DeckColors.borderSubtle),
                    ),
                  ),
                ),
              ),
            ],
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
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Workstation Session Lock',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DeckColors.secondaryText,
                    ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: (_vitals.isScreenLocked == true
                              ? DeckColors.healthy
                              : (_vitals.isScreenLocked == false
                                  ? DeckColors.primaryAccent
                                  : DeckColors.mutedText))
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _vitals.isScreenLocked == true
                          ? 'Session Locked'
                          : (_vitals.isScreenLocked == false
                              ? 'Session Unlocked'
                              : 'Unverified'),
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _vitals.isScreenLocked == true
                            ? DeckColors.healthy
                            : (_vitals.isScreenLocked == false
                                ? DeckColors.primaryAccent
                                : DeckColors.mutedText),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _checkLockState,
                    borderRadius: BorderRadius.circular(4),
                    child: const Padding(
                      padding: EdgeInsets.all(2.0),
                      child: Icon(
                        Icons.sync,
                        size: 14,
                        color: DeckColors.secondaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(color: DeckColors.borderSubtle, height: 24),
          // Secondary Technical Identifiers
          _buildDetailRow(
            'Tailscale Mesh IP',
            _currentHost.tailscaleIp,
            copyValue: _currentHost.tailscaleIp,
          ),
          if (_currentHost.directIp != null) ...[
            const SizedBox(height: 8),
            _buildDetailRow(
              'Local LAN Route',
              _currentHost.directIp!,
              copyValue: _currentHost.directIp!,
            ),
          ],
          const SizedBox(height: 8),
          _buildDetailRow(
            'SSH User & Port',
            '${_currentHost.username} (Port ${_currentHost.port})',
            copyValue:
                'ssh -p ${_currentHost.port} ${_currentHost.username}@${_currentHost.tailscaleIp}',
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

  Widget _buildDetailRow(
    String label,
    String value, {
    Color? valueColor,
    String? copyValue,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: DeckColors.secondaryText,
              ),
        ),
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: copyValue == null
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  Clipboard.setData(ClipboardData(text: copyValue));
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: Text('Copied $label ($copyValue)'),
                        duration: const Duration(milliseconds: 1400),
                      ),
                    );
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: valueColor ?? DeckColors.primaryText,
                      ),
                ),
                if (copyValue != null) ...[
                  const SizedBox(width: 5),
                  const Icon(
                    Icons.copy_rounded,
                    size: 11,
                    color: DeckColors.mutedText,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScreengrabBottomSheet extends StatefulWidget {
  final HostTarget host;
  final SshService sshService;
  final StorageService storage;
  final bool? isLocked;

  const _ScreengrabBottomSheet({
    required this.host,
    required this.sshService,
    required this.storage,
    this.isLocked,
  });

  @override
  State<_ScreengrabBottomSheet> createState() => _ScreengrabBottomSheetState();
}

class _ScreengrabBottomSheetState extends State<_ScreengrabBottomSheet> {
  bool _isLoading = true;
  Uint8List? _imageBytes;
  String? _error;
  DateTime? _capturedAt;

  @override
  void initState() {
    super.initState();
    _capture();
  }

  Future<void> _capture() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final secret = await widget.storage.getHostCredential(widget.host.id);
      final bytes = await widget.sshService.captureScreengrab(
        widget.host,
        secret: secret,
      );

      if (!mounted) return;
      if (bytes == null || bytes.isEmpty) {
        bool isLocked = widget.isLocked == true;
        if (!isLocked) {
          final liveLock = await widget.sshService.checkWorkstationLockState(
            widget.host,
            secret: secret,
          );
          if (liveLock == true) isLocked = true;
        }
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _error = isLocked
              ? 'Workstation session is locked. Graphical display capture is suppressed by the OS lock screen.'
              : 'Unable to capture remote workstation display. Please verify that a graphical user session (X11/Wayland/Windows Desktop) is running.';
        });
      } else {
        setState(() {
          _imageBytes = bytes;
          _capturedAt = DateTime.now();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Capture error: $e';
      });
    }
  }

  Future<void> _shareImage() async {
    if (_imageBytes == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/lapdeck_screengrab_${widget.host.name}.jpg');
      await file.writeAsBytes(_imageBytes!);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text:
              'Workstation display from ${widget.host.name} (${DateFormat.Hms().format(_capturedAt ?? DateTime.now())})',
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: DeckColors.borderMedium, width: 1),
          left: BorderSide(color: DeckColors.borderMedium, width: 1),
          right: BorderSide(color: DeckColors.borderMedium, width: 1),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: DeckColors.borderMedium,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(Icons.screenshot_monitor, size: 20, color: DeckColors.healthy),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Workstation Display · ${widget.host.name}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: DeckColors.primaryText,
                      ),
                ),
              ),
              if (_capturedAt != null)
                Text(
                  DateFormat.Hms().format(_capturedAt!),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: DeckColors.mutedText,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 18, color: DeckColors.mutedText),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DeckColors.primaryAccent,
                        ),
                        SizedBox(height: 14),
                        Text(
                          'Capturing remote display...',
                          style: TextStyle(color: DeckColors.secondaryText, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.screen_lock_portrait, size: 40, color: DeckColors.warning),
                              const SizedBox(height: 12),
                              Text(
                                'Capture Unavailable',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: DeckColors.primaryText,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 12, color: DeckColors.secondaryText),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: DeckColors.surfaceElevated,
                                  foregroundColor: DeckColors.primaryAccent,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: _capture,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Retry Capture'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: DeckColors.background,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: DeckColors.borderSubtle),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Center(
                          child: InteractiveViewer(
                            panEnabled: true,
                            scaleEnabled: true,
                            minScale: 0.5,
                            maxScale: 4.0,
                            child: Image.memory(
                              _imageBytes!,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
          ),
          const SizedBox(height: 12),
          if (!_isLoading && _imageBytes != null)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: DeckColors.primaryText,
                      side: const BorderSide(color: DeckColors.borderSubtle),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: _capture,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DeckColors.primaryAccent,
                      foregroundColor: DeckColors.background,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      minimumSize: const Size.fromHeight(44),
                    ),
                    onPressed: _shareImage,
                    icon: const Icon(Icons.share, size: 16),
                    label: const Text('Share / Save'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
