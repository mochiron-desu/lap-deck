import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/connector_models.dart';
import '../../models/host_target.dart';
import '../../services/connector_service.dart';
import '../../services/notification_service.dart';
import '../../services/storage_service.dart';
import '../../theme/deck_theme.dart';

/// Full-featured Antigravity AI Conversation screen & reusable console view.
/// Connects to a peer workstation's PeerServer (:8765), streams live NDJSON turns,
/// supports thinking accordions, real-time tool pills, session switching,
/// workspace/model switching, and mid-turn aborting.
class AiChatScreen extends StatefulWidget {
  final HostTarget initialHost;
  final List<HostTarget> availableHosts;
  final StorageService storage;
  final ConnectorService connectorService;
  final NotificationService? notificationService;
  final bool isEmbedded;

  const AiChatScreen({
    super.key,
    required this.initialHost,
    required this.availableHosts,
    required this.storage,
    required this.connectorService,
    this.notificationService,
    this.isEmbedded = false,
  });

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen>
    with WidgetsBindingObserver {
  late HostTarget _targetHost;
  String? _activeConversationId;
  String _activeWorkspace = '';
  String _activeModel = 'gemini-3.8-flash-medium';
  List<AiConversationTurn> _turns = [];
  List<Map<String, dynamic>> _availableModels = [];
  List<ConnectorWorkspaceTarget> _availableWorkspaces = [];

  bool _isLoadingHistory = true;
  bool _isStreaming = false;
  String? _errorBanner;
  final Set<int> _expandedThinkingIndices = {};

  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<AiStreamEvent>? _streamSub;
  Timer? _watchdogTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _targetHost = widget.initialHost;
    _loadInitialSession();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reconcileSessionWithPeer(silent: true);
    }
  }

  @override
  void didUpdateWidget(covariant AiChatScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isEmbedded &&
        oldWidget.initialHost.id != widget.initialHost.id &&
        !_isStreaming) {
      _targetHost = widget.initialHost;
      _loadInitialSession();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopWatchdogTimer();
    _streamSub?.cancel();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _startWatchdogTimer() {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!_isStreaming || !mounted) {
        _stopWatchdogTimer();
        return;
      }
      _reconcileSessionWithPeer(silent: true);
    });
  }

  void _stopWatchdogTimer() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  /// Normalizes turns so historical or past turns are never stuck in 'streaming'.
  List<AiConversationTurn> _sanitizeTurns(
    List<AiConversationTurn> turns, {
    required bool isRunning,
  }) {
    if (turns.isEmpty) return turns;
    final result = <AiConversationTurn>[];
    for (int i = 0; i < turns.length; i++) {
      final turn = turns[i];
      final isLast = (i == turns.length - 1);
      if (turn.status == AiTurnStatus.streaming) {
        if (!isLast || !isRunning) {
          final resolved = turn.response.isNotEmpty
              ? AiTurnStatus.completed
              : (turn.tools.isNotEmpty
                  ? AiTurnStatus.completed
                  : AiTurnStatus.aborted);
          result.add(
            turn.copyWith(
              status: resolved,
              clearCurrentTool: true,
            ),
          );
          continue;
        }
      }
      result.add(turn);
    }
    return result;
  }

  /// Reconciles session state with peer node when app resumes or watchdog ticks.
  Future<void> _reconcileSessionWithPeer({bool silent = true}) async {
    if (!mounted) return;
    final capturedHost = _targetHost;
    final capturedConvId = _activeConversationId;

    try {
      final secret = await widget.storage.getConnectorToken(capturedHost.id);
      final historyRes = await widget.connectorService.fetchConversationHistory(
        capturedHost,
        conversationId: capturedConvId,
        secret: secret,
      );

      if (!mounted || _targetHost.id != capturedHost.id) return;

      if (historyRes['ok'] == true) {
        final isPeerRunning = historyRes['isRunning'] == true;
        final rawTurns =
            (historyRes['turns'] as List<AiConversationTurn>?) ?? [];
        final peerConvId = historyRes['conversationId']?.toString();

        if (peerConvId != null && peerConvId.isNotEmpty) {
          _activeConversationId = peerConvId;
        }

        if (_isStreaming && !isPeerRunning) {
          // Completed while backgrounded or disconnected
          _stopWatchdogTimer();
          await _streamSub?.cancel();
          _streamSub = null;

          final sanitized = _sanitizeTurns(rawTurns, isRunning: false);
          final completedTurn =
              sanitized.isNotEmpty ? sanitized.last : null;
          final isSuccess = completedTurn != null &&
              completedTurn.status == AiTurnStatus.completed;

          setState(() {
            _isStreaming = false;
            _turns = sanitized;
          });

          if (completedTurn != null) {
            widget.notificationService?.notifyAiTurnFinished(
              hostName: capturedHost.name,
              isSuccess: isSuccess,
              summary: completedTurn.response.isNotEmpty
                  ? completedTurn.response
                  : (isSuccess
                      ? 'Prompt completed on ${capturedHost.name}'
                      : (completedTurn.errorMessage ?? 'Turn finished')),
            );
          }
          _scrollToBottom();
        } else if (_isStreaming && isPeerRunning) {
          // Still active on peer: sync thoughts/tools
          if (rawTurns.isNotEmpty) {
            final latest = rawTurns.last;
            setState(() {
              if (_turns.isNotEmpty) {
                final lastIdx = _turns.length - 1;
                final current = _turns[lastIdx];
                final updatedTools = List<String>.from(current.tools);
                for (final t in latest.tools) {
                  if (!updatedTools.contains(t)) updatedTools.add(t);
                }
                _turns[lastIdx] = current.copyWith(
                  thinking: latest.thinking.isNotEmpty
                      ? latest.thinking
                      : current.thinking,
                  response: latest.response.isNotEmpty
                      ? latest.response
                      : current.response,
                  tools: updatedTools,
                  currentTool: latest.currentTool,
                );
              }
            });
            _scrollToBottom();
          }
        } else if (!_isStreaming) {
          final sanitized =
              _sanitizeTurns(rawTurns, isRunning: isPeerRunning);
          setState(() {
            _turns = sanitized;
          });
        }
      }
    } catch (_) {
      // Background reconciliation should remain silent
    }
  }

  Future<String> _getSecret() async {
    return await widget.storage.getConnectorToken(_targetHost.id);
  }

  Future<void> _loadInitialSession({String? explicitConvId}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingHistory = true;
      _errorBanner = null;
    });

    final capturedHost = _targetHost;
    try {
      final secret = await widget.storage.getConnectorToken(capturedHost.id);
      final results = await Future.wait([
        widget.connectorService.fetchConversationHistory(
          capturedHost,
          conversationId: explicitConvId,
          secret: secret,
        ),
        widget.connectorService.fetchPeerTargetConfig(
          capturedHost,
          secret: secret,
        ),
        widget.connectorService.fetchAvailableModels(
          capturedHost,
          secret: secret,
        ),
      ]);

      if (!mounted || _targetHost.id != capturedHost.id) return;

      final historyRes = results[0] as Map<String, dynamic>;
      final targetCfg = results[1] as ConnectorTargetConfig?;
      final models = results[2] as List<Map<String, dynamic>>;

      setState(() {
        _availableModels = models;
        if (targetCfg != null) {
          _availableWorkspaces = targetCfg.availableWorkspaces;
          if (targetCfg.workspace.isNotEmpty) {
            _activeWorkspace = targetCfg.workspace;
          }
          if (targetCfg.model != null && targetCfg.model!.isNotEmpty) {
            _activeModel = targetCfg.model!;
          }
        }

        if (historyRes['ok'] == true) {
          _activeConversationId =
              explicitConvId ?? historyRes['conversationId']?.toString();
          final ws = historyRes['workspace']?.toString();
          if (ws != null && ws.isNotEmpty) _activeWorkspace = ws;
          final mdl = historyRes['model']?.toString();
          if (mdl != null && mdl.isNotEmpty) _activeModel = mdl;
          final isRunning = historyRes['isRunning'] == true;
          final rawTurns =
              (historyRes['turns'] as List<AiConversationTurn>?) ?? [];
          _turns = _sanitizeTurns(rawTurns, isRunning: isRunning);

          if (!isRunning && _isStreaming) {
            _isStreaming = false;
            _stopWatchdogTimer();
            _streamSub?.cancel();
            _streamSub = null;
          }
        } else {
          _errorBanner = historyRes['error']?.toString() ??
              'Could not load AI session from ${capturedHost.name} on port ${ConnectorService.defaultPort}.';
        }
        _isLoadingHistory = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorBanner = 'Failed connecting to ${capturedHost.name}: $e';
        _isLoadingHistory = false;
      });
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSendPrompt() async {
    final text = _promptController.text.trim();
    if (text.isEmpty || _isStreaming) return;

    HapticFeedback.lightImpact();
    _promptController.clear();

    // Capture target machine identity at operation start (Rule 5.4 / Section 8.2)
    final capturedHost = _targetHost;
    final capturedConvId = _activeConversationId;
    final capturedWorkspace = _activeWorkspace;
    final capturedModel = _activeModel;

    // Sanitize any existing turns so no earlier turn is stuck in streaming
    final sanitizedPriorTurns = _turns.map((t) {
      if (t.status == AiTurnStatus.streaming) {
        return t.copyWith(
          status: t.response.isNotEmpty
              ? AiTurnStatus.completed
              : (t.tools.isNotEmpty
                  ? AiTurnStatus.completed
                  : AiTurnStatus.aborted),
          clearCurrentTool: true,
        );
      }
      return t;
    }).toList();

    final turnIndex = sanitizedPriorTurns.length;
    final newTurn = AiConversationTurn(
      stepIndex: turnIndex,
      prompt: text,
      status: AiTurnStatus.streaming,
      createdAt: DateTime.now().toIso8601String(),
    );

    setState(() {
      _isStreaming = true;
      _errorBanner = null;
      _turns = [...sanitizedPriorTurns, newTurn];
    });
    _scrollToBottom();
    _startWatchdogTimer();

    final secret = await widget.storage.getConnectorToken(capturedHost.id);
    final stream = widget.connectorService.streamAgentTurn(
      capturedHost,
      prompt: text,
      conversationId: capturedConvId,
      workspace: capturedWorkspace.isNotEmpty ? capturedWorkspace : null,
      model: capturedModel.isNotEmpty ? capturedModel : null,
      secret: secret,
    );

    _streamSub = stream.listen(
      (event) {
        if (!mounted) return;
        setState(() {
          final current = _turns[turnIndex];
          if (event.event == 'init' &&
              event.conversationId != null &&
              event.conversationId!.isNotEmpty) {
            _activeConversationId = event.conversationId;
          } else if (event.event == 'thinking' && event.thinking != null) {
            _turns[turnIndex] = current.copyWith(thinking: event.thinking);
          } else if (event.event == 'stream') {
            final updatedTools = List<String>.from(current.tools);
            if (event.currentTool != null &&
                event.currentTool!.isNotEmpty &&
                !updatedTools.contains(event.currentTool)) {
              updatedTools.add(event.currentTool!);
            }
            _turns[turnIndex] = current.copyWith(
              response: event.accumulatedText ?? current.response,
              currentTool: event.currentTool,
              clearCurrentTool: event.currentTool == null,
              tools: updatedTools,
            );
          } else if (event.event == 'final') {
            _stopWatchdogTimer();
            if (event.conversationId != null &&
                event.conversationId!.isNotEmpty) {
              _activeConversationId = event.conversationId;
            }
            final isOk = event.ok == true;
            final finalResp = (event.responseText != null &&
                    event.responseText!.trim().isNotEmpty)
                ? event.responseText!
                : current.response;
            _turns[turnIndex] = current.copyWith(
              response: finalResp,
              clearCurrentTool: true,
              status: isOk ? AiTurnStatus.completed : AiTurnStatus.error,
              totalTokens: event.totalTokens ?? current.totalTokens,
              durationSeconds:
                  event.durationSeconds ?? current.durationSeconds,
              errorMessage: event.error,
            );
            _isStreaming = false;
            widget.notificationService?.notifyAiTurnFinished(
              hostName: capturedHost.name,
              isSuccess: isOk,
              summary: isOk
                  ? (finalResp.isNotEmpty
                      ? finalResp
                      : 'Completed prompt: $text')
                  : (event.error ?? 'Turn failed on ${capturedHost.name}'),
            );
          }
        });
        _scrollToBottom();
      },
      onError: (e) {
        if (!mounted) return;
        _stopWatchdogTimer();
        setState(() {
          _turns[turnIndex] = _turns[turnIndex].copyWith(
            status: AiTurnStatus.error,
            clearCurrentTool: true,
            errorMessage: e.toString(),
          );
          _isStreaming = false;
        });
        // Check with peer in case the operation completed while stream dropped
        _reconcileSessionWithPeer(silent: true);
      },
      onDone: () {
        if (!mounted) return;
        _stopWatchdogTimer();
        if (_isStreaming) {
          setState(() {
            _turns[turnIndex] = _turns[turnIndex].copyWith(
              status: _turns[turnIndex].response.isNotEmpty
                  ? AiTurnStatus.completed
                  : AiTurnStatus.error,
              clearCurrentTool: true,
            );
            _isStreaming = false;
          });
          _reconcileSessionWithPeer(silent: true);
        }
      },
    );
  }

  Future<void> _handleAbortTurn() async {
    if (!_isStreaming) return;
    HapticFeedback.heavyImpact();
    _stopWatchdogTimer();
    await _streamSub?.cancel();
    _streamSub = null;

    final capturedHost = _targetHost;
    final secret = await _getSecret();
    await widget.connectorService.abortAgentTurn(capturedHost, secret: secret);

    if (!mounted) return;
    setState(() {
      _isStreaming = false;
      if (_turns.isNotEmpty && _turns.last.status == AiTurnStatus.streaming) {
        final lastIdx = _turns.length - 1;
        _turns[lastIdx] = _turns[lastIdx].copyWith(
          status: AiTurnStatus.aborted,
          clearCurrentTool: true,
          errorMessage: 'Aborted by operator from LapDeck AI Console.',
        );
      }
    });
  }

  Future<void> _handleNewConversation() async {
    if (_isStreaming) return;
    HapticFeedback.mediumImpact();
    final secret = await _getSecret();
    await widget.connectorService.startNewConversation(
      _targetHost,
      workspace: _activeWorkspace.isNotEmpty ? _activeWorkspace : null,
      model: _activeModel.isNotEmpty ? _activeModel : null,
      secret: secret,
    );
    if (!mounted) return;
    setState(() {
      _activeConversationId = null;
      _turns = [];
      _expandedThinkingIndices.clear();
      _errorBanner = null;
    });
  }

  void _showSessionHistorySheet() {
    final searchCtrl = TextEditingController();
    List<AiSessionSummary> results = [];
    bool isSearching = true;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DeckColors.surfaceSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: DeckColors.borderMedium),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            Future<void> runSearch(String q) async {
              setSheetState(() => isSearching = true);
              final secret = await _getSecret();
              final found = await widget.connectorService.searchConversations(
                _targetHost,
                query: q,
                limit: 20,
                secret: secret,
              );
              if (ctx.mounted) {
                setSheetState(() {
                  results = found;
                  isSearching = false;
                });
              }
            }

            if (isSearching && results.isEmpty && searchCtrl.text.isEmpty) {
              Future.microtask(() => runSearch(''));
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 14,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
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
                        const Icon(
                          Icons.history,
                          color: DeckColors.primaryAccent,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Conversations · ${_targetHost.name}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: DeckColors.primaryText,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetCtx);
                            _handleNewConversation();
                          },
                          icon: const Icon(
                            Icons.add_comment_outlined,
                            size: 16,
                            color: DeckColors.primaryAccent,
                          ),
                          label: const Text(
                            'New Session',
                            style: TextStyle(
                              color: DeckColors.primaryAccent,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: searchCtrl,
                      onSubmitted: runSearch,
                      style: const TextStyle(
                        fontSize: 13,
                        color: DeckColors.primaryText,
                      ),
                      decoration: InputDecoration(
                        hintText:
                            'Search past conversations by keyword or UUID...',
                        hintStyle: const TextStyle(
                          fontSize: 12,
                          color: DeckColors.mutedText,
                        ),
                        prefixIcon: const Icon(
                          Icons.search,
                          size: 18,
                          color: DeckColors.secondaryText,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.arrow_forward,
                            size: 18,
                            color: DeckColors.primaryAccent,
                          ),
                          tooltip: 'Search conversations',
                          onPressed: () => runSearch(searchCtrl.text),
                        ),
                        filled: true,
                        fillColor: DeckColors.surfaceElevated,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: DeckColors.borderSubtle),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                      ),
                      child: isSearching
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 28),
                              child: Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: DeckColors.primaryAccent,
                                ),
                              ),
                            )
                          : results.isEmpty
                              ? const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 24),
                                  child: Center(
                                    child: Text(
                                      'No indexed conversations found on this peer.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: DeckColors.mutedText,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  itemCount: results.length,
                                  separatorBuilder: (_, __) =>
                                      const SizedBox(height: 8),
                                  itemBuilder: (_, idx) {
                                    final item = results[idx];
                                    final isCurrent = item.conversationId ==
                                        _activeConversationId;
                                    final shortId =
                                        item.conversationId.length > 8
                                            ? item.conversationId
                                                .substring(0, 8)
                                            : item.conversationId;
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(10),
                                      onTap: () {
                                        Navigator.pop(sheetCtx);
                                        _loadInitialSession(
                                          explicitConvId: item.conversationId,
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: isCurrent
                                              ? DeckColors.surfaceHighlight
                                              : DeckColors.background,
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          border: Border.all(
                                            color: isCurrent
                                                ? DeckColors.primaryAccent
                                                : DeckColors.borderSubtle,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: DeckColors
                                                        .primaryAccent
                                                        .withValues(
                                                            alpha: 0.14),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            4),
                                                  ),
                                                  child: Text(
                                                    shortId,
                                                    style: GoogleFonts
                                                        .jetBrainsMono(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: DeckColors
                                                          .primaryAccent,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                if (item.workspace.isNotEmpty)
                                                  Expanded(
                                                    child: Text(
                                                      item.workspace,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: GoogleFonts
                                                          .jetBrainsMono(
                                                        fontSize: 10,
                                                        color: DeckColors
                                                            .secondaryText,
                                                      ),
                                                    ),
                                                  ),
                                                if (isCurrent)
                                                  const Text(
                                                    'ACTIVE',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: DeckColors.healthy,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              item.previewPrompt.isNotEmpty
                                                  ? item.previewPrompt
                                                  : '(Conversation session)',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: DeckColors.primaryText,
                                                height: 1.35,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showWorkspaceAndModelSheet() {
    final wsCtrl = TextEditingController(text: _activeWorkspace);
    String selectedModel = _activeModel;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DeckColors.surfaceSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: DeckColors.borderMedium),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 20,
                  right: 20,
                  top: 14,
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                ),
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
                    Text(
                      'AI Context & Model · ${_targetHost.name}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: DeckColors.primaryText,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'TARGET WORKSPACE DIRECTORY',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: DeckColors.mutedText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: wsCtrl,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: DeckColors.primaryText,
                      ),
                      decoration: InputDecoration(
                        hintText: '/home/surajwork/Coding/misc/lap-deck',
                        filled: true,
                        fillColor: DeckColors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    if (_availableWorkspaces.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _availableWorkspaces.take(8).map((w) {
                          final isSel = wsCtrl.text.trim() == w.path;
                          return ActionChip(
                            backgroundColor: isSel
                                ? DeckColors.surfaceHighlight
                                : DeckColors.background,
                            side: BorderSide(
                              color: isSel
                                  ? DeckColors.primaryAccent
                                  : DeckColors.borderSubtle,
                            ),
                            label: Text(
                              w.name,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: isSel
                                    ? DeckColors.primaryAccent
                                    : DeckColors.secondaryText,
                              ),
                            ),
                            onPressed: () {
                              setSheetState(() => wsCtrl.text = w.path);
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      'AI MODEL',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: DeckColors.mutedText,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: _availableModels
                              .any((m) => m['model_id'] == selectedModel)
                          ? selectedModel
                          : (_availableModels.isNotEmpty
                              ? _availableModels.first['model_id']?.toString()
                              : selectedModel),
                      dropdownColor: DeckColors.surfaceElevated,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: DeckColors.surfaceElevated,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      items: _availableModels.map((m) {
                        final id = m['model_id']?.toString() ?? '';
                        final label = m['label']?.toString() ?? id;
                        final pct = m['remaining_pct'];
                        final suffix = pct != null ? ' ($pct%)' : '';
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Text(
                            '$label$suffix',
                            style: const TextStyle(
                              fontSize: 13,
                              color: DeckColors.primaryText,
                            ),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setSheetState(() => selectedModel = val);
                        }
                      },
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DeckColors.primaryAccent,
                          foregroundColor: Colors.black,
                          minimumSize: const Size.fromHeight(48),
                        ),
                        onPressed: () async {
                          final newWs = wsCtrl.text.trim();
                          Navigator.pop(sheetCtx);
                          final secret = await _getSecret();
                          await widget.connectorService.updatePeerTarget(
                            _targetHost,
                            workspace: newWs.isNotEmpty ? newWs : null,
                            model: selectedModel,
                            secret: secret,
                          );
                          if (mounted) {
                            setState(() {
                              if (newWs.isNotEmpty) _activeWorkspace = newWs;
                              _activeModel = selectedModel;
                            });
                          }
                        },
                        child: const Text(
                          'Apply Context Settings',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      children: [
        _buildContextHeaderBar(),
        if (_errorBanner != null) _buildErrorBanner(),
        Expanded(
          child: _isLoadingHistory
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DeckColors.primaryAccent,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Syncing AI session from ${_targetHost.name}...',
                        style: const TextStyle(
                          fontSize: 13,
                          color: DeckColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                )
              : _turns.isEmpty
                  ? _buildEmptyConversationState()
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      itemCount: _turns.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 14),
                      itemBuilder: (ctx, idx) => _buildTurnCard(idx, _turns[idx]),
                    ),
        ),
        _buildPromptInputBar(),
      ],
    );

    if (widget.isEmbedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: DeckColors.background,
      appBar: AppBar(
        backgroundColor: DeckColors.background,
        elevation: 0,
        title: Text('AI Console · ${_targetHost.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, size: 20),
            tooltip: 'Browse or search conversations',
            onPressed: _showSessionHistorySheet,
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, size: 20),
            tooltip: 'Start new conversation',
            onPressed: _isStreaming ? null : _handleNewConversation,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: 'Reload active conversation',
            onPressed: _isStreaming ? null : () => _loadInitialSession(),
          ),
        ],
      ),
      body: SafeArea(child: content),
    );
  }

  Widget _buildContextHeaderBar() {
    final shortConv = (_activeConversationId != null &&
            _activeConversationId!.isNotEmpty)
        ? (_activeConversationId!.length > 8
            ? _activeConversationId!.substring(0, 8)
            : _activeConversationId!)
        : 'NEW SESSION';
    final wsBasename = _activeWorkspace.isNotEmpty
        ? _activeWorkspace.split(RegExp(r'[/\\]')).last
        : 'Default Workspace';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: DeckColors.surfaceSecondary,
        border: Border(
          bottom: BorderSide(color: DeckColors.borderSubtle, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Host selector pill if multiple hosts enrolled
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _isStreaming || widget.availableHosts.length <= 1
                    ? null
                    : () {
                        final idx = widget.availableHosts
                            .indexWhere((h) => h.id == _targetHost.id);
                        final nextHost = widget.availableHosts[
                            (idx + 1) % widget.availableHosts.length];
                        setState(() => _targetHost = nextHost);
                        _loadInitialSession();
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: DeckColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: DeckColors.borderMedium),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _targetHost.os == HostOs.windows
                            ? Icons.desktop_windows_outlined
                            : Icons.laptop_chromebook,
                        size: 13,
                        color: DeckColors.primaryAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _targetHost.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: DeckColors.primaryText,
                        ),
                      ),
                      if (widget.availableHosts.length > 1) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.swap_horiz,
                          size: 13,
                          color: DeckColors.secondaryText,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Conversation UUID badge (tappable to open history)
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: _showSessionHistorySheet,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: DeckColors.primaryAccent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chat_bubble_outline,
                        size: 11,
                        color: DeckColors.primaryAccent,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        shortConv,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: DeckColors.primaryAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              if (widget.isEmbedded) ...[
                IconButton(
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.history,
                    size: 18,
                    color: DeckColors.secondaryText,
                  ),
                  tooltip: 'Session History',
                  onPressed: _showSessionHistorySheet,
                ),
                IconButton(
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.add_comment_outlined,
                    size: 18,
                    color: DeckColors.primaryAccent,
                  ),
                  tooltip: 'New Conversation',
                  onPressed: _isStreaming ? null : _handleNewConversation,
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          // Second row: Workspace & Model quick pills
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: _isStreaming ? null : _showWorkspaceAndModelSheet,
            child: Row(
              children: [
                const Icon(
                  Icons.folder_open_outlined,
                  size: 13,
                  color: DeckColors.informational,
                ),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    wsBasename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: DeckColors.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                const Text('·', style: TextStyle(color: DeckColors.mutedText)),
                const SizedBox(width: 10),
                const Icon(
                  Icons.auto_awesome_outlined,
                  size: 13,
                  color: DeckColors.primaryAccent,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    _activeModel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: DeckColors.secondaryText,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.tune,
                  size: 12,
                  color: DeckColors.mutedText,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: DeckColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DeckColors.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: DeckColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorBanner!,
              style: const TextStyle(
                fontSize: 12,
                color: DeckColors.primaryText,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _loadInitialSession(),
            child: const Text(
              'Retry',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: DeckColors.primaryAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyConversationState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DeckColors.surfaceSecondary,
                shape: BoxShape.circle,
                border: Border.all(color: DeckColors.borderSubtle),
              ),
              child: const Icon(
                Icons.terminal_outlined,
                size: 28,
                color: DeckColors.primaryAccent,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Antigravity AI Console · ${_targetHost.name}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: DeckColors.primaryText,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Send a prompt to run an Antigravity agent turn directly on ${_targetHost.name} in ${_activeWorkspace.isNotEmpty ? _activeWorkspace : "the active workspace"}, or open Session History to resume an existing conversation.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: DeckColors.secondaryText,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: _showSessionHistorySheet,
                  icon: const Icon(Icons.history, size: 16),
                  label: const Text('Browse Past Sessions'),
                ),
                OutlinedButton.icon(
                  onPressed: _showWorkspaceAndModelSheet,
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('Change Workspace / Model'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTurnCard(int index, AiConversationTurn turn) {
    final isThinkingExpanded = _expandedThinkingIndices.contains(index);
    final isStreamingCard = turn.status == AiTurnStatus.streaming &&
        (index == _turns.length - 1) &&
        _isStreaming;
    final effectiveStatus =
        (turn.status == AiTurnStatus.streaming && !isStreamingCard)
            ? (turn.response.isNotEmpty || turn.tools.isNotEmpty
                ? AiTurnStatus.completed
                : AiTurnStatus.aborted)
            : turn.status;
    final statusColor = switch (effectiveStatus) {
      AiTurnStatus.streaming => DeckColors.primaryAccent,
      AiTurnStatus.completed => DeckColors.healthy,
      AiTurnStatus.error => DeckColors.error,
      AiTurnStatus.aborted => DeckColors.warning,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Operator Prompt Bubble
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.84,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: DeckColors.surfaceHighlight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DeckColors.borderMedium),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'OPERATOR',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: DeckColors.primaryAccent,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: turn.prompt));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Prompt copied to clipboard'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Icon(
                        Icons.copy,
                        size: 13,
                        color: DeckColors.mutedText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  turn.prompt,
                  style: const TextStyle(
                    fontSize: 13,
                    color: DeckColors.primaryText,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // 2. Antigravity Agent Response Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DeckColors.surfaceSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isStreamingCard
                  ? DeckColors.primaryAccent.withValues(alpha: 0.6)
                  : DeckColors.borderSubtle,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: Agent label + status badge + copy button
              Row(
                children: [
                  const Icon(
                    Icons.smart_toy_outlined,
                    size: 15,
                    color: DeckColors.primaryAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'ANTIGRAVITY · ${_targetHost.name.toUpperCase()}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: DeckColors.secondaryText,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isStreamingCard) ...[
                          SizedBox(
                            width: 9,
                            height: 9,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.6,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          effectiveStatus.label,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (turn.response.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: turn.response));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Agent response copied'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Icon(
                        Icons.copy,
                        size: 14,
                        color: DeckColors.mutedText,
                      ),
                    ),
                  ],
                ],
              ),

              // Thinking accordion if present
              if (turn.thinking.isNotEmpty) ...[
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    setState(() {
                      if (isThinkingExpanded) {
                        _expandedThinkingIndices.remove(index);
                      } else {
                        _expandedThinkingIndices.add(index);
                      }
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: DeckColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DeckColors.borderSubtle),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.psychology_outlined,
                              size: 14,
                              color: DeckColors.mutedText,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Agent Reasoning / Thinking',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: DeckColors.mutedText,
                              ),
                            ),
                            const Spacer(),
                            Icon(
                              isThinkingExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: DeckColors.mutedText,
                            ),
                          ],
                        ),
                        if (isThinkingExpanded) ...[
                          const SizedBox(height: 6),
                          const Divider(
                            color: DeckColors.borderSubtle,
                            height: 1,
                          ),
                          const SizedBox(height: 6),
                          SelectableText(
                            turn.thinking,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 11,
                              color: DeckColors.secondaryText,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],

              // Active tool pill or executed tools list
              if (turn.currentTool != null || turn.tools.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    if (turn.currentTool != null &&
                        turn.currentTool!.isNotEmpty) () {
                      final rawTool = turn.currentTool!;
                      final activeLine = rawTool
                          .split('\n')
                          .map((l) => l.trim())
                          .where((l) => l.isNotEmpty)
                          .lastOrNull ?? rawTool;
                      var cleanTool = activeLine
                          .replaceAll(RegExp(r'^[⚙️✓\s]+'), '')
                          .replaceAll(RegExp(r'\.{2,}'), '…')
                          .trim();
                      if (cleanTool.endsWith('…')) {
                        cleanTool = cleanTool.substring(0, cleanTool.length - 1).trimRight();
                      }

                      return Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.74,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color:
                              DeckColors.primaryAccent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: DeckColors.primaryAccent
                                .withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 10,
                              height: 10,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.5,
                                color: DeckColors.primaryAccent,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                cleanTool,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: DeckColors.primaryAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }(),
                    ...turn.tools
                        .where((t) => t != turn.currentTool)
                        .take(8)
                        .map(
                          (tool) {
                            var clean = tool
                                .replaceAll(RegExp(r'^[⚙️✓\s]+'), '')
                                .replaceAll(RegExp(r'\.{2,}'), '…')
                                .trim();
                            if (clean.endsWith('…')) {
                              clean = clean.substring(0, clean.length - 1).trimRight();
                            }
                            return Container(
                              constraints: BoxConstraints(
                                maxWidth:
                                    MediaQuery.of(context).size.width * 0.74,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: DeckColors.background,
                                borderRadius: BorderRadius.circular(5),
                                border:
                                    Border.all(color: DeckColors.borderSubtle),
                              ),
                              child: Text(
                                clean,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.jetBrainsMono(
                                  fontSize: 10,
                                  color: DeckColors.mutedText,
                                ),
                              ),
                            );
                          },
                        ),
                  ],
                ),
              ],

              const SizedBox(height: 10),
              if (turn.response.isNotEmpty)
                SelectableText(
                  turn.response,
                  style: const TextStyle(
                    fontSize: 13,
                    color: DeckColors.primaryText,
                    height: 1.45,
                  ),
                )
              else if (isStreamingCard)
                const Text(
                  'Waiting for Antigravity response stream...',
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: DeckColors.mutedText,
                  ),
                )
              else if (turn.tools.isNotEmpty)
                Text(
                  'Tool actions executed (${turn.tools.length} tool${turn.tools.length > 1 ? "s" : ""}).',
                  style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: DeckColors.mutedText,
                  ),
                ),

              if (turn.errorMessage != null &&
                  turn.errorMessage!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: DeckColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    turn.errorMessage!,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: DeckColors.error,
                    ),
                  ),
                ),
              ],

              if (turn.totalTokens > 0 || turn.durationSeconds > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (turn.durationSeconds > 0)
                      Text(
                        '${turn.durationSeconds.toStringAsFixed(1)}s',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: DeckColors.mutedText,
                        ),
                      ),
                    if (turn.durationSeconds > 0 && turn.totalTokens > 0)
                      const Text(
                        ' · ',
                        style: TextStyle(color: DeckColors.mutedText),
                      ),
                    if (turn.totalTokens > 0)
                      Text(
                        '${turn.totalTokens} tokens',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: DeckColors.mutedText,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPromptInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: const BoxDecoration(
        color: DeckColors.surfaceSecondary,
        border: Border(
          top: BorderSide(color: DeckColors.borderSubtle, width: 1),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _promptController,
              enabled: !_isStreaming,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _handleSendPrompt(),
              style: const TextStyle(
                fontSize: 13,
                color: DeckColors.primaryText,
              ),
              decoration: InputDecoration(
                hintText: _isStreaming
                    ? 'Agent turn in progress on ${_targetHost.name}...'
                    : 'Message Antigravity on ${_targetHost.name}...',
                hintStyle: const TextStyle(
                  fontSize: 12,
                  color: DeckColors.mutedText,
                ),
                filled: true,
                fillColor: DeckColors.surfaceElevated,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: DeckColors.borderSubtle),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: DeckColors.primaryAccent,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          if (_isStreaming)
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: DeckColors.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _handleAbortTurn,
                icon: const Icon(Icons.stop_circle_outlined, size: 18),
                label: const Text(
                  'Stop',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            )
          else
            SizedBox(
              height: 46,
              width: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: DeckColors.primaryAccent,
                  foregroundColor: Colors.black,
                  iconColor: Colors.black,
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: _handleSendPrompt,
                child: const Icon(
                  Icons.send_rounded,
                  size: 20,
                  color: Colors.black,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
