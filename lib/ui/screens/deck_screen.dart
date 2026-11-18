import 'dart:async';
import 'package:flutter/material.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';
import '../../models/command_action.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../widgets/deck_header.dart';
import '../widgets/host_rack_selector.dart';
import '../widgets/quick_action_pad.dart';
import '../widgets/terminal_bay.dart';
import 'host_config_dialog.dart';

enum DeckViewMode { tacticalDeck, fullTerminal, securityAgent }

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
  DeckViewMode _viewMode = DeckViewMode.tacticalDeck;
  String? _runningActionId;
  String _terminalBuffer = '';
  bool _isShellActive = false;
  bool _isAwayArmed = false;

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
  }

  void _appendOutput(String text) {
    setState(() {
      _terminalBuffer += text;
      // Cap buffer at 50,000 characters to keep memory light
      if (_terminalBuffer.length > 50000) {
        _terminalBuffer = _terminalBuffer.substring(_terminalBuffer.length - 40000);
      }
    });
  }

  Future<void> _handleSelectHost(HostTarget host) async {
    if (_isShellActive) {
      await widget.sshService.disconnect();
      setState(() => _isShellActive = false);
    }
    setState(() => _activeHost = host);
    await widget.storage.setActiveHostId(host.id);
    _appendOutput('\r\n// ACTIVE HOST SWITCHED: [${host.name.toUpperCase()}] (${host.tailscaleIp})\r\n');
  }

  Future<void> _handleTriggerAction(CommandAction action) async {
    final host = _activeHost;
    if (host == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active host selected.')),
      );
      return;
    }

    setState(() => _runningActionId = action.id);
    _appendOutput('\r\n// EXEC: ${action.label} on [${host.name}]\r\n\$ ${action.command}\r\n');

    final secret = await widget.storage.getHostCredential(host.id);

    final result = await widget.sshService.executeCommand(
      host: host,
      command: action.command,
      password: host.authMethod == AuthMethod.password ? secret : null,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
    );

    setState(() => _runningActionId = null);

    if (result.output.isNotEmpty) {
      _appendOutput(result.output);
    }
    if (result.error.isNotEmpty) {
      _appendOutput('\r\n[STDERR]:\r\n${result.error}\r\n');
    }

    _appendOutput('// COMPLETED (${result.duration.inMilliseconds}ms, exit code: ${result.exitCode})\r\n');

    // Update away mode toggle state if this was a lapdog away/back command
    if (action.id == 'act-lapdog-away') {
      setState(() => _isAwayArmed = true);
    } else if (action.id == 'act-lapdog-back') {
      setState(() => _isAwayArmed = false);
    }
  }

  Future<void> _handleToggleShell() async {
    final host = _activeHost;
    if (host == null) return;

    if (_isShellActive) {
      await widget.sshService.disconnect();
      setState(() => _isShellActive = false);
      _appendOutput('\r\n// INTERACTIVE SESSION TERMINATED BY USER\r\n');
    } else {
      _appendOutput('\r\n// INITIATING INTERACTIVE PTY: ${host.username}@${host.tailscaleIp}:${host.port}...\r\n');
      final secret = await widget.storage.getHostCredential(host.id);

      final success = await widget.sshService.startInteractiveShell(
        host: host,
        password: host.authMethod == AuthMethod.password ? secret : null,
        privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
        onOutput: (chunk) => _appendOutput(chunk),
        onDisconnected: () {
          if (mounted) setState(() => _isShellActive = false);
        },
      );

      setState(() => _isShellActive = success);
      if (success) {
        _appendOutput('// PTY ALLOCATED (xterm-256color) • READY\r\n');
      }
    }
  }

  void _handleSendInput(String input) {
    if (_isShellActive) {
      widget.sshService.sendShellInput(input.endsWith('\n') ? input : '$input\n');
    } else {
      // Direct raw command execution when shell not connected
      final action = CommandAction(
        id: 'raw-exec-${DateTime.now().millisecondsSinceEpoch}',
        label: 'RAW RUN',
        description: input,
        command: input,
        icon: Icons.code,
        category: ActionCategory.custom,
      );
      _handleTriggerAction(action);
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
          setState(() {
            _activeHost = updatedHost;
          });
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
            onRefresh: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sweeping Tailscale mesh nodes...')),
              );
            },
            onAddHost: () => _openHostDialog(),
          ),

          // Tactical Mode Segmented Switcher
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: const BoxDecoration(
              color: DeckColors.surfaceRack,
              border: Border(
                bottom: BorderSide(color: DeckColors.borderSubtle, width: 1),
              ),
            ),
            child: Row(
              children: [
                _buildModeButton('TACTICAL DECK', DeckViewMode.tacticalDeck, Icons.dashboard_customize_outlined),
                const SizedBox(width: 8),
                _buildModeButton('PTY TERMINAL', DeckViewMode.fullTerminal, Icons.terminal),
                const SizedBox(width: 8),
                _buildModeButton('LAPDOG GUARD', DeckViewMode.securityAgent, Icons.security),
              ],
            ),
          ),

          // Body Content depending on ViewMode
          Expanded(
            child: switch (_viewMode) {
              DeckViewMode.tacticalDeck => _buildTacticalDeckView(),
              DeckViewMode.fullTerminal => _buildFullTerminalView(),
              DeckViewMode.securityAgent => _buildSecurityAgentView(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(String label, DeckViewMode mode, IconData icon) {
    final isSelected = _viewMode == mode;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _viewMode = mode),
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? DeckColors.surfaceElevated : Colors.transparent,
            border: Border.all(
              color: isSelected ? DeckColors.borderActive : DeckColors.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 13,
                color: isSelected ? DeckColors.accentOrange : DeckColors.textMid,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isSelected ? DeckColors.textHigh : DeckColors.textMid,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTacticalDeckView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          HostRackSelector(
            hosts: _hosts,
            activeHost: _activeHost,
            onSelectHost: _handleSelectHost,
            onEditHost: (host) => _openHostDialog(hostToEdit: host),
          ),
          const SizedBox(height: 16),
          QuickActionPad(
            actions: CommandAction.defaultActions,
            runningActionId: _runningActionId,
            onTriggerAction: _handleTriggerAction,
            onRunCustomCommand: _handleSendInput,
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'LIVE OUTPUT CONSOLE',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.2,
                color: DeckColors.textMid,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              height: 220,
              child: TerminalBay(
                activeHost: _activeHost,
                terminalOutput: _terminalBuffer,
                isShellActive: _isShellActive,
                onSendInput: _handleSendInput,
                onClearBuffer: () => setState(() => _terminalBuffer = ''),
                onToggleShell: _handleToggleShell,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildFullTerminalView() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: TerminalBay(
        activeHost: _activeHost,
        terminalOutput: _terminalBuffer,
        isShellActive: _isShellActive,
        onSendInput: _handleSendInput,
        onClearBuffer: () => setState(() => _terminalBuffer = ''),
        onToggleShell: _handleToggleShell,
      ),
    );
  }

  Widget _buildSecurityAgentView() {
    final host = _activeHost;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Security Agent Status Banner
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: DeckColors.surfaceRack,
              border: Border.all(color: DeckColors.borderSubtle, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _isAwayArmed ? Icons.shield : Icons.verified_user,
                      size: 20,
                      color: _isAwayArmed ? DeckColors.cautionAmber : DeckColors.phosphorGreen,
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'LAP-DOG SECURITY AGENT',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            letterSpacing: 1.0,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'MONITORING: ${host?.name.toUpperCase() ?? "NO HOST"}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: DeckColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: (_isAwayArmed ? DeckColors.cautionAmber : DeckColors.phosphorGreen).withValues(alpha: 0.12),
                        border: Border.all(
                          color: _isAwayArmed ? DeckColors.cautionAmber : DeckColors.phosphorGreen,
                          width: 1,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        _isAwayArmed ? 'ARMED // AWAY' : 'ACTIVE // HOME',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: _isAwayArmed ? DeckColors.cautionAmber : DeckColors.phosphorGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'When Away Mode is armed, lap-dog actively monitors PAM logins, unlock events, and physical access, capturing webcam snapshots and sending instant alerts.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: DeckColors.textMid,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.shield, size: 14),
                        label: const Text('ARM AWAY MODE'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DeckColors.cautionAmber,
                          foregroundColor: DeckColors.surfaceCore,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          final act = CommandAction.defaultActions.firstWhere((a) => a.id == 'act-lapdog-away');
                          _handleTriggerAction(act);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.verified_user, size: 14),
                        label: const Text('DISARM AWAY'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DeckColors.textHigh,
                          side: const BorderSide(color: DeckColors.borderMedium, width: 1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          final act = CommandAction.defaultActions.firstWhere((a) => a.id == 'act-lapdog-back');
                          _handleTriggerAction(act);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Security Log / Audit Feed
          Text(
            'RECENT ACCESS & AUDIT STREAM',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: DeckColors.textMid,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DeckColors.surfaceInset,
              border: Border.all(color: DeckColors.borderSubtle, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAuditItem(
                  'PAM_AUTH_SUCCESS',
                  'User surajwork logged in via Tailscale SSH',
                  '14:15:34',
                  DeckColors.phosphorGreen,
                ),
                const Divider(color: DeckColors.borderSubtle, height: 16),
                _buildAuditItem(
                  'ETW_PEER_SYNC',
                  'Peer laptop mochirondesu direct route synchronized (192.168.29.61)',
                  '14:02:11',
                  DeckColors.meshCyan,
                ),
                const Divider(color: DeckColors.borderSubtle, height: 16),
                _buildAuditItem(
                  'DAEMON_HEARTBEAT',
                  'lapdog background service running (PID 182767, uptime 4d 12h)',
                  '13:45:00',
                  DeckColors.textMuted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditItem(String event, String detail, String time, Color tagColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: tagColor.withValues(alpha: 0.12),
            border: Border.all(color: tagColor.withValues(alpha: 0.4), width: 1),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(
            event,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 9,
              color: tagColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: DeckColors.textHigh,
                ),
              ),
            ],
          ),
        ),
        Text(
          time,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 10,
            color: DeckColors.textMuted,
          ),
        ),
      ],
    );
  }
}
