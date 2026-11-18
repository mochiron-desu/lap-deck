import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';
import '../../models/connector_models.dart';
import '../../services/connector_service.dart';
import '../../services/notification_service.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../services/app_logger.dart';
import '../widgets/log_viewer_sheet.dart';
import 'ai_chat_screen.dart';

enum ConnectorSubSection {
  overview,
  peers,
  aiConsole,
  activity,
  logsAndErrors,
  apiCapabilities,
}

class ConnectorTab extends StatefulWidget {
  final List<HostTarget> hosts;
  final HostTarget? activeHost;
  final StorageService storage;
  final ConnectorService connectorService;
  final SshService? sshService;
  final NotificationService? notificationService;
  final Function(HostTarget) onSelectHost;

  const ConnectorTab({
    super.key,
    required this.hosts,
    required this.activeHost,
    required this.storage,
    required this.connectorService,
    this.sshService,
    this.notificationService,
    required this.onSelectHost,
  });

  @override
  State<ConnectorTab> createState() => _ConnectorTabState();
}

class _ConnectorTabState extends State<ConnectorTab> {
  ConnectorSubSection _activeSection = ConnectorSubSection.overview;

  // Source of truth: live state for all peers
  List<ConnectorPeerNodeState> _peerStates = [];
  DateTime? _lastDashboardRefreshAt;

  // Per-peer independent action state (keyed by peer.host.id)
  final Map<String, String> _peerInFlightAction = {};
  final Map<String, ({bool isOk, String message, DateTime timestamp})>
      _peerActionFeedback = {};
  final Map<String, bool> _expandedPeerWorkspaceInfo = {};
  final Set<String> _localUserStoppedIds = {};

  // Secondary tabs runtime caches
  List<ConnectorApiItem> _discoveredApis = [];
  List<ConnectorErrorItem> _errorLogs = [];
  Map<String, dynamic> _errorStats = {};
  List<MediaActivityItem> _mediaActivities = [];
  Map<String, dynamic>? _mediaStatus;

