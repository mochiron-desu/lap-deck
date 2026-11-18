import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';

class TerminalBay extends StatefulWidget {
  final HostTarget? activeHost;
  final String terminalOutput;
  final bool isShellActive;
  final Function(String input) onSendInput;
  final VoidCallback onClearBuffer;
  final VoidCallback onToggleShell;

  const TerminalBay({
    super.key,
    required this.activeHost,
    required this.terminalOutput,
    required this.isShellActive,
    required this.onSendInput,
    required this.onClearBuffer,
    required this.onToggleShell,
  });

  @override
  State<TerminalBay> createState() => _TerminalBayState();
}

class _TerminalBayState extends State<TerminalBay> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isCtrlActive = false;
  final List<String> _history = [];
  int _historyIndex = -1;

  @override
  void didUpdateWidget(TerminalBay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.terminalOutput != oldWidget.terminalOutput) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSubmit() {
    final text = _inputController.text;
    if (text.isEmpty && !widget.isShellActive) return;

    if (_isCtrlActive && text.isNotEmpty) {
      final firstChar = text[0].toUpperCase();
      final asciiCode = firstChar.codeUnitAt(0) - 64;
      if (asciiCode >= 1 && asciiCode <= 26) {
        widget.onSendInput(String.fromCharCode(asciiCode));
      }
      setState(() => _isCtrlActive = false);
    } else {
      widget.onSendInput(text);
      if (text.trim().isNotEmpty) {
        _history.add(text);
        _historyIndex = _history.length;
      }
    }

    _inputController.clear();
  }

  void _sendSpecialKey(String code) {
    HapticFeedback.lightImpact();
    widget.onSendInput(code);
  }

  @override
  Widget build(BuildContext context) {
    final host = widget.activeHost;

    return Container(
      decoration: BoxDecoration(
        color: DeckColors.surfaceInset,
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        children: [
          // Terminal Chassis Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: DeckColors.surfaceRack,
              border: Border(
                bottom: BorderSide(color: DeckColors.borderSubtle, width: 1),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: widget.isShellActive ? DeckColors.phosphorGreen : DeckColors.offlineSteel,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isShellActive ? 'LIVE PTY SESSION' : 'OUTPUT BUFFER',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: widget.isShellActive ? DeckColors.phosphorGreen : DeckColors.textMid,
                  ),
                ),
                Text(
                  ' • ${host?.username ?? "user"}@${host?.name ?? "host"}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: DeckColors.textMuted,
                  ),
                ),
                const Spacer(),
                // Shell toggle action
                InkWell(
                  onTap: widget.onToggleShell,
                  borderRadius: BorderRadius.circular(2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.isShellActive
                          ? DeckColors.alertCrimson.withValues(alpha: 0.15)
                          : DeckColors.accentOrange.withValues(alpha: 0.15),
                      border: Border.all(
                        color: widget.isShellActive ? DeckColors.alertCrimson : DeckColors.accentOrange,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      widget.isShellActive ? 'DISCONNECT' : 'START PTY',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: widget.isShellActive ? DeckColors.alertCrimson : DeckColors.accentOrange,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: widget.onClearBuffer,
                  child: const Padding(
                    padding: EdgeInsets.all(2.0),
                    child: Icon(Icons.delete_sweep, size: 14, color: DeckColors.textMuted),
                  ),
                ),
              ],
            ),
          ),

          // Terminal Output Stream Area
          Expanded(
            child: Container(
              color: DeckColors.surfaceInset,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                controller: _scrollController,
                child: SelectableText(
                  widget.terminalOutput.isEmpty
                      ? '// TERMINAL READY\r\n// Select a command above or enter raw bash/powershell command below.\r\n'
                      : widget.terminalOutput,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.4,
                    color: DeckColors.textTerminal,
                  ),
                ),
              ),
            ),
          ),

          // Hardware Modifier Keybar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: const BoxDecoration(
              color: DeckColors.surfaceRack,
              border: Border(
                top: BorderSide(color: DeckColors.borderSubtle, width: 1),
              ),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _KeybarButton(
                    label: 'CTRL',
                    isActive: _isCtrlActive,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _isCtrlActive = !_isCtrlActive);
                    },
                  ),
                  _KeybarButton(
                    label: 'CTRL-C',
                    onTap: () => _sendSpecialKey('\x03'),
                  ),
                  _KeybarButton(
                    label: 'ESC',
                    onTap: () => _sendSpecialKey('\x1b'),
                  ),
                  _KeybarButton(
                    label: 'TAB',
                    onTap: () => _sendSpecialKey('\t'),
                  ),
                  _KeybarButton(
                    label: '|',
                    onTap: () => _sendSpecialKey('|'),
                  ),
                  _KeybarButton(
                    label: '~',
                    onTap: () => _sendSpecialKey('~'),
                  ),
                  _KeybarButton(
                    label: '/',
                    onTap: () => _sendSpecialKey('/'),
                  ),
                  _KeybarButton(
                    label: '↑',
                    onTap: () {
                      if (_history.isNotEmpty && _historyIndex > 0) {
                        _historyIndex--;
                        _inputController.text = _history[_historyIndex];
                      } else {
                        _sendSpecialKey('\x1b[A');
                      }
                    },
                  ),
                  _KeybarButton(
                    label: '↓',
                    onTap: () {
                      if (_history.isNotEmpty && _historyIndex < _history.length - 1) {
                        _historyIndex++;
                        _inputController.text = _history[_historyIndex];
                      } else {
                        _sendSpecialKey('\x1b[B');
                      }
                    },
                  ),
                ],
              ),
            ),
          ),

          // Command Input Field
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: DeckColors.surfaceElevated,
              border: Border(
                top: BorderSide(color: DeckColors.borderSubtle, width: 1),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '\$',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: DeckColors.accentOrange,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _inputController,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: DeckColors.textHigh,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Enter command or shell keystroke...',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      fillColor: Colors.transparent,
                    ),
                    onSubmitted: (_) => _handleSubmit(),
                  ),
                ),
                InkWell(
                  onTap: _handleSubmit,
                  borderRadius: BorderRadius.circular(3),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: DeckColors.accentOrange,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      'RUN',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: DeckColors.surfaceCore,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
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

class _KeybarButton extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _KeybarButton({
    required this.label,
    this.isActive = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(3),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isActive ? DeckColors.accentOrange : DeckColors.surfaceInset,
            border: Border.all(
              color: isActive ? DeckColors.accentOrange : DeckColors.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: isActive ? DeckColors.surfaceCore : DeckColors.textMid,
            ),
          ),
        ),
      ),
    );
  }
}
