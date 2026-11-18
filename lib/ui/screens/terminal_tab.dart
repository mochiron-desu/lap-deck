import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';
import '../../services/storage_service.dart';
import '../../services/terminal_session_controller.dart';

class TerminalTab extends StatefulWidget {
  final List<HostTarget> hosts;
  final HostTarget? activeHost;
  final TerminalSessionController controller;
  final StorageService storage;
  final Function(HostTarget) onSelectHost;

  const TerminalTab({
    super.key,
    required this.hosts,
    required this.activeHost,
    required this.controller,
    required this.storage,
    required this.onSelectHost,
  });

  @override
  State<TerminalTab> createState() => _TerminalTabState();
}

class _TerminalTabState extends State<TerminalTab> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isCtrlActive = false;
  int _historyIndex = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTerminalOutput);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTerminalOutput);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTerminalOutput() {
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 60),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _handleConnect({
    HostTarget? explicitTarget,
    bool forceReconnect = false,
  }) async {
    final target = explicitTarget ?? widget.activeHost;
    if (target == null) return;

    final secret = await widget.storage.getHostCredential(target.id);
    await widget.controller.connect(
      target,
      secret: secret,
      forceReconnect: forceReconnect,
    );
  }

  void _handleSubmit() {
    final text = _inputController.text;
    if (text.isEmpty && !widget.controller.isConnected) return;

    if (_isCtrlActive && text.isNotEmpty) {
      final firstChar = text[0].toUpperCase();
      final asciiCode = firstChar.codeUnitAt(0) - 64;
      if (asciiCode >= 1 && asciiCode <= 26) {
        widget.controller.sendRawKeystroke(String.fromCharCode(asciiCode));
      }
      setState(() => _isCtrlActive = false);
    } else {
      widget.controller.sendInput(text);
      _historyIndex = widget.controller.history.length;
    }

    _inputController.clear();
  }

  void _sendSpecialKey(String code) {
    HapticFeedback.lightImpact();
    widget.controller.sendRawKeystroke(code);
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = widget.controller.isConnected;
    final isConnecting = widget.controller.isConnecting;
    final selectedTarget = widget.activeHost;
    final connectedHost = widget.controller.connectedHost;

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(
          isConnected && connectedHost != null
              ? 'Terminal · ${connectedHost.name}'
              : 'Terminal',
        ),
        backgroundColor: DeckColors.background,
        elevation: 0,
        actions: [
          if (isConnected) ...[
            IconButton(
              icon: const Icon(Icons.remove, size: 18),
              tooltip: 'Smaller font',
              onPressed: () => widget.controller
                  .setFontSize(widget.controller.fontSize - 1),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              tooltip: 'Larger font',
              onPressed: () => widget.controller
                  .setFontSize(widget.controller.fontSize + 1),
            ),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Copy buffer',
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(text: widget.controller.buffer),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Terminal output copied to clipboard'),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.clear_all, size: 18),
              tooltip: 'Clear screen',
              onPressed: widget.controller.clearBuffer,
            ),
            IconButton(
              icon: const Icon(
                Icons.power_settings_new,
                size: 18,
                color: DeckColors.error,
              ),
              tooltip: 'Disconnect',
              onPressed: widget.controller.disconnect,
            ),
          ],
        ],
      ),
      body: SafeArea(
        child: isConnected
            ? _buildActiveTerminalView(connectedHost, selectedTarget)
            : _buildLandingState(selectedTarget, isConnecting),
      ),
    );
  }

  Widget _buildLandingState(HostTarget? host, bool isConnecting) {
    final reachColor = host == null
        ? DeckColors.mutedText
        : switch (host.peerStatus) {
            PeerStatus.online => DeckColors.healthy,
            PeerStatus.connecting => DeckColors.informational,
            PeerStatus.unreachable || PeerStatus.offline => DeckColors.error,
            PeerStatus.unknown => DeckColors.mutedText,
          };

    final sshColor = host == null
        ? DeckColors.mutedText
        : switch (host.sshStatus) {
            ServiceStatus.available => DeckColors.healthy,
            ServiceStatus.connecting => DeckColors.informational,
            ServiceStatus.unavailable => DeckColors.error,
            ServiceStatus.unknown => DeckColors.mutedText,
          };

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: DeckColors.surfaceSecondary,
              shape: BoxShape.circle,
              border: Border.all(color: DeckColors.borderSubtle, width: 1),
            ),
            child: const Icon(
              Icons.terminal,
              size: 30,
              color: DeckColors.primaryAccent,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Interactive PTY Terminal',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Establish an encrypted xterm-256color shell directly into your selected target workstation.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 24),

          // Target Host Identity & Connection State Card
          Container(
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
                    const Icon(
                      Icons.ads_click,
                      size: 14,
                      color: DeckColors.primaryAccent,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'TARGET IDENTITY',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            letterSpacing: 0.8,
                            fontWeight: FontWeight.w700,
                            color: DeckColors.secondaryText,
                          ),
                    ),
                    const Spacer(),
                    PopupMenuButton<HostTarget>(
                      tooltip: 'Change target device',
                      onSelected: widget.onSelectHost,
                      color: DeckColors.surfaceElevated,
                      itemBuilder: (ctx) => widget.hosts.map((h) {
                        return PopupMenuItem(
                          value: h,
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  h.name,
                                  style: const TextStyle(
                                    color: DeckColors.primaryText,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                h.reachabilityLabel,
                                style: const TextStyle(
                                  color: DeckColors.secondaryText,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: DeckColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: DeckColors.borderSubtle),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Change target',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: DeckColors.primaryAccent,
                              ),
                            ),
                            SizedBox(width: 4),
                            Icon(
                              Icons.unfold_more,
                              size: 14,
                              color: DeckColors.primaryAccent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      host?.os == HostOs.windows
                          ? Icons.window
                          : Icons.terminal,
                      size: 22,
                      color: DeckColors.primaryAccent,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            host?.name ?? 'No host selected',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                              color: DeckColors.primaryText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            host != null
                                ? '${host.osDisplayName} · ${host.username}@${host.tailscaleIp}:${host.port}'
                                : 'Select a peer device to connect',
                            style: const TextStyle(
                              fontSize: 12,
                              color: DeckColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (host != null) ...[
                  const Divider(color: DeckColors.borderSubtle, height: 22),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Host reachability',
                        style: TextStyle(
                          fontSize: 12,
                          color: DeckColors.secondaryText,
                        ),
                      ),
                      Text(
                        host.hasFreshLatency
                            ? '${host.reachabilityLabel} (${host.pingMs} ms)'
                            : host.reachabilityLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: reachColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'SSH service state',
                        style: TextStyle(
                          fontSize: 12,
                          color: DeckColors.secondaryText,
                        ),
                      ),
                      Text(
                        host.sshStatusLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: sshColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Connect Primary Action
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              icon: isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: DeckColors.background,
                      ),
                    )
                  : const Icon(Icons.login, size: 18),
              label: Text(
                isConnecting
                    ? 'Connecting to ${host?.name ?? "host"}...'
                    : 'Connect to ${host?.name ?? "Host"}',
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
              onPressed: isConnecting || host == null
                  ? null
                  : () => _handleConnect(explicitTarget: host),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveTerminalView(
    HostTarget? connectedHost,
    HostTarget? selectedTarget,
  ) {
    final host = connectedHost ?? selectedTarget;
    final isTargetMismatch = connectedHost != null &&
        selectedTarget != null &&
        connectedHost.id != selectedTarget.id;

    return Column(
      children: [
        // Status Bar showing actual connected PTY host
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: const BoxDecoration(
            color: DeckColors.surfaceSecondary,
            border: Border(
              bottom: BorderSide(color: DeckColors.borderSubtle, width: 1),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: DeckColors.healthy,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LIVE PTY · ${host?.username}@${host?.name} (${host?.tailscaleIp})',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: DeckColors.healthy,
                  ),
                ),
              ),
              Text(
                '${widget.controller.fontSize.toInt()}sp',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: DeckColors.mutedText,
                ),
              ),
            ],
          ),
        ),

        // Safety Banner if global target changed while PTY remains on original host
        if (isTargetMismatch)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: DeckColors.warning.withValues(alpha: 0.14),
              border: const Border(
                bottom: BorderSide(color: DeckColors.borderSubtle, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: DeckColors.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Active shell is on ${connectedHost.name}. Selected target is ${selectedTarget.name}.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: DeckColors.primaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _handleConnect(
                    explicitTarget: selectedTarget,
                    forceReconnect: true,
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: DeckColors.primaryAccent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(48, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    'Switch to ${selectedTarget.name}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

        // Terminal Output Screen
        Expanded(
          child: Container(
            width: double.infinity,
            color: DeckColors.background,
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              controller: _scrollController,
              child: SelectableText(
                widget.controller.buffer.isEmpty
                    ? '// Terminal connected to ${host?.name ?? "host"}. Ready.\r\n'
                    : widget.controller.buffer,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: widget.controller.fontSize,
                  color: DeckColors.terminalText,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ),

        // Mobile Hardware Modifier Keybar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: const BoxDecoration(
            color: DeckColors.surfaceSecondary,
            border: Border(
              top: BorderSide(color: DeckColors.borderSubtle, width: 1),
            ),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildKeybarChip(
                  'CTRL',
                  isActive: _isCtrlActive,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _isCtrlActive = !_isCtrlActive);
                  },
                ),
                _buildKeybarChip(
                  'CTRL-C',
                  onTap: () => _sendSpecialKey('\x03'),
                ),
                _buildKeybarChip('ESC', onTap: () => _sendSpecialKey('\x1b')),
                _buildKeybarChip('TAB', onTap: () => _sendSpecialKey('\t')),
                _buildKeybarChip('|', onTap: () => _sendSpecialKey('|')),
                _buildKeybarChip('~', onTap: () => _sendSpecialKey('~')),
                _buildKeybarChip('/', onTap: () => _sendSpecialKey('/')),
                _buildKeybarChip(
                  '↑',
                  onTap: () {
                    final h = widget.controller.history;
                    if (h.isNotEmpty && _historyIndex > 0) {
                      _historyIndex--;
                      _inputController.text = h[_historyIndex];
                    } else {
                      _sendSpecialKey('\x1b[A');
                    }
                  },
                ),
                _buildKeybarChip(
                  '↓',
                  onTap: () {
                    final h = widget.controller.history;
                    if (h.isNotEmpty && _historyIndex < h.length - 1) {
                      _historyIndex++;
                      _inputController.text = h[_historyIndex];
                    } else {
                      _sendSpecialKey('\x1b[B');
                    }
                  },
                ),
              ],
            ),
          ),
        ),

        // Input Line showing target prompt context
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            color: DeckColors.surfaceElevated,
            border: Border(
              top: BorderSide(color: DeckColors.borderSubtle, width: 1),
            ),
          ),
          child: Row(
            children: [
              Text(
                '${host?.name ?? ""}\$',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: DeckColors.primaryAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _inputController,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 13,
                    color: DeckColors.primaryText,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Run command on ${host?.name ?? "host"}...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    fillColor: Colors.transparent,
                  ),
                  onSubmitted: (_) => _handleSubmit(),
                ),
              ),
              IconButton(
                icon: const Icon(
                  Icons.arrow_upward,
                  size: 18,
                  color: DeckColors.primaryAccent,
                ),
                onPressed: _handleSubmit,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKeybarChip(
    String label, {
    bool isActive = false,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:
                isActive ? DeckColors.primaryAccent : DeckColors.surfaceElevated,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color:
                  isActive ? DeckColors.primaryAccent : DeckColors.borderSubtle,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isActive ? DeckColors.background : DeckColors.secondaryText,
            ),
          ),
        ),
      ),
    );
  }
}