  bool _isInitialLoading = true;
  bool _isRefreshing = false;
  String? _globalError;
  String _selectedErrorCategory = 'ALL';
  String _selectedApiCategory = 'ALL';
  String _selectedSubViewPeerId = 'ALL';

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _initPeerPlaceholders();
    _refreshCurrentView();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_isRefreshing && _peerInFlightAction.isEmpty) {
        if (_activeSection == ConnectorSubSection.overview ||
            _activeSection == ConnectorSubSection.peers) {
          _refreshPeersDashboard(silent: true);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant ConnectorTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hosts.length != widget.hosts.length) {
      _refreshPeersDashboard(silent: true);
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _initPeerPlaceholders() {
    _peerStates = widget.hosts
        .map(
          (h) => ConnectorPeerNodeState(
            host: h,
            connectionState: ConnectorPeerConnectionState.connecting,
          ),
        )
        .toList();
  }

  Future<String?> _getSecret(HostTarget host) async {
    return await widget.storage.getConnectorToken(host.id);
  }

  List<ConnectorPeerNodeState> get _onlinePeers =>
      _peerStates.where((p) => p.isOnline).toList();

  ConnectorPeerNodeState? get _primaryOnlinePeer {
    for (final p in _peerStates) {
      if (p.isMain) return p;
    }
    for (final p in _peerStates) {
      if (p.isOnline) return p;
    }
    return _peerStates.isNotEmpty ? _peerStates.first : null;
  }

  Future<void> _refreshCurrentView() async {
    if (_activeSection == ConnectorSubSection.overview ||
        _activeSection == ConnectorSubSection.peers) {
      await _refreshPeersDashboard();
      return;
    }

    if (mounted) {
      setState(() {
        _isRefreshing = true;
        _globalError = null;
      });
    }

    try {
      // Ensure peer list is fresh first if empty
      if (_peerStates.every((p) => p.isConnecting)) {
        await _refreshPeersDashboard(silent: true);
      }

      final targetPeers = _selectedSubViewPeerId == 'ALL'
          ? (_onlinePeers.isNotEmpty
              ? _onlinePeers
              : _peerStates.take(1).toList())
          : _peerStates
              .where((p) => p.host.id == _selectedSubViewPeerId)
              .toList();

      switch (_activeSection) {
        case ConnectorSubSection.overview:
        case ConnectorSubSection.peers:
        case ConnectorSubSection.aiConsole:
          break;

        case ConnectorSubSection.activity:
          final allActs = <MediaActivityItem>[];
          Map<String, dynamic>? latestStatus;
          for (final peer in targetPeers) {
            final secret = await _getSecret(peer.host);
            final acts = await widget.connectorService.fetchMediaActivity(
              peer.host,
              secret: secret,
              limit: 30,
            );
            final status = await widget.connectorService.fetchMediaStatus(
              peer.host,
              secret: secret,
            );
            allActs.addAll(acts);
            latestStatus ??= status;
          }
          allActs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          if (mounted) {
            setState(() {
              _mediaActivities = allActs;
              _mediaStatus = latestStatus;
            });
          }
          break;

        case ConnectorSubSection.logsAndErrors:
          final allErrors = <ConnectorErrorItem>[];
          int totalCount = 0;
          String? lastErrTime;
          for (final peer in targetPeers) {
            final secret = await _getSecret(peer.host);
            final res = await widget.connectorService.fetchErrors(
              peer.host,
              secret: secret,
              limit: 50,
              category: _selectedErrorCategory,
            );
            if (res['ok'] == true) {
              final errs =
                  (res['errors'] as List<ConnectorErrorItem>?) ?? [];
              allErrors.addAll(errs);
              totalCount += (res['totalCount'] as int?) ?? errs.length;
              lastErrTime ??= res['lastErrorTime']?.toString();
            }
          }
          allErrors.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          if (mounted) {
            setState(() {
              _errorLogs = allErrors;
              _errorStats = {
                'totalCount': totalCount,
                'lastErrorTime': lastErrTime,
              };
            });
          }
          break;

        case ConnectorSubSection.apiCapabilities:
          final primary = _primaryOnlinePeer;
          if (primary != null) {
            final secret = await _getSecret(primary.host);
            final apis = await widget.connectorService.fetchApis(
              primary.host,
              secret: secret,
            );
            if (mounted) {
              setState(() {
                _discoveredApis = apis;
              });
            }
          }
          break;
      }
    } catch (e, st) {
      AppLogger.error(
        'ConnectorTab',
        'Unhandled error refreshing subview: $e',
        e,
        st,
      );
      if (mounted) {
        setState(() => _globalError = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  /// Fetches live telemetry and role state across all peers simultaneously.
  Future<void> _refreshPeersDashboard({bool silent = false}) async {
    if (widget.hosts.isEmpty) {
      if (mounted) {
        setState(() {
          _peerStates = [];
          _isInitialLoading = false;
          _isRefreshing = false;
          _lastDashboardRefreshAt = DateTime.now();
        });
      }
      return;
    }

    if (mounted && !silent) {
      setState(() {
        _isRefreshing = true;
        _globalError = null;
      });
    }

    try {
      final fetched = await widget.connectorService.fetchAllPeersState(
        widget.hosts,
        getSecretForHost: _getSecret,
        localUserStoppedIds: _localUserStoppedIds,
      );

      // Clear local user-stopped override for any peer that is now verified online
      for (final p in fetched) {
        if (p.isOnline) {
          _localUserStoppedIds.remove(p.host.id);
        }
      }

      // Sort: Main node first, then online Standby nodes, then offline/stopped
      fetched.sort((a, b) {
        if (a.isMain && !b.isMain) return -1;
        if (!a.isMain && b.isMain) return 1;
        if (a.isOnline && !b.isOnline) return -1;
        if (!a.isOnline && b.isOnline) return 1;
        return a.displayHostname
            .toLowerCase()
            .compareTo(b.displayHostname.toLowerCase());
      });

      if (mounted) {
        setState(() {
          _peerStates = fetched;
          _lastDashboardRefreshAt = DateTime.now();
          _isInitialLoading = false;
        });
      }
    } catch (e, st) {
      AppLogger.error(
        'ConnectorTab',
        'Failed refreshing peers dashboard: $e',
        e,
        st,
      );
      if (mounted) {
        setState(() {
          _globalError = e.toString();
          _isInitialLoading = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  /// Refreshes a single peer card's health data without reloading the entire application.
  Future<void> _refreshSinglePeer(HostTarget host) async {
    final secret = await _getSecret(host);
    final health = await widget.connectorService.fetchHealth(
      host,
      secret: secret,
    );
    if (!mounted) return;

    setState(() {
      _lastDashboardRefreshAt = DateTime.now();
      _peerStates = _peerStates.map((p) {
        if (p.host.id != host.id) return p;
        if (health != null) {
          _localUserStoppedIds.remove(host.id);
          return p.copyWith(
            connectionState: ConnectorPeerConnectionState.online,
            health: health,
            clearError: true,
            lastChecked: health.fetchedAt,
          );
        } else {
          final isStopped = _localUserStoppedIds.contains(host.id);
          return p.copyWith(
            connectionState: isStopped
                ? ConnectorPeerConnectionState.userStopped
                : ConnectorPeerConnectionState.offline,
            clearHealth: true,
            errorMessage: widget.connectorService.lastErrorDetail ??
                'Peer offline or unreachable',
            lastChecked: DateTime.now(),
          );
        }
      }).toList();
    });
  }

  // ---------------------------------------------------------------------------
  // Contextual Peer Actions (Stop, Start, Restart, Promote to Main, Change Target, Git Sync)
  // ---------------------------------------------------------------------------

  void _setPeerFeedback(String hostId, bool isOk, String message) {
    if (!mounted) return;
    setState(() {
      _peerActionFeedback[hostId] = (
        isOk: isOk,
        message: message,
        timestamp: DateTime.now(),
      );
    });
  }

  Future<void> _executePeerStop(ConnectorPeerNodeState peerState) async {
    final host = peerState.host;
    if (_peerInFlightAction.containsKey(host.id)) return;

    HapticFeedback.heavyImpact();
    setState(() {
      _peerInFlightAction[host.id] = 'Stopping ${peerState.displayHostname}...';
      _peerActionFeedback.remove(host.id);
    });

    try {
      final secret = await _getSecret(host);
      final otherOnline = _onlinePeers
          .where((p) => p.host.id != host.id)
          .map((p) => p.host)
          .toList();

      final res = await widget.connectorService.executeLifecycle(
        host,
        node: peerState.nodeOsKey,
        action: 'stop',
        userStopped: true,
        reason: 'Stopped by operator from Lapdeck Connection Dashboard',
        secret: secret,
        otherOnlinePeers: otherOnline,
      );

      final isOk = res['ok'] == true;
      if (isOk) {
        _localUserStoppedIds.add(host.id);
        // Wait briefly for the remote daemon's 1.0s graceful shutdown thread
        await Future.delayed(const Duration(milliseconds: 1400));
        await _refreshPeersDashboard(silent: true);
        _setPeerFeedback(
          host.id,
          true,
          res['message']?.toString() ??
              '${peerState.displayHostname} stopped (auto-revival suppressed).',
        );
      } else {
        _setPeerFeedback(
          host.id,
          false,
          res['error']?.toString() ??
              res['message']?.toString() ??
              'Failed to stop ${peerState.displayHostname}.',
        );
      }
    } catch (e) {
      _setPeerFeedback(host.id, false, 'Stop error: $e');
    } finally {
      if (mounted) {
        setState(() => _peerInFlightAction.remove(host.id));
      }
    }
  }

  Future<void> _executePeerStart(ConnectorPeerNodeState peerState) async {
    final host = peerState.host;
    if (_peerInFlightAction.containsKey(host.id)) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _peerInFlightAction[host.id] = 'Starting ${peerState.displayHostname}...';
      _peerActionFeedback.remove(host.id);
    });

    try {
      final secret = await _getSecret(host);
      final otherOnline = _onlinePeers
          .where((p) => p.host.id != host.id)
          .map((p) => p.host)
          .toList();

      Map<String, dynamic> res = await widget.connectorService.executeLifecycle(
        host,
        node: peerState.nodeOsKey,
        action: 'start',
        userStopped: false,
        reason: 'Started by operator from Lapdeck Connection Dashboard',
        secret: secret,
        otherOnlinePeers: otherOnline,
      );

      // Fallback: if mesh HTTP start could not reach any online peer, start via direct SSH
      if (res['ok'] != true && widget.sshService != null) {
        final sshCred = await widget.storage.getHostCredential(host.id);
        final startCmd = host.os == HostOs.windows
            ? 'schtasks /Run /TN AntigravityTelegramConnector'
            : 'systemctl --user restart antigravity-telegram.service || nohup ~/Coding/misc/telegram-antigravity-connector/manage.sh start >/dev/null 2>&1 &';
        final sshRes = await widget.sshService!.executeCommand(
          host: host,
          command: startCmd,
          password: host.authMethod == AuthMethod.password ? sshCred : null,
          privateKeyPem:
              host.authMethod == AuthMethod.privateKey ? sshCred : null,
        );
        if (sshRes.isSuccess) {
          await Future.delayed(const Duration(seconds: 3));
          res = {
            'ok': true,
            'message':
                'Started ${peerState.displayHostname} via SSH service command.',
          };
        }
      }

      _localUserStoppedIds.remove(host.id);
      await _refreshPeersDashboard(silent: true);

      final nowOnline =
          _peerStates.any((p) => p.host.id == host.id && p.isOnline);
      if (res['ok'] == true || nowOnline) {
        _setPeerFeedback(
          host.id,
          true,
          res['message']?.toString() ??
              '${peerState.displayHostname} is online.',
        );
      } else {
        _setPeerFeedback(
          host.id,
          false,
          res['error']?.toString() ??
              'Start signal sent, but ${peerState.displayHostname} did not respond on port ${ConnectorService.defaultPort}.',
        );
      }
    } catch (e) {
      _setPeerFeedback(host.id, false, 'Start error: $e');
    } finally {
      if (mounted) {
        setState(() => _peerInFlightAction.remove(host.id));
      }
    }
  }

  Future<void> _executePeerRestart(ConnectorPeerNodeState peerState) async {
    final host = peerState.host;
    if (_peerInFlightAction.containsKey(host.id)) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _peerInFlightAction[host.id] =
          'Restarting ${peerState.displayHostname}...';
      _peerActionFeedback.remove(host.id);
    });

    try {
      final secret = await _getSecret(host);
      final otherOnline = _onlinePeers
          .where((p) => p.host.id != host.id)
          .map((p) => p.host)
          .toList();

      final res = await widget.connectorService.executeLifecycle(
        host,
        node: peerState.nodeOsKey,
        action: 'restart',
        userStopped: false,
        reason: 'Restarted by operator from Lapdeck Connection Dashboard',
        secret: secret,
        otherOnlinePeers: otherOnline,
      );

      if (res['ok'] == true) {
        // Wait for daemon restart cycle (1s delay + startup) then verify health
        await Future.delayed(const Duration(milliseconds: 2800));
        await _refreshPeersDashboard(silent: true);
        final verifiedOnline =
            _peerStates.any((p) => p.host.id == host.id && p.isOnline);
        _setPeerFeedback(
          host.id,
          verifiedOnline,
          verifiedOnline
              ? '${peerState.displayHostname} restarted and verified online.'
              : 'Restart initiated on ${peerState.displayHostname}; waiting for daemon to come back online.',
        );
      } else {
        _setPeerFeedback(
          host.id,
          false,
          res['error']?.toString() ??
              'Failed to restart ${peerState.displayHostname}.',
        );
      }
    } catch (e) {
      _setPeerFeedback(host.id, false, 'Restart error: $e');
    } finally {
      if (mounted) {
        setState(() => _peerInFlightAction.remove(host.id));
      }
    }
  }

  Future<void> _executePromoteToMain(ConnectorPeerNodeState peerState) async {
    final host = peerState.host;
    if (_peerInFlightAction.containsKey(host.id)) return;

    HapticFeedback.heavyImpact();
    setState(() {
      _peerInFlightAction[host.id] =
          'Promoting ${peerState.displayHostname} to Main...';
      _peerActionFeedback.remove(host.id);
    });

    try {
      final secret = await _getSecret(host);
      final allOnlineHosts = _onlinePeers.map((p) => p.host).toList();

      final res = await widget.connectorService.promoteMain(
        host,
        allPeers: allOnlineHosts,
        reason:
            'Promoted ${peerState.displayHostname} to Main from Lapdeck Connection Dashboard',
        secret: secret,
      );

      final isOk = res['ok'] == true;
      await _refreshPeersDashboard(silent: true);

      final verifiedMain =
          _peerStates.any((p) => p.host.id == host.id && p.isMain);
      if (isOk && verifiedMain) {
        _setPeerFeedback(
          host.id,
          true,
          '${peerState.displayHostname} is now the active Main node.',
        );
      } else {
        _setPeerFeedback(
          host.id,
          false,
          res['error']?.toString() ??
              res['message']?.toString() ??
              'Promotion request did not confirm Main role.',
        );
      }
    } catch (e) {
      _setPeerFeedback(host.id, false, 'Promotion error: $e');
    } finally {
      if (mounted) {
        setState(() => _peerInFlightAction.remove(host.id));
      }
    }
  }

  Future<void> _executePeerGitSync(ConnectorPeerNodeState peerState) async {
    final host = peerState.host;
    if (_peerInFlightAction.containsKey(host.id)) return;

    HapticFeedback.mediumImpact();
    setState(() {
      _peerInFlightAction[host.id] =
          'Syncing Git repository on ${peerState.displayHostname}...';
      _peerActionFeedback.remove(host.id);
    });

    try {
      final secret = await _getSecret(host);
      final res = await widget.connectorService.triggerGitSync(
        host,
        secret: secret,
      );

      final isOk = res['ok'] == true;
      await _refreshSinglePeer(host);
      _setPeerFeedback(
        host.id,
        isOk,
        res['message']?.toString() ??
            res['error']?.toString() ??
            (isOk ? 'Git sync completed.' : 'Git sync failed.'),
      );
    } catch (e) {
      _setPeerFeedback(host.id, false, 'Git sync error: $e');
    } finally {
      if (mounted) {
        setState(() => _peerInFlightAction.remove(host.id));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Confirmation Dialogs & Change Target Sheet
  // ---------------------------------------------------------------------------

  void _confirmStopPeer(ConnectorPeerNodeState peerState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: DeckColors.borderMedium),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.stop_circle_outlined,
              color: DeckColors.error,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Stop ${peerState.displayHostname}?',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: DeckColors.primaryText,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDialogPeerSummary(peerState),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DeckColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DeckColors.borderSubtle),
              ),
              child: Text(
                peerState.isMain
                    ? 'This peer is currently the MAIN node. Stopping it will mark it User-Stopped (suppressing watchdog auto-revival) and allow an online Standby peer to assume Telegram polling.'
                    : 'Stopping this peer marks it User-Stopped in state.json so other mesh peers will NOT auto-revive or pull it back online until you start it.',
                style: const TextStyle(
                  color: DeckColors.secondaryText,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: DeckColors.mutedText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DeckColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _executePeerStop(peerState);
            },
            child: const Text('Stop Peer'),
          ),
        ],
      ),
    );
  }

  void _confirmRestartPeer(ConnectorPeerNodeState peerState) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: DeckColors.borderMedium),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.restart_alt,
              color: DeckColors.warning,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Restart ${peerState.displayHostname}?',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: DeckColors.primaryText,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDialogPeerSummary(peerState),
            const SizedBox(height: 12),
            const Text(
              'The connector daemon will perform a clean shutdown and restart immediately. Active session state and workspace configuration are preserved.',
              style: TextStyle(
                color: DeckColors.secondaryText,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: DeckColors.mutedText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DeckColors.warning,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _executePeerRestart(peerState);
            },
            child: const Text('Restart Peer'),
          ),
        ],
      ),
    );
  }

  void _confirmPromoteToMain(ConnectorPeerNodeState peerState) {
    final currentMains =
        _peerStates.where((p) => p.isMain && p.host.id != peerState.host.id).toList();
    final currentMainLabel = currentMains.isNotEmpty
        ? currentMains.map((p) => p.displayHostname).join(', ')
        : 'Current Main node';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: DeckColors.borderMedium),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.workspace_premium,
              color: DeckColors.primaryAccent,
              size: 22,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Promote ${peerState.displayHostname} to Main?',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: DeckColors.primaryText,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDialogPeerSummary(peerState),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DeckColors.background,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DeckColors.borderSubtle),
              ),
              child: Text(
                '${peerState.displayHostname} will assume the active Telegram Main poller role, and $currentMainLabel will automatically transition to Standby mode.',
                style: const TextStyle(
                  color: DeckColors.secondaryText,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: DeckColors.mutedText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DeckColors.primaryAccent,
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _executePromoteToMain(peerState);
            },
            child: const Text('Promote to Main'),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogPeerSummary(ConnectorPeerNodeState peerState) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: DeckColors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DeckColors.borderSubtle),
      ),
      child: Row(
        children: [
          Icon(
            peerState.host.os == HostOs.linux
                ? Icons.terminal
                : Icons.window,
            color: DeckColors.primaryAccent,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  peerState.displayHostname,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: DeckColors.primaryText,
                  ),
                ),
                Text(
                  '${peerState.roleLabel} · ${peerState.tailscaleIp}:${ConnectorService.defaultPort}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: DeckColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openChangeTargetSheet(ConnectorPeerNodeState peerState) async {
    final updated = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: DeckColors.surfaceSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ChangePeerTargetSheet(
        peerState: peerState,
        allPeers: _peerStates,
        isGlobalLapdeckTarget: widget.activeHost?.id == peerState.host.id,
        connectorService: widget.connectorService,
        storage: widget.storage,
        onSetLapdeckGlobalTarget: () {
          widget.onSelectHost(peerState.host);
        },
      ),
    );

    if (updated != null && mounted) {
      final isOk = updated['ok'] == true;
      final msg = updated['message']?.toString() ??
          (isOk ? 'Target updated.' : 'Failed to update target.');
      _setPeerFeedback(peerState.host.id, isOk, msg);
      await _refreshPeersDashboard(silent: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Main Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final onlineCount = _peerStates.where((p) => p.isOnline).length;
    final totalCount = _peerStates.length;

    return Scaffold(
      backgroundColor: DeckColors.background,
      appBar: AppBar(
        backgroundColor: DeckColors.background,
        elevation: 0,
        title: Row(
          children: [
            const Icon(
              Icons.cell_tower,
              color: DeckColors.primaryAccent,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(
              'CONNECTOR',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: DeckColors.primaryText,
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: onlineCount > 0
                    ? DeckColors.healthy.withValues(alpha: 0.14)
                    : DeckColors.error.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: onlineCount > 0
                      ? DeckColors.healthy.withValues(alpha: 0.4)
                      : DeckColors.error.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '$onlineCount/$totalCount ONLINE',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: onlineCount > 0
                      ? DeckColors.healthy
                      : DeckColors.error,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.history_edu_outlined,
              size: 20,
              color: DeckColors.informational,
            ),
            tooltip: 'Diagnostic Logs',
            onPressed: () => LogViewerSheet.show(context),
          ),
          IconButton(
            icon: _isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DeckColors.primaryAccent,
                    ),
                  )
                : const Icon(Icons.refresh, size: 20),
            tooltip: 'Refresh Peers',
            onPressed: _isRefreshing ? null : _refreshCurrentView,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSectionSelectorBar(),
            const Divider(height: 1, color: DeckColors.borderSubtle),
            Expanded(
              child: RefreshIndicator(
                color: DeckColors.primaryAccent,
                backgroundColor: DeckColors.surfaceElevated,
                onRefresh: _refreshCurrentView,
                child: _buildActiveSectionBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionSelectorBar() {
    final isPeersView = _activeSection == ConnectorSubSection.overview ||
        _activeSection == ConnectorSubSection.peers;

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _buildNavPill(
            isSelected: isPeersView,
            label: 'Live Peers',
            icon: Icons.device_hub,
            onTap: () {
              if (!isPeersView) {
                setState(() => _activeSection = ConnectorSubSection.overview);
                _refreshPeersDashboard();
              }
            },
          ),
          const SizedBox(width: 8),
          _buildNavPill(
            isSelected: _activeSection == ConnectorSubSection.aiConsole,
            label: 'AI Console',
            icon: Icons.smart_toy_outlined,
            onTap: () {
              if (_activeSection != ConnectorSubSection.aiConsole) {
                setState(() => _activeSection = ConnectorSubSection.aiConsole);
              }
            },
          ),
          const SizedBox(width: 8),
          _buildNavPill(
            isSelected: _activeSection == ConnectorSubSection.activity,
            label: 'Activity',
            icon: Icons.history,
            onTap: () {
              if (_activeSection != ConnectorSubSection.activity) {
                setState(() => _activeSection = ConnectorSubSection.activity);
                _refreshCurrentView();
              }
            },
          ),
          const SizedBox(width: 8),
          _buildNavPill(
            isSelected: _activeSection == ConnectorSubSection.logsAndErrors,
            label: 'Logs & Errors',
            icon: Icons.bug_report_outlined,
            onTap: () {
              if (_activeSection != ConnectorSubSection.logsAndErrors) {
                setState(
                  () => _activeSection = ConnectorSubSection.logsAndErrors,
                );
                _refreshCurrentView();
              }
            },
          ),
          const SizedBox(width: 8),
          _buildNavPill(
            isSelected: _activeSection == ConnectorSubSection.apiCapabilities,
            label: 'API Capabilities',
            icon: Icons.api,
            onTap: () {
              if (_activeSection != ConnectorSubSection.apiCapabilities) {
                setState(
                  () => _activeSection = ConnectorSubSection.apiCapabilities,
                );
                _refreshCurrentView();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavPill({
    required bool isSelected,
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? DeckColors.surfaceHighlight
              : DeckColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isSelected ? DeckColors.primaryAccent : DeckColors.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected
                  ? DeckColors.primaryAccent
                  : DeckColors.secondaryText,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? DeckColors.primaryText
                    : DeckColors.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSectionBody() {
    final defaultAiHost = _primaryOnlinePeer?.host ??
        widget.activeHost ??
        (widget.hosts.isNotEmpty
            ? widget.hosts.first
            : HostTarget.defaultHosts.first);

    return switch (_activeSection) {
      ConnectorSubSection.overview ||
      ConnectorSubSection.peers =>
        _buildLivePeerDashboard(),
      ConnectorSubSection.aiConsole => AiChatScreen(
          initialHost: defaultAiHost,
          availableHosts: widget.hosts.isNotEmpty
              ? widget.hosts
              : HostTarget.defaultHosts,
          storage: widget.storage,
          connectorService: widget.connectorService,
          notificationService: widget.notificationService,
          isEmbedded: true,
        ),
      ConnectorSubSection.activity => _buildActivitySection(),
      ConnectorSubSection.logsAndErrors => _buildLogsAndErrorsSection(),
      ConnectorSubSection.apiCapabilities => _buildApiCapabilitiesSection(),
    };
  }

  // ---------------------------------------------------------------------------
  // A & B & C. Live Peer Management Dashboard
  // ---------------------------------------------------------------------------

  Widget _buildLivePeerDashboard() {
    if (_isInitialLoading && _peerStates.every((p) => p.isConnecting)) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: DeckColors.primaryAccent,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Probing live connector peers on port ${ConnectorService.defaultPort}...',
              style: const TextStyle(
                color: DeckColors.secondaryText,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // A. Connection Overview Summary
        _buildConnectionOverviewCard(),
        const SizedBox(height: 20),

        // Global error banner if unexpected exception occurred
        if (_globalError != null) ...[
          _buildGlobalErrorCard(_globalError!),
          const SizedBox(height: 16),
        ],

        // Section Header for Live Peer List
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'CONNECTED MESH PEERS',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: DeckColors.mutedText,
              ),
            ),
            Text(
              'Port ${ConnectorService.defaultPort}',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: DeckColors.mutedText,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // B. Dynamically Populated Live Peer Cards
        if (_peerStates.isEmpty)
          _buildEmptyPeersState()
        else
          ..._peerStates.map((peerState) => _buildLivePeerCard(peerState)),
      ],
    );
  }

  /// Section A: Connection Overview (calculated strictly from live backend data).
  Widget _buildConnectionOverviewCard() {
    final totalConfigured = _peerStates.length;
    final activePeers = _peerStates.where((p) => p.isOnline).toList();
    final mainPeers = _peerStates.where((p) => p.isMain).toList();
    final standbyPeers = _peerStates.where((p) => p.isStandby).toList();
    final connectingCount = _peerStates.where((p) => p.isConnecting).length;

    final Color statusColor;
    final String statusTitle;
    final IconData statusIcon;

    if (connectingCount > 0 && activePeers.isEmpty) {
      statusColor = DeckColors.informational;
      statusTitle = 'Probing Connector Mesh...';
      statusIcon = Icons.sync;
    } else if (totalConfigured == 0) {
      statusColor = DeckColors.mutedText;
      statusTitle = 'No Peers Configured';
      statusIcon = Icons.help_outline;
    } else if (activePeers.length == totalConfigured && mainPeers.isNotEmpty) {
      statusColor = DeckColors.healthy;
      statusTitle = 'Mesh Healthy · All Peers Online';
      statusIcon = Icons.check_circle;
    } else if (activePeers.isNotEmpty) {
      statusColor = DeckColors.warning;
      statusTitle = mainPeers.isNotEmpty
          ? 'Mesh Degraded · ${activePeers.length} of $totalConfigured Peers Online'
          : 'Mesh Degraded · No Active Main Poller';
      statusIcon = Icons.warning_amber_rounded;
    } else {
      statusColor = DeckColors.error;
      statusTitle = 'Connector Mesh Offline';
      statusIcon = Icons.cloud_off_outlined;
    }

    final mainNames = mainPeers.isNotEmpty
        ? mainPeers.map((p) => p.displayHostname).join(', ')
        : 'None active';
    final standbyNames = standbyPeers.isNotEmpty
        ? standbyPeers.map((p) => p.displayHostname).join(', ')
        : 'None active';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DeckColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top overall status row
          Row(
            children: [
              Icon(statusIcon, size: 16, color: statusColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
              Text(
                _formatCheckTime(_lastDashboardRefreshAt),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: DeckColors.mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: DeckColors.borderSubtle),
          const SizedBox(height: 14),

          // 3-Column Live Metrics Strip
          IntrinsicHeight(
            child: Row(
              children: [
                Expanded(
                  child: _buildOverviewMetricBox(
                    label: 'ACTIVE PEERS',
                    value: '${activePeers.length}',
                    subValue: 'of $totalConfigured total',
                    valueColor: activePeers.isNotEmpty
                        ? DeckColors.healthy
                        : DeckColors.error,
                  ),
                ),
                Container(width: 1, color: DeckColors.borderSubtle),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: _buildOverviewMetricBox(
                      label: 'MAIN NODE',
                      value: '${mainPeers.length}',
                      subValue: mainNames,
                      valueColor: mainPeers.isNotEmpty
                          ? DeckColors.primaryAccent
                          : DeckColors.mutedText,
                    ),
                  ),
                ),
                Container(width: 1, color: DeckColors.borderSubtle),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: _buildOverviewMetricBox(
                      label: 'STANDBY',
                      value: '${standbyPeers.length}',
                      subValue: standbyNames,
                      valueColor: standbyPeers.isNotEmpty
                          ? DeckColors.informational
                          : DeckColors.mutedText,
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

  Widget _buildOverviewMetricBox({
    required String label,
    required String value,
    required String subValue,
    required Color valueColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: DeckColors.mutedText,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subValue,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            color: DeckColors.secondaryText,
          ),
        ),
      ],
    );
  }

  /// Section B & C: Individual Live Peer Card with Contextual Actions and Collapsible Workspace Panel.
  Widget _buildLivePeerCard(ConnectorPeerNodeState peerState) {
    final host = peerState.host;
    final health = peerState.health;
    final isMain = peerState.isMain;
    final isStandby = peerState.isStandby;
    final isOnline = peerState.isOnline;
    final inFlightMsg = _peerInFlightAction[host.id];
    final isBusy = inFlightMsg != null;
    final feedback = _peerActionFeedback[host.id];
    final isExpanded = _expandedPeerWorkspaceInfo[host.id] ?? false;

    // Restrained visual distinction for Main vs Standby vs Offline
    final Color borderColor = isMain
        ? DeckColors.primaryAccent.withValues(alpha: 0.65)
        : (!isOnline
            ? (peerState.isUserStopped
                ? DeckColors.warning.withValues(alpha: 0.4)
                : DeckColors.error.withValues(alpha: 0.35))
            : DeckColors.borderSubtle);

    final double borderWidth = isMain ? 1.5 : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Card Padding
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header Row: OS icon, Hostname, Role Badge, Connection Status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isMain
                            ? DeckColors.primaryAccent.withValues(alpha: 0.14)
                            : DeckColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isMain
                              ? DeckColors.primaryAccent.withValues(alpha: 0.4)
                              : DeckColors.borderSubtle,
                        ),
                      ),
                      child: Icon(
                        host.os == HostOs.linux
                            ? Icons.terminal
                            : (host.os == HostOs.windows
                                ? Icons.window
                                : Icons.laptop_mac),
                        size: 18,
                        color: isMain
                            ? DeckColors.primaryAccent
                            : DeckColors.secondaryText,
                      ),
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
                                peerState.displayHostname,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: DeckColors.primaryText,
                                ),
                              ),
                              _buildRoleBadge(peerState),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isOnline
                                ? '${peerState.osDisplay} · v${health!.version} · Uptime: ${health.uptimeHuman}'
                                : '${peerState.osDisplay} · ${host.roleDisplayName}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: DeckColors.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildConnectionStatusBadge(peerState),
                  ],
                ),
                const SizedBox(height: 12),

                // 2. Network Endpoints & Active Target Strip
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildEndpointChip(
                      icon: Icons.hub_outlined,
                      label:
                          'TS: ${peerState.tailscaleIp}:${ConnectorService.defaultPort}',
                    ),
                    if (peerState.lanIp.isNotEmpty &&
                        peerState.lanIp != 'N/A')
                      _buildEndpointChip(
                        icon: Icons.lan_outlined,
                        label: 'LAN: ${peerState.lanIp}',
                      ),
                    if (isOnline &&
                        health?.workspace != null &&
                        health!.workspace!.isNotEmpty)
                      _buildEndpointChip(
                        icon: Icons.folder_outlined,
                        label:
                            'Target: ${_formatWorkspaceShort(health.workspace!)}',
                        accentColor: DeckColors.informational,
                      ),
                    if (isOnline &&
                        health?.activeNode?.toLowerCase() ==
                            peerState.nodeOsKey)
                      _buildEndpointChip(
                        icon: Icons.track_changes,
                        label: 'AI Target: ${peerState.nodeOsKey.toUpperCase()}',
                        accentColor: DeckColors.primaryAccent,
                      ),
                  ],
                ),

                // 3. Resource Utilization Strip (when online)
                if (isOnline && health != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DeckColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DeckColors.borderSubtle),
                    ),
                    child: Column(
                      children: [
                        _buildUtilizationBar(
                          label: 'CPU',
                          valueText:
                              '${health.cpuPercent.toStringAsFixed(1)}%',
                          ratio: health.cpuPercent / 100.0,
                        ),
                        const SizedBox(height: 8),
                        _buildUtilizationBar(
                          label: 'RAM',
                          valueText: health.ramSummary,
                          ratio: health.ramPercent / 100.0,
                        ),
                        if (health.diskPercent != null) ...[
                          const SizedBox(height: 8),
                          _buildUtilizationBar(
                            label: 'DISK',
                            valueText: health.diskSummary,
                            ratio: health.diskPercent! / 100.0,
                          ),
                        ],
                      ],
                    ),
                  ),
                ] else if (!isOnline) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: DeckColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: peerState.isUserStopped
                            ? DeckColors.warning.withValues(alpha: 0.35)
                            : DeckColors.error.withValues(alpha: 0.35),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          peerState.isUserStopped
                              ? Icons.pause_circle_outline
                              : Icons.error_outline,
                          size: 16,
                          color: peerState.isUserStopped
                              ? DeckColors.warning
                              : DeckColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            peerState.isUserStopped
                                ? 'Stopped by user. Auto-revival is locked out until explicitly started.'
                                : (peerState.errorMessage ??
                                    'Connector daemon unreachable on port ${ConnectorService.defaultPort}.'),
                            style: TextStyle(
                              fontSize: 12,
                              color: peerState.isUserStopped
                                  ? DeckColors.warning
                                  : DeckColors.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // 4. Per-Peer In-Flight Progress or Result Feedback Banner
                if (isBusy) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: DeckColors.primaryAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: DeckColors.primaryAccent.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: DeckColors.primaryAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            inFlightMsg,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: DeckColors.primaryAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (feedback != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: (feedback.isOk
                              ? DeckColors.healthy
                              : DeckColors.error)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: (feedback.isOk
                                ? DeckColors.healthy
                                : DeckColors.error)
                            .withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          feedback.isOk
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          size: 16,
                          color: feedback.isOk
                              ? DeckColors.healthy
                              : DeckColors.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            feedback.message,
                            style: const TextStyle(
                              fontSize: 12,
                              color: DeckColors.primaryText,
                            ),
                          ),
                        ),
                        IconButton(
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          icon: const Icon(
                            Icons.close,
                            size: 14,
                            color: DeckColors.mutedText,
                          ),
                          tooltip: 'Dismiss',
                          onPressed: () {
                            setState(() => _peerActionFeedback.remove(host.id));
                          },
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),

                // 5. Contextual Peer Quick Actions
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Promote to Main: ONLY displayed for online Standby peers
                    if (isStandby)
                      _buildPeerActionButton(
                        label: 'Promote to Main',
                        icon: Icons.workspace_premium_outlined,
                        foreground: DeckColors.primaryAccent,
                        borderColor: DeckColors.primaryAccent,
                        backgroundColor:
                            DeckColors.primaryAccent.withValues(alpha: 0.12),
                        onPressed: isBusy
                            ? null
                            : () => _confirmPromoteToMain(peerState),
                      ),

                    // Open AI Console on this peer
                    if (isOnline)
                      _buildPeerActionButton(
                        label: 'AI Console',
                        icon: Icons.smart_toy_outlined,
                        foreground: DeckColors.primaryAccent,
                        borderColor: DeckColors.primaryAccent,
                        backgroundColor:
                            DeckColors.primaryAccent.withValues(alpha: 0.12),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => AiChatScreen(
                                initialHost: peerState.host,
                                availableHosts: widget.hosts.isNotEmpty
                                    ? widget.hosts
                                    : [peerState.host],
                                storage: widget.storage,
                                connectorService: widget.connectorService,
                                notificationService: widget.notificationService,
                              ),
                            ),
                          );
                        },
                      ),

                    // Change Target
                    _buildPeerActionButton(
                      label: 'Change Target',
                      icon: Icons.track_changes_outlined,
                      foreground: DeckColors.primaryText,
                      borderColor: DeckColors.borderMedium,
                      onPressed: isBusy
                          ? null
                          : () => _openChangeTargetSheet(peerState),
                    ),

                    // Restart
                    if (isOnline)
                      _buildPeerActionButton(
                        label: 'Restart',
                        icon: Icons.restart_alt,
                        foreground: DeckColors.secondaryText,
                        borderColor: DeckColors.borderSubtle,
                        onPressed: isBusy
                            ? null
                            : () => _confirmRestartPeer(peerState),
                      ),

                    // Stop (when online) or Start (when stopped/offline)
                    if (isOnline)
                      _buildPeerActionButton(
                        label: 'Stop',
                        icon: Icons.stop_circle_outlined,
                        foreground: DeckColors.error,
                        borderColor: DeckColors.error.withValues(alpha: 0.5),
                        onPressed:
                            isBusy ? null : () => _confirmStopPeer(peerState),
                      )
                    else
                      _buildPeerActionButton(
                        label: 'Start Peer',
                        icon: Icons.play_arrow_outlined,
                        foreground: DeckColors.healthy,
                        borderColor: DeckColors.healthy,
                        backgroundColor:
                            DeckColors.healthy.withValues(alpha: 0.12),
                        onPressed: isBusy
                            ? null
                            : () => _executePeerStart(peerState),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // 6. Collapsible Secondary Section: AI Agent, Workspace & Git Sync
          if (isOnline && health != null) ...[
            const Divider(height: 1, color: DeckColors.borderSubtle),
            InkWell(
              onTap: () {
                setState(() {
                  _expandedPeerWorkspaceInfo[host.id] = !isExpanded;
                });
              },
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.smart_toy_outlined,
                      size: 15,
                      color: DeckColors.mutedText,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'AI Agent, Workspace & Git',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeckColors.secondaryText,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${health.gitBranch ?? 'master'} @ ${health.gitCommit ?? 'HEAD'}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: DeckColors.mutedText,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: DeckColors.mutedText,
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                decoration: const BoxDecoration(
                  color: DeckColors.background,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(12),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Divider(height: 12, color: DeckColors.borderSubtle),
                    _buildMetadataRow(
                      'Workspace',
                      health.workspace ?? 'Default',
                      isMono: true,
                    ),
                    _buildMetadataRow(
                      'Active Model',
                      health.model ?? 'Not initialized',
                      isMono: true,
                    ),
                    _buildMetadataRow(
                      'Session ID',
                      health.conversationId ?? 'None',
                      isMono: true,
                    ),
                    _buildMetadataRow(
                      'Git Branch',
                      '${health.gitBranch ?? 'master'} (${health.gitCommit ?? 'HEAD'}) · ${health.gitClean ? 'Clean' : 'Modified'}',
                      isMono: true,
                    ),
                    _buildMetadataRow(
                      'Tailscale IP',
                      peerState.tailscaleIp,
                      isMono: true,
                    ),
                    _buildMetadataRow(
                      'LAN IP',
                      peerState.lanIp,
                      isMono: true,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: DeckColors.primaryText,
                            side: const BorderSide(
                              color: DeckColors.borderMedium,
                            ),
                            minimumSize: const Size(120, 38),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                          ),
                          onPressed: isBusy
                              ? null
                              : () => _executePeerGitSync(peerState),
                          icon: const Icon(Icons.sync, size: 15),
                          label: const Text(
                            'Pull Git Sync',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRoleBadge(ConnectorPeerNodeState peerState) {
    if (!peerState.isOnline) {
      return const SizedBox.shrink();
    }
    final isMain = peerState.isMain;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: isMain
            ? DeckColors.primaryAccent.withValues(alpha: 0.16)
            : DeckColors.surfaceElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isMain
              ? DeckColors.primaryAccent.withValues(alpha: 0.6)
              : DeckColors.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isMain ? Icons.workspace_premium : Icons.shield_moon_outlined,
            size: 11,
            color:
                isMain ? DeckColors.primaryAccent : DeckColors.secondaryText,
          ),
          const SizedBox(width: 4),
          Text(
            isMain ? 'MAIN' : 'STANDBY',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color:
                  isMain ? DeckColors.primaryAccent : DeckColors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatusBadge(ConnectorPeerNodeState peerState) {
    final (Color color, String label) = switch (peerState.connectionState) {
      ConnectorPeerConnectionState.online => (DeckColors.healthy, 'ONLINE'),
      ConnectorPeerConnectionState.connecting => (
          DeckColors.informational,
          'CONNECTING',
        ),
      ConnectorPeerConnectionState.userStopped => (
          DeckColors.warning,
          'STOPPED',
        ),
      ConnectorPeerConnectionState.offline => (DeckColors.error, 'OFFLINE'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (peerState.isConnecting)
            SizedBox(
              width: 8,
              height: 8,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: color,
              ),
            )
          else
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEndpointChip({
    required IconData icon,
    required String label,
    Color? accentColor,
  }) {
    final c = accentColor ?? DeckColors.secondaryText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: DeckColors.surfaceElevated,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: accentColor != null
              ? accentColor.withValues(alpha: 0.35)
              : DeckColors.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: accentColor != null ? c : DeckColors.primaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUtilizationBar({
    required String label,
    required String valueText,
    required double ratio,
  }) {
    final clamped = ratio.clamp(0.0, 1.0);
    final barColor = clamped > 0.85
        ? DeckColors.error
        : (clamped > 0.70 ? DeckColors.warning : DeckColors.healthy);

    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: DeckColors.mutedText,
            ),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: clamped,
              minHeight: 5,
              backgroundColor: DeckColors.surfaceSecondary,
              color: barColor,
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 125,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: DeckColors.primaryText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPeerActionButton({
    required String label,
    required IconData icon,
    required Color foreground,
    required Color borderColor,
    Color? backgroundColor,
    required VoidCallback? onPressed,
  }) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: backgroundColor ?? DeckColors.surfaceElevated,
        side: BorderSide(color: borderColor),
        minimumSize: const Size(110, 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
      icon: Icon(icon, size: 15),
      label: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildMetadataRow(String label, String value, {bool isMono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: DeckColors.mutedText,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: isMono
                  ? GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      color: DeckColors.primaryText,
                    )
                  : const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: DeckColors.primaryText,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPeersState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DeckColors.borderSubtle),
      ),
      child: const Column(
        children: [
          Icon(Icons.devices_other, size: 32, color: DeckColors.mutedText),
          SizedBox(height: 10),
          Text(
            'No Connector Peers Available',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: DeckColors.primaryText,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Enroll a peer workstation in the Devices tab to monitor and manage its Telegram Antigravity Connector node.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: DeckColors.secondaryText),
          ),
        ],
      ),
    );
  }

  Widget _buildGlobalErrorCard(String errorMsg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DeckColors.error.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.error_outline, color: DeckColors.error, size: 18),
              SizedBox(width: 8),
              Text(
                'Communication Error',
                style: TextStyle(
                  color: DeckColors.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            errorMsg,
            style: GoogleFonts.jetBrainsMono(
              color: DeckColors.secondaryText,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: DeckColors.surfaceElevated,
                  foregroundColor: DeckColors.primaryAccent,
                ),
                onPressed: _refreshCurrentView,
                icon: const Icon(Icons.refresh, size: 15),
                label: const Text('Retry'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: DeckColors.informational,
                  side: const BorderSide(color: DeckColors.informational),
                ),
                onPressed: () => LogViewerSheet.show(context),
                icon: const Icon(Icons.history_edu_outlined, size: 15),
                label: const Text('View Logs'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Activity Section (Across Peers)
  // ---------------------------------------------------------------------------

  Widget _buildPeerFilterRow() {
    if (_peerStates.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildPeerFilterChip('ALL', 'All Peers'),
            ..._peerStates.map(
              (p) => _buildPeerFilterChip(p.host.id, p.displayHostname),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeerFilterChip(String id, String label) {
    final isSelected = _selectedSubViewPeerId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (val) {
          if (val && _selectedSubViewPeerId != id) {
            setState(() => _selectedSubViewPeerId = id);
            _refreshCurrentView();
          }
        },
        selectedColor: DeckColors.primaryAccent,
        backgroundColor: DeckColors.surfaceElevated,
        labelStyle: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.black : DeckColors.secondaryText,
        ),
      ),
    );
  }

  Widget _buildActivitySection() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildPeerFilterRow(),
        if (_mediaStatus != null)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: DeckColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: DeckColors.borderSubtle),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem(
                  'Cooldown',
                  '${_mediaStatus?['default_cooldown_seconds'] ?? 120}s',
                ),
                _buildStatItem(
                  'Trusted Users',
                  '${_mediaStatus?['trusted_users_count'] ?? 0}',
                ),
                _buildStatItem(
                  'Active Jobs',
                  '${_mediaStatus?['active_jobs_count'] ?? 0}',
                ),
              ],
            ),
          ),
        Text(
          'RECENT MEDIA COMMANDS (/yt, /demucs, /ig)',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: DeckColors.secondaryText,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        if (_mediaActivities.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DeckColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: DeckColors.borderSubtle),
            ),
            child: const Text(
              'No recent media command invocations logged.',
              style: TextStyle(color: DeckColors.mutedText, fontSize: 13),
            ),
          )
        else
          ..._mediaActivities.map((act) => _buildActivityCard(act)),
      ],
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: DeckColors.primaryAccent,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: DeckColors.secondaryText),
        ),
      ],
    );
  }

  Widget _buildActivityCard(MediaActivityItem act) {
    final statusColor = switch (act.status.toLowerCase()) {
      'completed' => DeckColors.healthy,
      'started' => DeckColors.informational,
      'failed' => DeckColors.error,
      'blocked' => DeckColors.warning,
      _ => DeckColors.secondaryText,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DeckColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    act.command,
                    style: GoogleFonts.jetBrainsMono(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: DeckColors.primaryAccent,
                    ),
                  ),
                  if (act.peerName != null && act.peerName!.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: DeckColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        act.peerName!,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: DeckColors.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  act.status.toUpperCase(),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            act.target,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: DeckColors.primaryText),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'User: ${act.userName} (${act.userId})',
                style: const TextStyle(
                  fontSize: 11,
                  color: DeckColors.secondaryText,
                ),
              ),
              Text(
                act.timestamp,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: DeckColors.mutedText,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Logs & Errors Section
  // ---------------------------------------------------------------------------

  Widget _buildLogsAndErrorsSection() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildPeerFilterRow(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Errors: ${_errorStats['totalCount'] ?? _errorLogs.length}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: DeckColors.primaryText,
                  ),
                ),
                Text(
                  'Last logged: ${_errorStats['lastErrorTime'] ?? 'None'}',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: DeckColors.mutedText,
                  ),
                ),
              ],
            ),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: DeckColors.error,
                side: const BorderSide(color: DeckColors.error),
              ),
              onPressed: () async {
                final targets = _selectedSubViewPeerId == 'ALL'
                    ? _onlinePeers
                    : _peerStates
                        .where((p) => p.host.id == _selectedSubViewPeerId)
                        .toList();
                bool anyCleared = false;
                for (final peer in targets) {
                  final sec = await _getSecret(peer.host);
                  final ok = await widget.connectorService.clearErrors(
                    peer.host,
                    secret: sec,
                  );
                  if (ok) anyCleared = true;
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        anyCleared
                            ? 'Error log cleared'
                            : 'Failed to clear error log',
                      ),
                    ),
                  );
                  _refreshCurrentView();
                }
              },
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Clear Log'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['ALL', 'AI', 'TELEGRAM', 'MEDIA', 'PEER', 'SYSTEM']
                .map((cat) {
              final isSel = _selectedErrorCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSel,
                  onSelected: (val) {
                    if (val) {
                      setState(() => _selectedErrorCategory = cat);
                      _refreshCurrentView();
                    }
                  },
                  selectedColor: DeckColors.primaryAccent,
                  backgroundColor: DeckColors.surfaceElevated,
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSel ? Colors.black : DeckColors.secondaryText,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        if (_errorLogs.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DeckColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: DeckColors.borderSubtle),
            ),
            child: const Text(
              'No errors logged under this category.',
              style: TextStyle(color: DeckColors.mutedText),
            ),
          )
        else
          ..._errorLogs.map((err) => _buildErrorCard(err)),
      ],
    );
  }

  Widget _buildErrorCard(ConnectorErrorItem err) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DeckColors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: DeckColors.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      err.category,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: DeckColors.error,
                      ),
                    ),
                  ),
                  if (err.peerName != null && err.peerName!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: DeckColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        err.peerName!,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          color: DeckColors.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                err.timestamp,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: DeckColors.mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            err.message,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: DeckColors.primaryText,
            ),
          ),
          if (err.prompt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Prompt: ${err.prompt}',
              style: const TextStyle(
                fontSize: 12,
                color: DeckColors.secondaryText,
              ),
            ),
          ],
          if (err.exception != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: DeckColors.background,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                err.exception!,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  color: DeckColors.warning,
                ),
              ),
            ),
          ],
          if (err.traceback != null) ...[
            const SizedBox(height: 6),
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'View Traceback',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: DeckColors.primaryAccent,
                  ),
                ),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DeckColors.background,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: SelectableText(
                      err.traceback!,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        color: DeckColors.terminalText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. API Capabilities Section
  // ---------------------------------------------------------------------------

  Widget _buildApiCapabilitiesSection() {
    final filtered = _selectedApiCategory == 'ALL'
        ? _discoveredApis
        : _discoveredApis
            .where(
              (a) =>
                  a.category.toUpperCase() ==
                  _selectedApiCategory.toUpperCase(),
            )
            .toList();

    final categories = {
      'ALL',
      ..._discoveredApis.map((a) => a.category.toUpperCase()),
    }.toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'DISCOVERED APIS (${_discoveredApis.length} ENDPOINTS)',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: DeckColors.secondaryText,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: categories.map((cat) {
              final isSel = _selectedApiCategory == cat;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(cat),
                  selected: isSel,
                  onSelected: (val) {
                    if (val) setState(() => _selectedApiCategory = cat);
                  },
                  selectedColor: DeckColors.primaryAccent,
                  backgroundColor: DeckColors.surfaceElevated,
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSel ? Colors.black : DeckColors.secondaryText,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: DeckColors.surfaceSecondary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: DeckColors.borderSubtle),
            ),
            child: const Text(
              'No endpoints available.',
              style: TextStyle(color: DeckColors.mutedText),
            ),
          )
        else
          ...filtered.map((api) => _buildApiTile(api)),
      ],
    );
  }

  Widget _buildApiTile(ConnectorApiItem api) {
    final isPost = api.method == 'POST';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: DeckColors.borderSubtle),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isPost
                ? DeckColors.primaryAccent.withValues(alpha: 0.15)
                : DeckColors.informational.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            api.method,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color:
                  isPost ? DeckColors.primaryAccent : DeckColors.informational,
            ),
          ),
        ),
        title: Text(
          api.path,
          style: GoogleFonts.jetBrainsMono(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: DeckColors.primaryText,
          ),
        ),
        subtitle: Text(
          api.summary,
          style: const TextStyle(fontSize: 12, color: DeckColors.secondaryText),
        ),
        trailing: const Icon(
          Icons.chevron_right,
          color: DeckColors.secondaryText,
          size: 20,
        ),
        onTap: () => _openApiRunnerSheet(api),
      ),
    );
  }

  void _openApiRunnerSheet(ConnectorApiItem api) {
    final primary = _primaryOnlinePeer;
    if (primary == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: DeckColors.surfaceSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _ApiRunnerSheet(
        api: api,
        initialHost: primary.host,
        availablePeers: _peerStates,
        connectorService: widget.connectorService,
        storage: widget.storage,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Formatting Helpers
  // ---------------------------------------------------------------------------

  String _formatCheckTime(DateTime? dt) {
    if (dt == null) return 'Not checked yet';
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 15) return 'Checked just now';
    if (diff.inSeconds < 60) return 'Checked ${diff.inSeconds}s ago';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return 'Checked $hh:$mm:$ss';
  }

  String _formatWorkspaceShort(String fullPath) {
    final norm = fullPath.replaceAll('\\', '/');
    final trimmed = norm.endsWith('/') && norm.length > 1
        ? norm.substring(0, norm.length - 1)
        : norm;
    final idx = trimmed.lastIndexOf('/');
    if (idx >= 0 && idx < trimmed.length - 1) {
      return trimmed.substring(idx + 1);
    }
    return fullPath;
  }
}

// ---------------------------------------------------------------------------
// Change Target Bottom Sheet (Temporary Peer-Specific Interaction State)
// ---------------------------------------------------------------------------

class _ChangePeerTargetSheet extends StatefulWidget {
  final ConnectorPeerNodeState peerState;
  final List<ConnectorPeerNodeState> allPeers;
  final bool isGlobalLapdeckTarget;
  final ConnectorService connectorService;
  final StorageService storage;
  final VoidCallback onSetLapdeckGlobalTarget;

  const _ChangePeerTargetSheet({
    required this.peerState,
    required this.allPeers,
    required this.isGlobalLapdeckTarget,
    required this.connectorService,
    required this.storage,
    required this.onSetLapdeckGlobalTarget,
  });

  @override
  State<_ChangePeerTargetSheet> createState() => _ChangePeerTargetSheetState();
}

class _ChangePeerTargetSheetState extends State<_ChangePeerTargetSheet> {
  bool _isLoadingConfig = true;
  bool _isSaving = false;
  bool _isBrowsingDirs = false;

  ConnectorTargetConfig? _targetConfig;
  String? _error;

  late TextEditingController _workspaceController;
  String _selectedActiveNode = '';
  String _currentBrowsePath = '';
  String? _parentBrowsePath;
  List<String> _browsedDirectories = [];
  bool _setAsGlobalDeckTarget = false;

  @override
  void initState() {
    super.initState();
    final initialWs = widget.peerState.health?.workspace ?? '';
    _workspaceController = TextEditingController(text: initialWs);
    _selectedActiveNode =
        widget.peerState.health?.activeNode ?? widget.peerState.nodeOsKey;
    _setAsGlobalDeckTarget = widget.isGlobalLapdeckTarget;
    _loadLiveTargetConfig();
  }

  @override
  void dispose() {
    _workspaceController.dispose();
    super.dispose();
  }

  Future<void> _loadLiveTargetConfig() async {
    setState(() {
      _isLoadingConfig = true;
      _error = null;
    });

    try {
      final secret = await widget.storage.getConnectorToken(
        widget.peerState.host.id,
      );
      final cfg = await widget.connectorService.fetchPeerTargetConfig(
        widget.peerState.host,
        secret: secret,
        cachedHealth: widget.peerState.health,
      );

      if (!mounted) return;
      if (cfg != null) {
        setState(() {
          _targetConfig = cfg;
          if (cfg.workspace.isNotEmpty) {
            _workspaceController.text = cfg.workspace;
            _currentBrowsePath = cfg.workspace;
          }
          _selectedActiveNode = cfg.activeNode;
          _isLoadingConfig = false;
        });
      } else {
        setState(() {
          _error = widget.connectorService.lastErrorDetail ??
              'Could not load target configuration from ${widget.peerState.displayHostname}.';
          _isLoadingConfig = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoadingConfig = false;
        });
      }
    }
  }

  Future<void> _browseDirectory(String? dirPath) async {
    setState(() {
      _isBrowsingDirs = true;
      _error = null;
    });

    try {
      final secret = await widget.storage.getConnectorToken(
        widget.peerState.host.id,
      );
      final res = await widget.connectorService.listDirectories(
        widget.peerState.host,
        path: dirPath,
        secret: secret,
      );

      if (!mounted) return;
      if (res['ok'] == true) {
        setState(() {
          _currentBrowsePath = res['path']?.toString() ?? dirPath ?? '';
          _parentBrowsePath = res['parent']?.toString();
          _browsedDirectories =
              (res['directories'] as List<String>?) ?? <String>[];
          if (_currentBrowsePath.isNotEmpty) {
            _workspaceController.text = _currentBrowsePath;
          }
        });
      } else {
        setState(() {
          _error = res['error']?.toString() ?? 'Failed to list directory';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isBrowsingDirs = false);
      }
    }
  }

  Future<void> _saveTargetChanges() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });

    try {
      if (_setAsGlobalDeckTarget && !widget.isGlobalLapdeckTarget) {
        widget.onSetLapdeckGlobalTarget();
      }

      if (!widget.peerState.isOnline) {
        if (mounted) {
          Navigator.of(context).pop({
            'ok': true,
            'message':
                'Selected ${widget.peerState.displayHostname} as active Lapdeck target.',
          });
        }
        return;
      }

      final secret = await widget.storage.getConnectorToken(
        widget.peerState.host.id,
      );
      final newWs = _workspaceController.text.trim();
      final res = await widget.connectorService.updatePeerTarget(
        widget.peerState.host,
        workspace: newWs.isNotEmpty ? newWs : null,
        activeNode: _selectedActiveNode,
        secret: secret,
      );

      if (!mounted) return;
      if (res['ok'] == true) {
        Navigator.of(context).pop(res);
      } else {
        setState(() {
          _error = res['error']?.toString() ??
              res['message']?.toString() ??
              'Backend rejected target update.';
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final peer = widget.peerState;
    final availableWorkspaces =
        _targetConfig?.availableWorkspaces ?? <ConnectorWorkspaceTarget>[];
    final availableNodes = _targetConfig?.availableNodes.isNotEmpty == true
        ? _targetConfig!.availableNodes
        : widget.allPeers
            .map(
              (p) => {
                'name': p.nodeOsKey,
                'label': '${p.displayHostname} (${p.nodeOsKey.toUpperCase()})',
                'os': p.nodeOsKey,
              },
            )
            .toList();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
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

              // Header
              Row(
                children: [
                  const Icon(
                    Icons.track_changes,
                    color: DeckColors.primaryAccent,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Change Target · ${peer.displayHostname}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: DeckColors.primaryText,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 20,
                      color: DeckColors.mutedText,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Configure the active AI execution target node and target workspace directory on ${peer.displayHostname} (${peer.tailscaleIp}).',
                style: const TextStyle(
                  fontSize: 12,
                  color: DeckColors.secondaryText,
                ),
              ),
              const SizedBox(height: 16),

              if (_isLoadingConfig)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: DeckColors.primaryAccent,
                    ),
                  ),
                )
              else ...[
                if (_error != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: DeckColors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: DeckColors.error.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      _error!,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 11,
                        color: DeckColors.error,
                      ),
                    ),
                  ),
                ],

                // 1. Execution Target Node Selection (from backend configured_nodes)
                Text(
                  'AI EXECUTION TARGET NODE',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: DeckColors.mutedText,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: availableNodes.map((nodeMap) {
                    final nodeKey =
                        (nodeMap['name']?.toString() ?? 'linux').toLowerCase();
                    final nodeLabel =
                        nodeMap['label']?.toString() ?? nodeKey.toUpperCase();
                    final isSelected =
                        _selectedActiveNode.toLowerCase() == nodeKey;

                    return ChoiceChip(
                      label: Text(nodeLabel),
                      selected: isSelected,
                      onSelected: (val) {
                        if (val) {
                          setState(() => _selectedActiveNode = nodeKey);
                        }
                      },
                      selectedColor: DeckColors.primaryAccent,
                      backgroundColor: DeckColors.surfaceElevated,
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.black
                            : DeckColors.primaryText,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 18),

                // 2. Target Workspace Directory on Peer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TARGET WORKSPACE DIRECTORY',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                        color: DeckColors.mutedText,
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _isBrowsingDirs
                          ? null
                          : () => _browseDirectory(
                                _workspaceController.text.trim(),
                              ),
                      icon: const Icon(
                        Icons.folder_open,
                        size: 14,
                        color: DeckColors.informational,
                      ),
                      label: const Text(
                        'Browse Remote Folders',
                        style: TextStyle(
                          fontSize: 11,
                          color: DeckColors.informational,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _workspaceController,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    color: DeckColors.primaryText,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Active Workspace Path',
                    filled: true,
                    fillColor: DeckColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                        color: DeckColors.borderSubtle,
                      ),
                    ),
                  ),
                ),

                // Remote Folder Browser Panel (when active)
                if (_browsedDirectories.isNotEmpty ||
                    _parentBrowsePath != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 165),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: DeckColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DeckColors.borderSubtle),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        if (_parentBrowsePath != null &&
                            _parentBrowsePath!.isNotEmpty)
                          ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: const Icon(
                              Icons.arrow_upward,
                              size: 15,
                              color: DeckColors.primaryAccent,
                            ),
                            title: Text(
                              '.. (${_parentBrowsePath!})',
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: DeckColors.primaryAccent,
                              ),
                            ),
                            onTap: () => _browseDirectory(_parentBrowsePath),
                          ),
                        ..._browsedDirectories.map(
                          (dir) => ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            leading: const Icon(
                              Icons.folder_outlined,
                              size: 16,
                              color: DeckColors.informational,
                            ),
                            title: Text(
                              dir,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 11,
                                color: DeckColors.primaryText,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.subdirectory_arrow_right,
                                size: 15,
                                color: DeckColors.mutedText,
                              ),
                              tooltip: 'Open folder',
                              onPressed: () => _browseDirectory(dir),
                            ),
                            onTap: () {
                              setState(() => _workspaceController.text = dir);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // Available Discovered Workspaces from Backend
                if (availableWorkspaces.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(
                    'AVAILABLE WORKSPACES ON ${peer.displayHostname.toUpperCase()}',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: DeckColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 190),
                    decoration: BoxDecoration(
                      color: DeckColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: DeckColors.borderSubtle),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: availableWorkspaces.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        color: DeckColors.borderSubtle,
                      ),
                      itemBuilder: (ctx, idx) {
                        final ws = availableWorkspaces[idx];
                        final isSelected =
                            _workspaceController.text.trim() == ws.path;
                        return ListTile(
                          dense: true,
                          selected: isSelected,
                          selectedTileColor:
                              DeckColors.primaryAccent.withValues(alpha: 0.1),
                          leading: Icon(
                            ws.isGit ? Icons.commit : Icons.folder_outlined,
                            size: 16,
                            color: isSelected
                                ? DeckColors.primaryAccent
                                : DeckColors.secondaryText,
                          ),
                          title: Text(
                            ws.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? DeckColors.primaryAccent
                                  : DeckColors.primaryText,
                            ),
                          ),
                          subtitle: Text(
                            ws.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: DeckColors.mutedText,
                            ),
                          ),
                          trailing: isSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  size: 16,
                                  color: DeckColors.primaryAccent,
                                )
                              : null,
                          onTap: () {
                            setState(() {
                              _workspaceController.text = ws.path;
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                // 3. Lapdeck Global Device Target Synchronization Switch
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: DeckColors.primaryAccent,
                  checkColor: Colors.black,
                  value: _setAsGlobalDeckTarget,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _setAsGlobalDeckTarget = val);
                    }
                  },
                  title: Text(
                    'Also set ${peer.displayHostname} as active LAPDECK target device',
                    style: const TextStyle(
                      fontSize: 12,
                      color: DeckColors.primaryText,
                    ),
                  ),
                  subtitle: const Text(
                    'Synchronizes Home and Devices tab target selection with this peer.',
                    style: TextStyle(
                      fontSize: 11,
                      color: DeckColors.mutedText,
                    ),
                  ),
                ),

                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DeckColors.primaryAccent,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _isSaving ? null : _saveTargetChanges,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(
                      _isSaving ? 'Applying Target...' : 'Apply Target',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Interactive API Runner Bottom Sheet
// ---------------------------------------------------------------------------

class _ApiRunnerSheet extends StatefulWidget {
  final ConnectorApiItem api;
  final HostTarget initialHost;
  final List<ConnectorPeerNodeState> availablePeers;
  final ConnectorService connectorService;
  final StorageService storage;

  const _ApiRunnerSheet({
    required this.api,
    required this.initialHost,
    required this.availablePeers,
    required this.connectorService,
    required this.storage,
  });

  @override
  State<_ApiRunnerSheet> createState() => _ApiRunnerSheetState();
}

class _ApiRunnerSheetState extends State<_ApiRunnerSheet> {
  final Map<String, TextEditingController> _paramControllers = {};
  late HostTarget _selectedPeerHost;
  bool _isExecuting = false;
  Map<String, dynamic>? _responseResult;
  int? _durationMs;

  @override
  void initState() {
    super.initState();
    _selectedPeerHost = widget.initialHost;
    for (final key in widget.api.parameters.keys) {
      final paramDef = widget.api.parameters[key];
      final defaultVal =
          paramDef is Map ? paramDef['default']?.toString() ?? '' : '';
      _paramControllers[key] = TextEditingController(text: defaultVal);
    }
  }

  @override
  void dispose() {
    for (final c in _paramControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _execute() async {
    setState(() {
      _isExecuting = true;
      _responseResult = null;
    });

    final stopwatch = Stopwatch()..start();

    try {
      final secret = await widget.storage.getConnectorToken(
        _selectedPeerHost.id,
      );
      final body = <String, dynamic>{};
      final query = <String, String>{};

      for (final entry in _paramControllers.entries) {
        if (entry.value.text.trim().isNotEmpty) {
          if (widget.api.method == 'GET') {
            query[entry.key] = entry.value.text.trim();
          } else {
            final paramDef = widget.api.parameters[entry.key];
            final typeStr =
                paramDef is Map ? paramDef['type']?.toString() : 'string';
            if (typeStr == 'boolean') {
              body[entry.key] =
                  entry.value.text.trim().toLowerCase() == 'true';
            } else if (typeStr == 'integer') {
              body[entry.key] =
                  int.tryParse(entry.value.text.trim()) ??
                  entry.value.text.trim();
            } else {
              body[entry.key] = entry.value.text.trim();
            }
          }
        }
      }

      final res = await widget.connectorService.executeDynamicApi(
        _selectedPeerHost,
        path: widget.api.path,
        method: widget.api.method,
        body: widget.api.method != 'GET' ? body : null,
        queryParams: widget.api.method == 'GET' ? query : null,
        secret: secret,
      );

      stopwatch.stop();

      if (mounted) {
        setState(() {
          _responseResult = res;
          _durationMs = stopwatch.elapsedMilliseconds;
        });
      }
    } catch (e) {
      stopwatch.stop();
      if (mounted) {
        setState(() {
          _responseResult = {'ok': false, 'error': e.toString()};
          _durationMs = stopwatch.elapsedMilliseconds;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isExecuting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: widget.api.method == 'POST'
                        ? DeckColors.primaryAccent.withValues(alpha: 0.15)
                        : DeckColors.informational.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    widget.api.method,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: widget.api.method == 'POST'
                          ? DeckColors.primaryAccent
                          : DeckColors.informational,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.api.path,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: DeckColors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.api.description,
              style: const TextStyle(
                color: DeckColors.secondaryText,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),

            // Target Peer Selector for this API call
            if (widget.availablePeers.length > 1) ...[
              Text(
                'EXECUTE ON PEER',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: DeckColors.mutedText,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: widget.availablePeers.map((p) {
                  final isSel = p.host.id == _selectedPeerHost.id;
                  return ChoiceChip(
                    label: Text(p.displayHostname),
                    selected: isSel,
                    onSelected: (val) {
                      if (val) setState(() => _selectedPeerHost = p.host);
                    },
                    selectedColor: DeckColors.primaryAccent,
                    backgroundColor: DeckColors.surfaceElevated,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isSel ? Colors.black : DeckColors.primaryText,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
            ],

            if (widget.api.parameters.isNotEmpty) ...[
              Text(
                'PARAMETERS',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: DeckColors.secondaryText,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 10),
              ...widget.api.parameters.entries.map((param) {
                final paramName = param.key;
                final paramDef = param.value is Map ? param.value as Map : {};
                final desc = paramDef['description']?.toString() ?? '';
                final isRequired = paramDef['required'] == true;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: _paramControllers[paramName],
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 13,
                      color: DeckColors.primaryText,
                    ),
                    decoration: InputDecoration(
                      labelText: '$paramName ${isRequired ? '*' : ''}',
                      helperText: desc.isNotEmpty ? desc : null,
                      filled: true,
                      fillColor: DeckColors.surfaceElevated,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                          color: DeckColors.borderSubtle,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ],

            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: DeckColors.primaryAccent,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _isExecuting ? null : _execute,
                icon: _isExecuting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Icon(Icons.play_arrow, size: 18),
                label: Text(
                  _isExecuting
                      ? 'Executing on ${_selectedPeerHost.name}...'
                      : 'Send Request to ${_selectedPeerHost.name}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),

            if (_responseResult != null) ...[
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'RESPONSE (${_durationMs ?? 0}ms)',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: DeckColors.secondaryText,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.copy,
                      size: 16,
                      color: DeckColors.secondaryText,
                    ),
                    tooltip: 'Copy JSON',
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: jsonEncode(_responseResult)),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Response copied to clipboard'),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: DeckColors.background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DeckColors.borderSubtle),
                ),
                child: SelectableText(
                  const JsonEncoder.withIndent('  ').convert(_responseResult),
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: _responseResult?['ok'] == true
                        ? DeckColors.terminalText
                        : DeckColors.error,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
