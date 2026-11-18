import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';
import '../../models/vitals_data.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../services/terminal_session_controller.dart';
import 'device_detail_screen.dart';
import 'host_config_dialog.dart';

class HomeTab extends StatefulWidget {
  final List<HostTarget> hosts;
  final HostTarget? activeHost;
  final VitalsData vitals;
  final LapdogStatus lapdogStatus;
  final bool isVitalsLoading;
  final bool localTailscaleActive;
  final DateTime? lastNetworkCheckAt;
  final StorageService storage;
  final SshService sshService;
  final TerminalSessionController terminalController;
  final Function(HostTarget) onSelectHost;
  final VoidCallback onRefresh;
  final Function(int tabIndex) onNavigateTab;
  final VoidCallback onHostsUpdated;
  final Function(String hostId, TelemetryBundle bundle) onTelemetryUpdated;

  const HomeTab({
    super.key,
    required this.hosts,
    required this.activeHost,
    required this.vitals,
    required this.lapdogStatus,
    required this.isVitalsLoading,
    required this.localTailscaleActive,
    required this.lastNetworkCheckAt,
    required this.storage,
    required this.sshService,
    required this.terminalController,
    required this.onSelectHost,
    required this.onRefresh,
    required this.onNavigateTab,
    required this.onHostsUpdated,
    required this.onTelemetryUpdated,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  // Active contextual operation feedback (retains original target identity)
  OperationFeedback? _operationFeedback;
  final Set<String> _inFlightKeys = {};

  //Connectivity alert UI state (dismissal hides presentation without changing system state)
  String? _dismissedAlertSignature;
  bool _isAlertExpanded = false;

  String _formatTime(DateTime? dt) {
    if (dt == null) return 'Not checked yet';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 15) return 'Checked just now';
    if (diff.inMinutes < 1) return 'Checked ${diff.inSeconds}s ago';
    return 'Checked ${DateFormat('HH:mm:ss').format(dt)}';
  }

  void _openAddDeviceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => HostConfigDialog(
        onSave: (newHost, secret) async {
          final list = List<HostTarget>.from(widget.hosts)..add(newHost);
          await widget.storage.saveHosts(list);
          if (secret != null) {
            await widget.storage.saveHostCredential(newHost.id, secret);
          }
          widget.onHostsUpdated();
          widget.onSelectHost(newHost);
        },
      ),
    );
  }

  /// Opens the Target Device Selector bottom sheet (Section 1).
  void _showTargetSelectorSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: DeckColors.surfaceSecondary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: DeckColors.borderSubtle, width: 1),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(
                      Icons.ads_click,
                      size: 18,
                      color: DeckColors.primaryAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Select Target Device',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(sheetCtx).pop();
                        _openAddDeviceDialog();
                      },
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('Add device'),
                      style: TextButton.styleFrom(
                        foregroundColor: DeckColors.primaryAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'All quick actions on the Home screen will execute against the selected target machine.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DeckColors.secondaryText,
                      ),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.55,
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.hosts.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (ctx, i) {
                      final host = widget.hosts[i];
                      final isSelected = host.id == widget.activeHost?.id;
                      return _buildSelectorSheetItem(sheetCtx, host, isSelected);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSelectorSheetItem(
    BuildContext sheetCtx,
    HostTarget host,
    bool isSelected,
  ) {
    final statusColor = _peerStatusColor(host);
    final statusText = _peerStatusSummary(host);

    return Material(
      color: isSelected ? DeckColors.surfaceElevated : DeckColors.background,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          widget.onSelectHost(host);
          Navigator.of(sheetCtx).pop();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? DeckColors.primaryAccent.withValues(alpha: 0.45)
                  : DeckColors.borderSubtle,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
                color: isSelected
                    ? DeckColors.primaryAccent
                    : DeckColors.mutedText,
              ),
              const SizedBox(width: 12),
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
                          host.name,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: DeckColors.primaryText,
                                  ),
                        ),
                        if (isSelected) _buildSelectedBadge(),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${host.osDisplayName} · ${host.tailscaleIp}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DeckColors.secondaryText,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 11,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  if (host.hasFreshLatency) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${host.pingMs} ms',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: DeckColors.secondaryText,
                          ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the Terminal Quick Action sheet / navigates to Terminal tab (Section 2: Terminal).
  void _handleTerminalQuickAction() {
    final target = widget.activeHost;
    if (target == null) return;

    // If a reusable active session already exists for this exact target, go directly to it.
    if (widget.terminalController.hasActiveSessionFor(target)) {
      setState(() {
        _operationFeedback = OperationFeedback(
          id: 'term-${DateTime.now().millisecondsSinceEpoch}',
          operationName: 'Terminal Session',
          targetHostId: target.id,
          targetHostName: target.name,
          state: OperationLifecycleState.successful,
          summary:
              'Reusing active PTY session on ${target.name} (${target.tailscaleIp}).',
          timestamp: DateTime.now(),
        );
      });
      widget.onNavigateTab(2);
      return;
    }

    // Before connecting, display target identity and connection state.
    showModalBottomSheet(
      context: context,
      backgroundColor: DeckColors.surfaceSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: DeckColors.borderSubtle, width: 1),
      ),
      builder: (sheetCtx) {
        final hasOtherSession = widget.terminalController.isConnected &&
            widget.terminalController.connectedHost != null &&
            widget.terminalController.connectedHost!.id != target.id;
        final otherHost = widget.terminalController.connectedHost;
        final canConnect = target.peerStatus != PeerStatus.unreachable &&
            target.peerStatus != PeerStatus.offline;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.terminal,
                      size: 20,
                      color: DeckColors.primaryAccent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Open Terminal on ${target.name}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildSheetTargetSummaryCard(target),
                if (hasOtherSession && otherHost != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DeckColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DeckColors.warning.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline,
                          size: 16,
                          color: DeckColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'An active terminal session is currently connected to ${otherHost.name}. Connecting to ${target.name} will replace that session.',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: DeckColors.primaryText,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!canConnect) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DeckColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DeckColors.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      '${target.name} is currently ${target.reachabilityLabel.toLowerCase()} (${target.tailscaleIp}). SSH connection may fail until the host is reachable.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DeckColors.error,
                          ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: DeckColors.secondaryText,
                          side: const BorderSide(color: DeckColors.borderSubtle),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(sheetCtx).pop();
                          widget.onNavigateTab(2);
                          final secret = await widget.storage
                              .getHostCredential(target.id);
                          await widget.terminalController.connect(
                            target,
                            secret: secret,
                            forceReconnect: hasOtherSession,
                          );
                        },
                        icon: const Icon(Icons.login, size: 18),
                        label: Text('Connect to ${target.name}'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: DeckColors.primaryAccent,
                          foregroundColor: DeckColors.background,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Opens the context-aware Diagnostics Bottom Sheet (Section 2: Diagnostics).
  void _handleDiagnosticsQuickAction() {
    final target = widget.activeHost;
    if (target == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: DeckColors.surfaceSecondary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: DeckColors.borderSubtle, width: 1),
      ),
      builder: (sheetCtx) {
        return _DiagnosticsBottomSheet(
          targetHost: target,
          storage: widget.storage,
          sshService: widget.sshService,
          onTelemetryUpdated: (bundle) {
            widget.onTelemetryUpdated(target.id, bundle);
          },
          onRefreshGlobal: widget.onRefresh,
          onOperationStateChanged: (feedback) {
            if (mounted) {
              setState(() => _operationFeedback = feedback);
            }
          },
        );
      },
    );
  }

  /// Opens the Arm/Disarm Away confirmation sheet and executes against captured target (Section 2: Arm Away).
  void _handleArmAwayQuickAction() {
    final target = widget.activeHost;
    if (target == null) return;

    final opKey = 'away-${target.id}';
    if (_inFlightKeys.contains(opKey)) return;

    // Determine current security state for this target
    final isCurrentlyArmed = widget.lapdogStatus.isAwayArmed;
    final desiredArmState = !isCurrentlyArmed;
    final actionTitle =
        desiredArmState ? 'Arm Away Mode' : 'Disarm Away Mode';

    showModalBottomSheet(
      context: context,
      backgroundColor: DeckColors.surfaceSecondary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: DeckColors.borderSubtle, width: 1),
      ),
      builder: (sheetCtx) {
        final isUnreachable = target.peerStatus == PeerStatus.unreachable ||
            target.peerStatus == PeerStatus.offline;
        final isLapdogMissing =
            target.lapdogDaemonStatus == ServiceStatus.unavailable;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      desiredArmState ? Icons.shield : Icons.verified_user,
                      size: 20,
                      color: desiredArmState
                          ? DeckColors.warning
                          : DeckColors.healthy,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '$actionTitle on ${target.name}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildSheetTargetSummaryCard(target),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: DeckColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DeckColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildKeyValueRow(
                        'Current security mode',
                        !widget.lapdogStatus.isVerified
                            ? 'Unverified (${target.lapdogStatusLabel})'
                            : (!widget.lapdogStatus.isInstalled
                                ? 'Lapdog daemon not detected'
                                : (isCurrentlyArmed
                                    ? 'Away Mode (Armed)'
                                    : 'Home Mode (Disarmed)')),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Expected effect:',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: DeckColors.secondaryText,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        desiredArmState
                            ? 'Enables Lapdog Away monitoring on ${target.name}. Failed login attempts will capture webcam photos and dispatch instant Telegram alerts.'
                            : 'Disarms Lapdog Away monitoring on ${target.name} and returns the daemon to normal Home mode.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: DeckColors.primaryText,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ),
                ),
                if (isUnreachable || isLapdogMissing) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DeckColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DeckColors.warning.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      isUnreachable
                          ? '${target.name} is currently ${target.reachabilityLabel.toLowerCase()}. Reachability will be verified before sending the command.'
                          : 'Lapdog daemon was not detected on ${target.name} during the last check. The operation will verify whether lapdog is installed.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DeckColors.warning,
                          ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: DeckColors.secondaryText,
                          side: const BorderSide(color: DeckColors.borderSubtle),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          _executeArmAwayOperation(
                            target: target,
                            enableAway: desiredArmState,
                          );
                        },
                        icon: Icon(
                          desiredArmState ? Icons.shield : Icons.lock_open,
                          size: 18,
                        ),
                        label: Text(
                          desiredArmState
                              ? 'Arm ${target.name}'
                              : 'Disarm ${target.name}',
                        ),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: desiredArmState
                              ? DeckColors.primaryAccent
                              : DeckColors.healthy,
                          foregroundColor: DeckColors.background,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _executeArmAwayOperation({
    required HostTarget target,
    required bool enableAway,
  }) async {
    final opKey = 'away-${target.id}';
    if (_inFlightKeys.contains(opKey)) return;

    final opId = 'op-${DateTime.now().millisecondsSinceEpoch}';
    final opName = enableAway ? 'Arm Away Mode' : 'Disarm Away Mode';

    setState(() {
      _inFlightKeys.add(opKey);
      _operationFeedback = OperationFeedback(
        id: opId,
        operationName: opName,
        targetHostId: target.id,
        targetHostName: target.name,
        state: OperationLifecycleState.inProgress,
        summary: 'Verifying reachability and updating Lapdog mode on ${target.name}...',
        timestamp: DateTime.now(),
      );
    });

    try {
      // 1. Check live reachability of the captured target
      final reach = await widget.sshService.checkReachability(target);
      if (!reach.isOnline || reach.sshPortStatus != ServiceStatus.available) {
        if (mounted) {
          setState(() {
            _operationFeedback = OperationFeedback(
              id: opId,
              operationName: opName,
              targetHostId: target.id,
              targetHostName: target.name,
              state: OperationLifecycleState.targetUnavailable,
              summary:
                  'Cannot execute $opName: ${target.name} (${target.tailscaleIp}) is ${reach.peerStatus == PeerStatus.online ? "SSH unavailable" : "unreachable"}.',
              technicalDetails: reach.errorDetail,
              timestamp: DateTime.now(),
            );
          });
        }
        return;
      }

      // 2. Execute command & query confirmed backend state on target
      final secret = await widget.storage.getHostCredential(target.id);
      final modeArg = enableAway ? 'away' : 'back';
      final cmd = '''
if command -v lapdog >/dev/null 2>&1; then
  lapdog $modeArg && lapdog status
elif [ -x "\$HOME/.local/bin/lapdog" ]; then
  "\$HOME/.local/bin/lapdog" $modeArg && "\$HOME/.local/bin/lapdog" status
else
  echo "LAPDOG_BINARY_MISSING"
  exit 127
fi
''';

      final res = await widget.sshService.executeCommand(
        host: target,
        command: cmd,
        privateKeyPem:
            target.authMethod == AuthMethod.privateKey ? secret : null,
        password: target.authMethod == AuthMethod.password ? secret : null,
      );

      if (!mounted) return;

      if (res.isTimeout) {
        setState(() {
          _operationFeedback = OperationFeedback(
            id: opId,
            operationName: opName,
            targetHostId: target.id,
            targetHostName: target.name,
            state: OperationLifecycleState.resultUnknown,
            summary:
                'Request sent to ${target.name}, but confirmation timed out. Lapdog mode may or may not have changed.',
            technicalDetails: res.error,
            timestamp: DateTime.now(),
          );
        });
        return;
      }

      if (res.output.contains('LAPDOG_BINARY_MISSING') || res.exitCode == 127) {
        setState(() {
          _operationFeedback = OperationFeedback(
            id: opId,
            operationName: opName,
            targetHostId: target.id,
            targetHostName: target.name,
            state: OperationLifecycleState.failed,
            summary:
                'Lapdog security daemon is not installed on ${target.name} (${target.osDisplayName}).',
            timestamp: DateTime.now(),
          );
        });
        return;
      }

      if (!res.isSuccess) {
        setState(() {
          _operationFeedback = OperationFeedback(
            id: opId,
            operationName: opName,
            targetHostId: target.id,
            targetHostName: target.name,
            state: OperationLifecycleState.failed,
            summary: 'Failed to confirm $opName on ${target.name}.',
            technicalDetails:
                res.error.isNotEmpty ? res.error : 'Exit code: ${res.exitCode}',
            timestamp: DateTime.now(),
          );
        });
        return;
      }

      // 3. Refresh telemetry for the target host to reflect confirmed backend state
      final bundle = await widget.sshService.fetchTelemetryBundle(
        target,
        secret: secret,
      );
      if (bundle != null && mounted) {
        widget.onTelemetryUpdated(target.id, bundle);
      }

      final confirmedArmed = bundle?.lapdog.isAwayArmed ??
          res.output.toUpperCase().contains('ARMED');

      if (mounted) {
        setState(() {
          _operationFeedback = OperationFeedback(
            id: opId,
            operationName: opName,
            targetHostId: target.id,
            targetHostName: target.name,
            state: confirmedArmed == enableAway
                ? OperationLifecycleState.successful
                : OperationLifecycleState.resultUnknown,
            summary: confirmedArmed == enableAway
                ? 'Confirmed on ${target.name}: Lapdog is now in ${confirmedArmed ? "Away Armed" : "Home"} mode.'
                : 'Command completed on ${target.name}, but Lapdog reported mode: ${confirmedArmed ? "Away Armed" : "Home"}.',
            timestamp: DateTime.now(),
          );
        });
      }
    } finally {
      if (mounted) {
        setState(() => _inFlightKeys.remove(opKey));
      }
    }
  }

  /// Opens contextual confirmation sheet for locking the remote session (Section 2: Lock Device).
  void _handleLockDeviceQuickAction() {
    final target = widget.activeHost;
    if (target == null) return;

    final opKey = 'lock-${target.id}';
    if (_inFlightKeys.contains(opKey)) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: DeckColors.surfaceSecondary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: DeckColors.borderSubtle, width: 1),
      ),
      builder: (sheetCtx) {
        final isUnreachable = target.peerStatus == PeerStatus.unreachable ||
            target.peerStatus == PeerStatus.offline;

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.lock_outline,
                      size: 20,
                      color: DeckColors.primaryAccent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${target.lockActionTitle} on ${target.name}',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _buildSheetTargetSummaryCard(target),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: DeckColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: DeckColors.borderSubtle),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildKeyValueRow('Operation', target.lockActionTitle),
                      const SizedBox(height: 6),
                      _buildKeyValueRow('Target machine', target.name),
                      const SizedBox(height: 8),
                      Text(
                        'Consequence:',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: DeckColors.secondaryText,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        target.lockConsequenceDescription,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: DeckColors.primaryText,
                              height: 1.4,
                            ),
                      ),
                    ],
                  ),
                ),
                if (isUnreachable) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DeckColors.error.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: DeckColors.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Text(
                      '${target.name} is currently ${target.reachabilityLabel.toLowerCase()} (${target.tailscaleIp}). The session cannot be locked unless the host is reachable over SSH.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DeckColors.error,
                          ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetCtx).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: DeckColors.secondaryText,
                          side: const BorderSide(color: DeckColors.borderSubtle),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          _executeLockSessionOperation(target);
                        },
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: Text('Lock ${target.name}'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: DeckColors.primaryAccent,
                          foregroundColor: DeckColors.background,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Executes remote lock operation with full 6-step lifecycle feedback (Section 6 & Section 8).
  Future<void> _executeLockSessionOperation(HostTarget target) async {
    final opKey = 'lock-${target.id}';
    if (_inFlightKeys.contains(opKey)) return;

    final opId = 'lock-${DateTime.now().millisecondsSinceEpoch}';
    final opName = target.lockActionTitle;

    setState(() {
      _inFlightKeys.add(opKey);
      _operationFeedback = OperationFeedback(
        id: opId,
        operationName: opName,
        targetHostId: target.id,
        targetHostName: target.name,
        state: OperationLifecycleState.inProgress,
        summary:
            'Checking SSH connectivity and sending lock command to ${target.name}...',
        timestamp: DateTime.now(),
      );
    });

    try {
      // Steps 1-3: Identify target, validate support, check relevant connectivity
      final reach = await widget.sshService.checkReachability(target);
      if (!reach.isOnline || reach.sshPortStatus != ServiceStatus.available) {
        if (mounted) {
          setState(() {
            _operationFeedback = OperationFeedback(
              id: opId,
              operationName: opName,
              targetHostId: target.id,
              targetHostName: target.name,
              state: OperationLifecycleState.targetUnavailable,
              summary:
                  '${target.name} WAS NOT LOCKED: Host is ${reach.peerStatus == PeerStatus.online ? "SSH unavailable" : "unreachable"} (${target.tailscaleIp}).',
              technicalDetails: reach.errorDetail,
              timestamp: DateTime.now(),
            );
          });
        }
        return;
      }

      // Step 4: Execute the request against captured target
      final secret = await widget.storage.getHostCredential(target.id);
      final res = await widget.sshService.executeCommand(
        host: target,
        command: target.lockSessionCommand,
        privateKeyPem:
            target.authMethod == AuthMethod.privateKey ? secret : null,
        password: target.authMethod == AuthMethod.password ? secret : null,
        executionTimeout: const Duration(seconds: 6),
      );

      if (!mounted) return;

      // Step 5 & 6: Handle timeout uncertainty vs failure vs confirmed outcome
      if (res.isTimeout) {
        setState(() {
          _operationFeedback = OperationFeedback(
            id: opId,
            operationName: opName,
            targetHostId: target.id,
            targetHostName: target.name,
            state: OperationLifecycleState.resultUnknown,
            summary:
                'Lock request timed out on ${target.name}. Outcome is unknown — the remote session may or may not have locked.',
            technicalDetails: res.error,
            timestamp: DateTime.now(),
          );
        });
        return;
      }

      if (res.isConnectionFailure || !res.isSuccess) {
        setState(() {
          _operationFeedback = OperationFeedback(
            id: opId,
            operationName: opName,
            targetHostId: target.id,
            targetHostName: target.name,
            state: OperationLifecycleState.failed,
            summary:
                '${target.name} was NOT locked. The remote command failed (exit ${res.exitCode}).',
            technicalDetails:
                res.error.isNotEmpty ? res.error : 'No session manager responded.',
            timestamp: DateTime.now(),
          );
        });
        return;
      }

      setState(() {
        _operationFeedback = OperationFeedback(
          id: opId,
          operationName: opName,
          targetHostId: target.id,
          targetHostName: target.name,
          state: OperationLifecycleState.successful,
          summary:
              'Confirmed: ${target.lockActionTitle} completed on ${target.name} (${res.connectedEndpoint} in ${res.duration.inMilliseconds} ms).',
          timestamp: DateTime.now(),
        );
      });
    } finally {
      if (mounted) {
        setState(() => _inFlightKeys.remove(opKey));
      }
    }
  }

  /// Verifies actual device state after a timeout or uncertain operation (Section 6).
  Future<void> _verifyTargetState(String hostId) async {
    HostTarget? target;
    for (final h in widget.hosts) {
      if (h.id == hostId) {
        target = h;
        break;
      }
    }
    if (target == null) return;

    setState(() {
      _operationFeedback = OperationFeedback(
        id: 'verify-${DateTime.now().millisecondsSinceEpoch}',
        operationName: 'State Verification',
        targetHostId: target!.id,
        targetHostName: target.name,
        state: OperationLifecycleState.inProgress,
        summary: 'Verifying live reachability and service state on ${target.name}...',
        timestamp: DateTime.now(),
      );
    });

    final reach = await widget.sshService.checkReachability(target);
    if (!reach.isOnline || reach.sshPortStatus != ServiceStatus.available) {
      if (mounted) {
        setState(() {
          _operationFeedback = OperationFeedback(
            id: 'verify-${DateTime.now().millisecondsSinceEpoch}',
            operationName: 'State Verification',
            targetHostId: target!.id,
            targetHostName: target.name,
            state: OperationLifecycleState.targetUnavailable,
            summary:
                'Verification result for ${target.name}: Host is ${reach.peerStatus == PeerStatus.online ? "Online, but SSH is Unavailable" : "Unreachable"}.',
            technicalDetails: reach.errorDetail,
            timestamp: DateTime.now(),
          );
        });
      }
      return;
    }

    final secret = await widget.storage.getHostCredential(target.id);
    final bundle = await widget.sshService.fetchTelemetryBundle(
      target,
      secret: secret,
    );
    if (bundle != null && mounted) {
      widget.onTelemetryUpdated(target.id, bundle);
      setState(() {
        _operationFeedback = OperationFeedback(
          id: 'verify-${DateTime.now().millisecondsSinceEpoch}',
          operationName: 'State Verification',
          targetHostId: target!.id,
          targetHostName: target.name,
          state: OperationLifecycleState.successful,
          summary:
              'Verified ${target.name}: Host online (${reach.latencyMs ?? "--"} ms), SSH available, Lapdog ${bundle.lapdog.isInstalled ? (bundle.lapdog.isAwayArmed ? "Away Armed" : "Home Mode") : "Unavailable"}.',
          timestamp: DateTime.now(),
        );
      });
    } else if (mounted) {
      setState(() {
        _operationFeedback = OperationFeedback(
          id: 'verify-${DateTime.now().millisecondsSinceEpoch}',
          operationName: 'State Verification',
          targetHostId: target!.id,
          targetHostName: target.name,
          state: OperationLifecycleState.failed,
          summary:
              '${target.name} is reachable on TCP port ${target.port}, but SSH telemetry verification failed.',
          timestamp: DateTime.now(),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.activeHost;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // 1. Application Header
            _buildAppHeader(),

            // Scrollable Home Content following Section 5 Hierarchy
            Expanded(
              child: RefreshIndicator(
                color: DeckColors.primaryAccent,
                backgroundColor: DeckColors.surfaceElevated,
                onRefresh: () async => widget.onRefresh(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 2. Important Connectivity Alerts (compact & dismissible)
                      if (active != null) _buildConnectivityAlert(active),

                      // 3. Network Overview
                      _buildNetworkOverviewCard(active),
                      const SizedBox(height: 16),

                      // 4. Target Device Selector (directly above Quick Actions)
                      if (active != null) ...[
                        _buildTargetDeviceSelectorCard(active),
                        const SizedBox(height: 16),
                      ],

                      // 5. Context-Aware Quick Actions + Operation Feedback
                      _buildQuickActionsSection(active),
                      const SizedBox(height: 20),

                      // 6. Connected Devices
                      _buildDevicesSection(active),
                      const SizedBox(height: 20),

                      // 7. Lapdog Security Summary
                      _buildSecurityOverviewCard(active),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: const BoxDecoration(
        color: DeckColors.background,
        border: Border(
          bottom: BorderSide(color: DeckColors.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        children: [
          Text(
            'LAPDECK',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: DeckColors.surfaceElevated,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: DeckColors.borderSubtle, width: 1),
            ),
            child: Text(
              'v1.2',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: DeckColors.secondaryText,
                  ),
            ),
          ),
          const Spacer(),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: widget.isVitalsLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DeckColors.primaryAccent,
                    ),
                  )
                : const Icon(
                    Icons.refresh,
                    size: 20,
                    color: DeckColors.secondaryText,
                  ),
            tooltip: 'Refresh Network & Target State',
            onPressed: widget.isVitalsLoading ? null : widget.onRefresh,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(
              Icons.add,
              size: 20,
              color: DeckColors.primaryAccent,
            ),
            tooltip: 'Add Peer Device',
            onPressed: _openAddDeviceDialog,
          ),
        ],
      ),
    );
  }

  /// Compact contextual connectivity alert (Section 5: Connectivity alerts).
  Widget _buildConnectivityAlert(HostTarget active) {
    // Only show alert if we have checked at least once and a subsystem has failed
    final hasIssue = active.peerStatus == PeerStatus.unreachable ||
        active.peerStatus == PeerStatus.offline ||
        active.sshStatus == ServiceStatus.unavailable ||
        active.agentStatus == ServiceStatus.unavailable;

    if (!hasIssue) return const SizedBox.shrink();

    final signature =
        '${active.id}-${active.peerStatus.name}-${active.sshStatus.name}-${active.agentStatus.name}';
    if (_dismissedAlertSignature == signature) {
      return const SizedBox.shrink();
    }

    final isHostUnreachable = active.peerStatus == PeerStatus.unreachable ||
        active.peerStatus == PeerStatus.offline;
    final severityLabel = isHostUnreachable ? 'UNREACHABLE' : 'SERVICE WARNING';
    final alertColor =
        isHostUnreachable ? DeckColors.error : DeckColors.warning;

    final shortExplanation = isHostUnreachable
        ? (widget.localTailscaleActive
            ? 'Target host is unreachable on Tailscale mesh (${active.tailscaleIp}).'
            : 'Target host unreachable and Tailscale VPN interface is inactive.')
        : (active.sshStatus == ServiceStatus.unavailable
            ? 'Host is online (${active.tailscaleIp}), but SSH service is unavailable.'
            : 'SSH connected, but LAPDECK telemetry agent failed to respond.');

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: DeckColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: alertColor.withValues(alpha: 0.45),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isHostUnreachable
                      ? Icons.cloud_off_outlined
                      : Icons.warning_amber_rounded,
                  size: 16,
                  color: alertColor,
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: alertColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    severityLabel,
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: alertColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    active.name,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                TextButton(
                  onPressed: widget.isVitalsLoading ? null : widget.onRefresh,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(48, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Retry',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: alertColor,
                    ),
                  ),
                ),
                IconButton(
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    _isAlertExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: DeckColors.secondaryText,
                  ),
                  tooltip: 'Technical details',
                  onPressed: () =>
                      setState(() => _isAlertExpanded = !_isAlertExpanded),
                ),
                IconButton(
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: DeckColors.mutedText,
                  ),
                  tooltip: 'Dismiss alert',
                  onPressed: () =>
                      setState(() => _dismissedAlertSignature = signature),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              shortExplanation,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: DeckColors.secondaryText,
                  ),
            ),
            if (_isAlertExpanded) ...[
              const Divider(color: DeckColors.borderSubtle, height: 16),
              _buildKeyValueRow(
                'Tailscale VPN Interface',
                widget.localTailscaleActive ? 'Active (100.x)' : 'Not detected',
              ),
              const SizedBox(height: 4),
              _buildKeyValueRow(
                'Target Endpoint',
                '${active.tailscaleIp}:${active.port}${active.directIp != null ? " (LAN: ${active.directIp})" : ""}',
              ),
              const SizedBox(height: 4),
              _buildKeyValueRow('Host Reachability', active.reachabilityLabel),
              const SizedBox(height: 4),
              _buildKeyValueRow('SSH Service', active.sshStatusLabel),
              const SizedBox(height: 4),
              _buildKeyValueRow('LAPDECK Agent', active.agentStatusLabel),
              if (active.lastError != null) ...[
                const SizedBox(height: 6),
                Text(
                  active.lastError!,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: DeckColors.mutedText,
                      ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  /// Redesigned Network Overview Card (Section 4 & Section 5).
  Widget _buildNetworkOverviewCard(HostTarget? active) {
    final onlinePeers =
        widget.hosts.where((h) => h.peerStatus == PeerStatus.online).length;
    final totalPeers = widget.hosts.length;
    final anyChecking =
        widget.hosts.any((h) => h.peerStatus == PeerStatus.connecting) ||
            widget.isVitalsLoading;
    final allUnknown =
        widget.hosts.every((h) => h.peerStatus == PeerStatus.unknown);

    // Determine accurate, non-contradictory overall health state & subsystem failure
    Color healthColor;
    String healthTitle;
    String? subsystemFailure;

    if (allUnknown || (anyChecking && widget.lastNetworkCheckAt == null)) {
      healthColor = DeckColors.informational;
      healthTitle = 'Checking network health...';
    } else if (!widget.localTailscaleActive && onlinePeers == 0) {
      healthColor = DeckColors.error;
      healthTitle = 'Tailscale mesh offline';
      subsystemFailure =
          'Subsystem failed: Tailscale VPN interface inactive & 0 peers reachable';
    } else if (active != null &&
        (active.peerStatus == PeerStatus.unreachable ||
            active.peerStatus == PeerStatus.offline)) {
      healthColor = onlinePeers > 0 ? DeckColors.warning : DeckColors.error;
      healthTitle = onlinePeers > 0
          ? 'Mesh online · Target unreachable'
          : 'All peers unreachable';
      subsystemFailure =
          'Subsystem failed: Host reachability on ${active.name} (${active.tailscaleIp})';
    } else if (active != null &&
        active.sshStatus == ServiceStatus.unavailable) {
      healthColor = DeckColors.warning;
      healthTitle = 'Peer online · SSH unavailable';
      subsystemFailure =
          'Subsystem failed: SSH service on ${active.name} (port ${active.port})';
    } else if (active != null &&
        active.agentStatus == ServiceStatus.unavailable) {
      healthColor = DeckColors.warning;
      healthTitle = 'SSH connected · Telemetry degraded';
      subsystemFailure =
          'Subsystem failed: LAPDECK telemetry script on ${active.name}';
    } else if (onlinePeers < totalPeers) {
      healthColor = DeckColors.healthy;
      healthTitle = 'Target healthy · $onlinePeers of $totalPeers peers online';
    } else {
      healthColor = DeckColors.healthy;
      healthTitle = 'Network healthy';
    }

    final latencyValue = (active != null && active.hasFreshLatency)
        ? '${active.pingMs} ms (${active.isDirect ? "LAN" : "Mesh"})'
        : (active?.peerStatus == PeerStatus.connecting
            ? 'Measuring...'
            : 'Unavailable');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary Health Row
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: healthColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  healthTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: healthColor,
                      ),
                ),
              ),
              Text(
                _formatTime(widget.lastNetworkCheckAt),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DeckColors.mutedText,
                      fontSize: 11,
                    ),
              ),
            ],
          ),
          if (subsystemFailure != null) ...[
            const SizedBox(height: 6),
            Text(
              subsystemFailure,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: DeckColors.secondaryText,
                  ),
            ),
          ],
          const SizedBox(height: 14),
          // Secondary Metrics: 2 clean columns (no cramped 3-column truncation)
          Row(
            children: [
              Expanded(
                child: _buildOverviewStat(
                  label: 'CONNECTED PEERS',
                  value: '$onlinePeers of $totalPeers online',
                  subvalue: widget.localTailscaleActive
                      ? 'Tailscale mesh active'
                      : 'Mesh interface inactive',
                ),
              ),
              Container(
                width: 1,
                height: 36,
                margin: const EdgeInsets.symmetric(horizontal: 12),
                color: DeckColors.borderSubtle,
              ),
              Expanded(
                child: _buildOverviewStat(
                  label: 'TARGET LATENCY',
                  value: latencyValue,
                  subvalue: active != null
                      ? 'SSH: ${active.sshStatusLabel}'
                      : 'No target',
                ),
              ),
            ],
          ),
          const Divider(color: DeckColors.borderSubtle, height: 20),
          // Full-width Selected Device line so device name is NEVER truncated
          Row(
            children: [
              Text(
                'SELECTED DEVICE',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      letterSpacing: 0.5,
                      color: DeckColors.mutedText,
                    ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  active?.name ?? 'None selected',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: DeckColors.primaryText,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewStat({
    required String label,
    required String value,
    required String subvalue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10,
                letterSpacing: 0.5,
                color: DeckColors.mutedText,
              ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: DeckColors.primaryText,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          subvalue,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: DeckColors.secondaryText,
              ),
        ),
      ],
    );
  }

  /// Dedicated Target Device Selector directly above Quick Actions (Section 1).
  Widget _buildTargetDeviceSelectorCard(HostTarget active) {
    final reachColor = _peerStatusColor(active);
    final reachLabel = _peerStatusSummary(active);

    return Material(
      color: DeckColors.surfaceSecondary,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _showTargetSelectorSheet,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: DeckColors.borderMedium,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top header row: TARGET DEVICE + Selected badge + Current Reachability
              Row(
                children: [
                  const Icon(
                    Icons.ads_click,
                    size: 15,
                    color: DeckColors.primaryAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'TARGET DEVICE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.w700,
                          color: DeckColors.secondaryText,
                        ),
                  ),
                  const SizedBox(width: 8),
                  _buildSelectedBadge(),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: reachColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: reachColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          reachLabel,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: reachColor,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Main row: Full device name, OS · Mesh IP, and [Change device] action
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    switch (active.os) {
                      HostOs.linux => Icons.terminal,
                      HostOs.windows => Icons.window,
                      HostOs.macos => Icons.laptop_mac,
                    },
                    size: 22,
                    color: DeckColors.primaryAccent,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          active.name,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: DeckColors.primaryText,
                                  ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${active.osDisplayName} · ${active.tailscaleIp}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    color: DeckColors.secondaryText,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: DeckColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: DeckColors.borderMedium,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Change device',
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: DeckColors.primaryAccent,
                                  ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.swap_horiz,
                          size: 16,
                          color: DeckColors.primaryAccent,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Independent subsystem status pills
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildSubsystemChip(
                    'Host',
                    active.reachabilityLabel,
                    _peerStatusColor(active),
                  ),
                  _buildSubsystemChip(
                    'SSH',
                    active.sshStatusLabel,
                    _serviceStatusColor(active.sshStatus),
                  ),
                  _buildSubsystemChip(
                    'Agent',
                    active.agentStatusLabel,
                    _serviceStatusColor(active.agentStatus),
                  ),
                  if (active.hasFreshLatency)
                    _buildSubsystemChip(
                      'RTT',
                      '${active.pingMs} ms',
                      DeckColors.healthy,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubsystemChip(String name, String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: DeckColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$name: ',
            style: const TextStyle(
              fontSize: 10,
              color: DeckColors.mutedText,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            status,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Context-Aware Quick Actions Section (Section 2 & Section 6).
  Widget _buildQuickActionsSection(HostTarget? active) {
    final targetName = active?.name ?? 'no target';
    final isArmed = widget.lapdogStatus.isAwayArmed;
    final hasReusablePty = widget.terminalController.hasActiveSessionFor(active);
    final isAwayBusy =
        active != null && _inFlightKeys.contains('away-${active.id}');
    final isLockBusy =
        active != null && _inFlightKeys.contains('lock-${active.id}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Quick actions',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: DeckColors.secondaryText,
                  ),
            ),
            if (active != null)
              Text(
                'Targeting ${active.name}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: DeckColors.mutedText,
                    ),
              ),
          ],
        ),
        const SizedBox(height: 10),

        // Contextual Operation Lifecycle Feedback Card (Section 6 & Section 8)
        if (_operationFeedback != null) ...[
          _buildOperationFeedbackBanner(_operationFeedback!),
          const SizedBox(height: 12),
        ],

        // 2x2 Grid of Context-Aware Actions
        Row(
          children: [
            Expanded(
              child: _buildContextActionCard(
                icon: Icons.terminal,
                title: 'Terminal',
                targetSubtitle: hasReusablePty
                    ? 'Resume on $targetName'
                    : 'Open on $targetName',
                stateHint: hasReusablePty
                    ? 'Active PTY session'
                    : 'SSH ${active?.sshStatusLabel ?? "Unknown"}',
                accentColor:
                    hasReusablePty ? DeckColors.healthy : DeckColors.primaryAccent,
                isBusy: false,
                onTap: active == null ? null : _handleTerminalQuickAction,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildContextActionCard(
                icon: Icons.fact_check_outlined,
                title: 'Diagnostics',
                targetSubtitle: 'Inspect $targetName',
                stateHint: active?.reachabilityLabel ?? 'Unknown',
                accentColor: DeckColors.informational,
                isBusy: false,
                onTap: active == null ? null : _handleDiagnosticsQuickAction,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildContextActionCard(
                icon: isArmed ? Icons.shield : Icons.verified_user_outlined,
                title: isArmed ? 'Disarm Away' : 'Arm Away',
                targetSubtitle:
                    isArmed ? 'Disarm $targetName' : 'Protect $targetName',
                stateHint: active?.lapdogDaemonStatus == ServiceStatus.available
                    ? (isArmed ? 'Away Armed' : 'Home Mode')
                    : 'Daemon ${active?.lapdogStatusLabel ?? "Unknown"}',
                accentColor:
                    isArmed ? DeckColors.warning : DeckColors.healthy,
                isBusy: isAwayBusy,
                onTap: (active == null || isAwayBusy)
                    ? null
                    : _handleArmAwayQuickAction,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildContextActionCard(
                icon: Icons.lock_outline,
                title: active?.lockActionTitle ?? 'Lock Session',
                targetSubtitle: 'Lock $targetName',
                stateHint: 'SSH ${active?.sshStatusLabel ?? "Unknown"}',
                accentColor: DeckColors.primaryAccent,
                isBusy: isLockBusy,
                onTap: (active == null || isLockBusy)
                    ? null
                    : _handleLockDeviceQuickAction,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContextActionCard({
    required IconData icon,
    required String title,
    required String targetSubtitle,
    required String stateHint,
    required Color accentColor,
    required bool isBusy,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: DeckColors.surfaceSecondary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DeckColors.borderSubtle, width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (isBusy)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accentColor,
                      ),
                    )
                  else
                    Icon(icon, size: 18, color: accentColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: DeckColors.primaryText,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                targetSubtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DeckColors.secondaryText,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                stateHint,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: DeckColors.mutedText,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Displays operation lifecycle state with target safety (Section 6 & Section 8).
  Widget _buildOperationFeedbackBanner(OperationFeedback op) {
    final Color stateColor = switch (op.state) {
      OperationLifecycleState.ready => DeckColors.informational,
      OperationLifecycleState.inProgress => DeckColors.primaryAccent,
      OperationLifecycleState.successful => DeckColors.healthy,
      OperationLifecycleState.failed => DeckColors.error,
      OperationLifecycleState.timedOut => DeckColors.warning,
      OperationLifecycleState.resultUnknown => DeckColors.warning,
      OperationLifecycleState.targetUnavailable => DeckColors.error,
    };

    final canVerify = op.state == OperationLifecycleState.timedOut ||
        op.state == OperationLifecycleState.resultUnknown ||
        op.state == OperationLifecycleState.failed ||
        op.state == OperationLifecycleState.targetUnavailable;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: stateColor.withValues(alpha: 0.45),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (op.isBusy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: stateColor,
                  ),
                )
              else
                Icon(
                  switch (op.state) {
                    OperationLifecycleState.successful =>
                      Icons.check_circle_outline,
                    OperationLifecycleState.timedOut ||
                    OperationLifecycleState.resultUnknown =>
                      Icons.help_outline,
                    _ => Icons.error_outline,
                  },
                  size: 16,
                  color: stateColor,
                ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.14),
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
                  height: 1.35,
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
          if (canVerify) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _verifyTargetState(op.targetHostId),
                icon: const Icon(Icons.fact_check_outlined, size: 14),
                label: Text('Verify ${op.targetHostName} state'),
                style: TextButton.styleFrom(
                  foregroundColor: DeckColors.primaryAccent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: const Size(48, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Connected Devices Section (Section 3 & Section 5).
  Widget _buildDevicesSection(HostTarget? active) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Connected devices',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: DeckColors.secondaryText,
                    ),
              ),
            ),
            TextButton(
              onPressed: _showTargetSelectorSheet,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(48, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Change target',
                style: TextStyle(
                  fontSize: 12,
                  color: DeckColors.secondaryText,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () => widget.onNavigateTab(1),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: const Size(48, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'View all (${widget.hosts.length})',
                style: const TextStyle(
                  fontSize: 12,
                  color: DeckColors.primaryAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.hosts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final host = widget.hosts[index];
            final isSelected = host.id == active?.id;
            return _buildDeviceRow(host, isSelected);
          },
        ),
      ],
    );
  }

  /// Redesigned Device Row following Section 3 & Section 5:
  /// - First line: Device name (never truncated) + Selected indicator
  /// - Second line: Operating system + Device role/description
  /// - Trailing information: Connection status + Latency, if available
  /// - Tapping a row opens device details explicitly without silently switching target.
  Widget _buildDeviceRow(HostTarget host, bool isSelected) {
    final statusColor = _peerStatusColor(host);
    final statusLabel = _peerStatusSummary(host);

    return Material(
      color: DeckColors.surfaceSecondary,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => DeviceDetailScreen(
                host: host,
                isGlobalTarget: isSelected,
                storage: widget.storage,
                sshService: widget.sshService,
                terminalController: widget.terminalController,
                onUpdated: widget.onHostsUpdated,
                onSelectAsTarget: () => widget.onSelectHost(host),
                onTelemetryUpdated: (bundle) =>
                    widget.onTelemetryUpdated(host.id, bundle),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: DeckColors.borderSubtle,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                switch (host.os) {
                  HostOs.linux => Icons.terminal,
                  HostOs.windows => Icons.window,
                  HostOs.macos => Icons.laptop_mac,
                },
                size: 20,
                color: isSelected
                    ? DeckColors.primaryAccent
                    : DeckColors.secondaryText,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // First line: Complete device name + Selected indicator
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          host.name,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: DeckColors.primaryText,
                                  ),
                        ),
                        if (isSelected) _buildSelectedBadge(),
                      ],
                    ),
                    const SizedBox(height: 3),
                    // Second line: Operating system · Device role
                    Text(
                      '${host.osDisplayName} · ${host.roleDisplayName}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DeckColors.secondaryText,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              // Trailing: Connection status + Latency if available
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusLabel,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 11,
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ),
                  if (host.hasFreshLatency) ...[
                    const SizedBox(height: 2),
                    Text(
                      '${host.pingMs} ms',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: DeckColors.secondaryText,
                          ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                size: 18,
                color: DeckColors.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Redesigned Lapdog Security Summary Card (Section 5: Lapdog card).
  /// Removes redundant Arm Away button (available in Quick Actions) and shows:
  /// - Current security mode
  /// - Daemon health
  /// - Last health check
  /// - Security event summary (using "events recorded", not "events audited")
  /// - Manage security action
  Widget _buildSecurityOverviewCard(HostTarget? active) {
    final lapdog = widget.lapdogStatus;
    final daemonAvailable =
        active?.lapdogDaemonStatus == ServiceStatus.available &&
            lapdog.isInstalled;
    final isArmed = daemonAvailable && lapdog.isAwayArmed;

    final String modeLabel;
    final Color modeColor;
    if (active == null || !lapdog.isVerified) {
      modeLabel = 'Unverified';
      modeColor = DeckColors.mutedText;
    } else if (!daemonAvailable) {
      modeLabel = 'Unavailable';
      modeColor = DeckColors.mutedText;
    } else if (isArmed) {
      modeLabel = 'Away armed';
      modeColor = DeckColors.warning;
    } else {
      modeLabel = 'Home mode';
      modeColor = DeckColors.healthy;
    }

    final daemonHealthText = active == null
        ? 'No target'
        : switch (active.lapdogDaemonStatus) {
            ServiceStatus.available =>
              'Available${lapdog.version.isNotEmpty ? " (${lapdog.version})" : ""}',
            ServiceStatus.unavailable =>
              'Unavailable on ${active.osDisplayName}',
            ServiceStatus.connecting => 'Checking...',
            ServiceStatus.unknown => 'Unknown',
          };

    final eventSummaryText = daemonAvailable
        ? '${lapdog.sentHistory} events recorded · ${lapdog.pendingEvents} pending in queue'
        : 'No security events recorded for ${active?.name ?? "target"}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isArmed ? Icons.shield : Icons.verified_user_outlined,
                size: 18,
                color: modeColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Lapdog security · ${active?.name ?? "None"}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: DeckColors.primaryText,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: modeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  modeLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: modeColor,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildKeyValueRow('Current security mode', modeLabel),
          const SizedBox(height: 6),
          _buildKeyValueRow('Daemon health', daemonHealthText),
          const SizedBox(height: 6),
          _buildKeyValueRow(
            'Last health check',
            _formatTime(lapdog.lastChecked ?? active?.lastChecked),
          ),
          const SizedBox(height: 6),
          _buildKeyValueRow('Security events', eventSummaryText),
          const Divider(color: DeckColors.borderSubtle, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Use Quick Actions above to arm or disarm ${active?.name ?? "target"}.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: DeckColors.mutedText,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: active == null
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => DeviceDetailScreen(
                              host: active,
                              isGlobalTarget: true,
                              storage: widget.storage,
                              sshService: widget.sshService,
                              terminalController: widget.terminalController,
                              onUpdated: widget.onHostsUpdated,
                              onSelectAsTarget: () =>
                                  widget.onSelectHost(active),
                              onTelemetryUpdated: (bundle) =>
                                  widget.onTelemetryUpdated(active.id, bundle),
                            ),
                          ),
                        );
                      },
                icon: const Icon(Icons.tune, size: 15),
                label: const Text('Manage security'),
                style: TextButton.styleFrom(
                  foregroundColor: DeckColors.primaryAccent,
                  minimumSize: const Size(48, 36),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: DeckColors.primaryAccent.withValues(alpha: 0.14),
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
    );
  }

  Widget _buildSheetTargetSummaryCard(HostTarget target) {
    final statusColor = _peerStatusColor(target);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DeckColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DeckColors.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(
            switch (target.os) {
              HostOs.linux => Icons.terminal,
              HostOs.windows => Icons.window,
              HostOs.macos => Icons.laptop_mac,
            },
            size: 20,
            color: DeckColors.primaryAccent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  target.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${target.osDisplayName} · ${target.username}@${target.tailscaleIp}:${target.port}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: DeckColors.secondaryText,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              _peerStatusSummary(target),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: statusColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKeyValueRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: DeckColors.secondaryText,
              ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: DeckColors.primaryText,
                ),
          ),
        ),
      ],
    );
  }

  /// Green ONLY for verified healthy states (Section 4 & Section 7).
  Color _peerStatusColor(HostTarget host) {
    if (host.peerStatus == PeerStatus.online &&
        host.sshStatus == ServiceStatus.available) {
      return DeckColors.healthy;
    }
    if (host.peerStatus == PeerStatus.online &&
        host.sshStatus == ServiceStatus.unavailable) {
      return DeckColors.warning;
    }
    if (host.peerStatus == PeerStatus.connecting) {
      return DeckColors.informational;
    }
    if (host.peerStatus == PeerStatus.unreachable ||
        host.peerStatus == PeerStatus.offline) {
      return DeckColors.error;
    }
    return DeckColors.mutedText;
  }

  String _peerStatusSummary(HostTarget host) {
    if (host.peerStatus == PeerStatus.online &&
        host.sshStatus == ServiceStatus.unavailable) {
      return 'SSH Unavailable';
    }
    return host.reachabilityLabel;
  }

  Color _serviceStatusColor(ServiceStatus s) {
    return switch (s) {
      ServiceStatus.available => DeckColors.healthy,
      ServiceStatus.unavailable => DeckColors.error,
      ServiceStatus.connecting => DeckColors.informational,
      ServiceStatus.unknown => DeckColors.mutedText,
    };
  }
}

/// Interactive Diagnostics Bottom Sheet bound to a captured target machine (Section 2 & Section 8).
class _DiagnosticsBottomSheet extends StatefulWidget {
  final HostTarget targetHost;
  final StorageService storage;
  final SshService sshService;
  final Function(TelemetryBundle bundle) onTelemetryUpdated;
  final VoidCallback onRefreshGlobal;
  final Function(OperationFeedback feedback) onOperationStateChanged;

  const _DiagnosticsBottomSheet({
    required this.targetHost,
    required this.storage,
    required this.sshService,
    required this.onTelemetryUpdated,
    required this.onRefreshGlobal,
    required this.onOperationStateChanged,
  });

  @override
  State<_DiagnosticsBottomSheet> createState() =>
      _DiagnosticsBottomSheetState();
}

class _DiagnosticsBottomSheetState extends State<_DiagnosticsBottomSheet> {
  late HostTarget _capturedTarget;
  late List<DiagnosticCheckResult> _checks;
  bool _isRunning = false;
  bool _hasRun = false;
  String? _blockingReason;

  @override
  void initState() {
    super.initState();
    // Retain original target identity throughout diagnostics lifecycle
    _capturedTarget = widget.targetHost;
    _checks = _buildInitialChecks(_capturedTarget);
    if (_capturedTarget.peerStatus == PeerStatus.unreachable ||
        _capturedTarget.peerStatus == PeerStatus.offline) {
      _blockingReason =
          '${_capturedTarget.name} (${_capturedTarget.tailscaleIp}) is currently unreachable. Start diagnostics to re-probe network connectivity.';
    }
  }

  List<DiagnosticCheckResult> _buildInitialChecks(HostTarget host) {
    return [
      DiagnosticCheckResult(
        id: 'chk-reachability',
        title: 'Mesh & LAN Host Reachability',
        description:
            'Probe ${host.tailscaleIp}:${host.port}${host.directIp != null ? " (fallback ${host.directIp})" : ""}',
      ),
      DiagnosticCheckResult(
        id: 'chk-ssh',
        title: 'SSH Authentication & Shell',
        description:
            'Verify ${host.authMethod.name} login for ${host.username}@${host.name}',
      ),
      const DiagnosticCheckResult(
        id: 'chk-vitals',
        title: 'LAPDECK System Telemetry',
        description: 'Collect CPU load, RAM usage, root disk & uptime',
      ),
      const DiagnosticCheckResult(
        id: 'chk-processes',
        title: 'Workspace Process Inspection',
        description: 'Query top active CPU & memory processes',
      ),
      DiagnosticCheckResult(
        id: 'chk-lapdog',
        title: 'Lapdog Security Daemon',
        description:
            'Verify lapdog binary & watchdog mode on ${host.osDisplayName}',
      ),
    ];
  }

  void _updateCheck(
    String id, {
    required OperationLifecycleState state,
    String? detail,
    int? durationMs,
  }) {
    if (!mounted) return;
    setState(() {
      _checks = _checks.map((c) {
        if (c.id != id) return c;
        return c.copyWith(state: state, detail: detail, durationMs: durationMs);
      }).toList();
    });
  }

  Future<void> _runDiagnostics() async {
    if (_isRunning) return;

    final target = _capturedTarget;
    final opId = 'diag-${DateTime.now().millisecondsSinceEpoch}';

    setState(() {
      _isRunning = true;
      _hasRun = true;
      _blockingReason = null;
      _checks = _buildInitialChecks(target);
    });

    widget.onOperationStateChanged(
      OperationFeedback(
        id: opId,
        operationName: 'Diagnostics',
        targetHostId: target.id,
        targetHostName: target.name,
        state: OperationLifecycleState.inProgress,
        summary: 'Running 5 diagnostic checks on ${target.name}...',
        timestamp: DateTime.now(),
      ),
    );

    try {
      // Check 1: Host Reachability & TCP Port
      _updateCheck(
        'chk-reachability',
        state: OperationLifecycleState.inProgress,
        detail: 'Probing ${target.tailscaleIp}:${target.port}...',
      );

      final reach = await widget.sshService.checkReachability(target);

      if (!reach.isOnline) {
        _updateCheck(
          'chk-reachability',
          state: OperationLifecycleState.targetUnavailable,
          detail: reach.errorDetail ??
              'Host unreachable on Tailscale and LAN routes.',
        );
        for (final id in [
          'chk-ssh',
          'chk-vitals',
          'chk-processes',
          'chk-lapdog',
        ]) {
          _updateCheck(
            id,
            state: OperationLifecycleState.targetUnavailable,
            detail:
                'Skipped because ${target.name} is unreachable on the network.',
          );
        }
        if (mounted) {
          setState(() {
            _blockingReason = reach.errorDetail ??
                '${target.name} did not respond on Tailscale (${target.tailscaleIp}). Ensure Tailscale VPN is active on both devices and the machine is awake.';
          });
        }
        widget.onOperationStateChanged(
          OperationFeedback(
            id: opId,
            operationName: 'Diagnostics',
            targetHostId: target.id,
            targetHostName: target.name,
            state: OperationLifecycleState.targetUnavailable,
            summary:
                'Diagnostics halted: ${target.name} (${target.tailscaleIp}) is unreachable.',
            technicalDetails: reach.errorDetail,
            timestamp: DateTime.now(),
          ),
        );
        return;
      }

      if (reach.sshPortStatus != ServiceStatus.available) {
        _updateCheck(
          'chk-reachability',
          state: OperationLifecycleState.successful,
          detail:
              'Peer online (${reach.latencyMs ?? "--"} ms via ${reach.isDirect ? "LAN" : "Tailscale"}).',
          durationMs: reach.latencyMs,
        );
        _updateCheck(
          'chk-ssh',
          state: OperationLifecycleState.failed,
          detail: reach.errorDetail ??
              'SSH port ${target.port} refused or timed out.',
        );
        for (final id in ['chk-vitals', 'chk-processes', 'chk-lapdog']) {
          _updateCheck(
            id,
            state: OperationLifecycleState.targetUnavailable,
            detail: 'Cannot run remote check because SSH service is unavailable.',
          );
        }
        if (mounted) {
          setState(() {
            _blockingReason =
                '${target.name} is online on the mesh, but SSH port ${target.port} is not accepting connections. Verify sshd / OpenSSH Server is running on ${target.name}.';
          });
        }
        widget.onOperationStateChanged(
          OperationFeedback(
            id: opId,
            operationName: 'Diagnostics',
            targetHostId: target.id,
            targetHostName: target.name,
            state: OperationLifecycleState.failed,
            summary:
                'Diagnostics on ${target.name}: Host is online, but SSH service on port ${target.port} is unavailable.',
            timestamp: DateTime.now(),
          ),
        );
        return;
      }

      _updateCheck(
        'chk-reachability',
        state: OperationLifecycleState.successful,
        detail:
            'Reachable via ${reach.isDirect ? "Direct LAN (${target.directIp})" : "Tailscale Mesh (${target.tailscaleIp})"} in ${reach.latencyMs} ms.',
        durationMs: reach.latencyMs,
      );

      // Check 2-5: SSH Auth & Telemetry Bundle
      _updateCheck(
        'chk-ssh',
        state: OperationLifecycleState.inProgress,
        detail: 'Authenticating as ${target.username}...',
      );
      _updateCheck(
        'chk-vitals',
        state: OperationLifecycleState.inProgress,
        detail: 'Querying system vitals...',
      );
      _updateCheck(
        'chk-processes',
        state: OperationLifecycleState.inProgress,
        detail: 'Reading process table...',
      );
      _updateCheck(
        'chk-lapdog',
        state: OperationLifecycleState.inProgress,
        detail: 'Checking Lapdog daemon...',
      );

      final secret = await widget.storage.getHostCredential(target.id);
      final sw = Stopwatch()..start();
      final bundle = await widget.sshService.fetchTelemetryBundle(
        target,
        secret: secret,
      );
      sw.stop();

      if (bundle == null) {
        _updateCheck(
          'chk-ssh',
          state: OperationLifecycleState.failed,
          detail:
              'SSH authentication or command execution failed on ${target.name}.',
        );
        for (final id in ['chk-vitals', 'chk-processes', 'chk-lapdog']) {
          _updateCheck(
            id,
            state: OperationLifecycleState.failed,
            detail: 'Telemetry script did not return valid data.',
          );
        }
        widget.onOperationStateChanged(
          OperationFeedback(
            id: opId,
            operationName: 'Diagnostics',
            targetHostId: target.id,
            targetHostName: target.name,
            state: OperationLifecycleState.failed,
            summary:
                'Diagnostics failed on ${target.name}: TCP port ${target.port} is open, but SSH authentication failed.',
            timestamp: DateTime.now(),
          ),
        );
        return;
      }

      widget.onTelemetryUpdated(bundle);

      _updateCheck(
        'chk-ssh',
        state: OperationLifecycleState.successful,
        detail:
            'Authenticated ${target.username}@${target.name} (${sw.elapsedMilliseconds} ms).',
        durationMs: sw.elapsedMilliseconds,
      );
      _updateCheck(
        'chk-vitals',
        state: OperationLifecycleState.successful,
        detail:
            'CPU ${(bundle.vitals.cpuPercent * 100).toStringAsFixed(0)}% · RAM ${bundle.vitals.ramUsage} · Up ${bundle.vitals.uptime}',
      );
      _updateCheck(
        'chk-processes',
        state: OperationLifecycleState.successful,
        detail:
            '${bundle.processes.length} active processes inspected.',
      );
      _updateCheck(
        'chk-lapdog',
        state: bundle.lapdog.isInstalled
            ? OperationLifecycleState.successful
            : OperationLifecycleState.failed,
        detail: bundle.lapdog.isInstalled
            ? 'Daemon available (${bundle.lapdog.isAwayArmed ? "Away Armed" : "Home Mode"}, ${bundle.lapdog.sentHistory} events recorded)'
            : 'Lapdog binary not installed or not in PATH on ${target.name}.',
      );

      widget.onOperationStateChanged(
        OperationFeedback(
          id: opId,
          operationName: 'Diagnostics',
          targetHostId: target.id,
          targetHostName: target.name,
          state: OperationLifecycleState.successful,
          summary:
              'Diagnostics completed on ${target.name}: Reachable (${reach.latencyMs} ms), SSH & Vitals verified.',
          timestamp: DateTime.now(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRunning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final target = _capturedTarget;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
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
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(
                  Icons.fact_check_outlined,
                  size: 20,
                  color: DeckColors.informational,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Diagnostics · ${target.name}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                IconButton(
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.close,
                    size: 18,
                    color: DeckColors.secondaryText,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Target Context Summary
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DeckColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DeckColors.borderSubtle),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Target: ${target.name}',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${target.osDisplayName} · ${target.tailscaleIp}:${target.port}',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: DeckColors.secondaryText,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: DeckColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      target.reachabilityLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: DeckColors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_blockingReason != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DeckColors.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: DeckColors.error.withValues(alpha: 0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 16,
                          color: DeckColors.error,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Connectivity Issue Detected',
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: DeckColors.error,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _blockingReason!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DeckColors.primaryText,
                            fontSize: 11,
                          ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Text(
              'DIAGNOSTIC CHECKS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    letterSpacing: 0.8,
                    color: DeckColors.mutedText,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.42,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _checks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _buildCheckTile(_checks[i]),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isRunning ? null : _runDiagnostics,
                icon: _isRunning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DeckColors.background,
                        ),
                      )
                    : Icon(
                        _hasRun ? Icons.refresh : Icons.play_arrow,
                        size: 18,
                      ),
                label: Text(
                  _isRunning
                      ? 'Inspecting ${target.name}...'
                      : (_hasRun
                          ? 'Re-run Diagnostics on ${target.name}'
                          : 'Start Diagnostics on ${target.name}'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: DeckColors.primaryAccent,
                  foregroundColor: DeckColors.background,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckTile(DiagnosticCheckResult check) {
    final Color color = switch (check.state) {
      OperationLifecycleState.ready => DeckColors.mutedText,
      OperationLifecycleState.inProgress => DeckColors.primaryAccent,
      OperationLifecycleState.successful => DeckColors.healthy,
      OperationLifecycleState.failed => DeckColors.error,
      OperationLifecycleState.timedOut => DeckColors.warning,
      OperationLifecycleState.resultUnknown => DeckColors.warning,
      OperationLifecycleState.targetUnavailable => DeckColors.error,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: DeckColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: check.state == OperationLifecycleState.inProgress
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(
                    switch (check.state) {
                      OperationLifecycleState.ready =>
                        Icons.radio_button_unchecked,
                      OperationLifecycleState.successful => Icons.check_circle,
                      OperationLifecycleState.failed ||
                      OperationLifecycleState.targetUnavailable =>
                        Icons.cancel_outlined,
                      _ => Icons.help_outline,
                    },
                    size: 16,
                    color: color,
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        check.title,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: DeckColors.primaryText,
                            ),
                      ),
                    ),
                    Text(
                      check.state.label,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  check.detail ?? check.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: check.detail != null
                            ? DeckColors.secondaryText
                            : DeckColors.mutedText,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
