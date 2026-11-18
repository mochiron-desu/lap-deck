import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../models/host_target.dart';
import '../models/connector_models.dart';
import 'app_logger.dart';

class ConnectorService {
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4);

  static const int defaultPort = 8765;

  /// Holds the most recent human-readable error or exception detail.
  String? lastErrorDetail;

  /// Helper to send an authenticated HTTP request to the connector peer server.
  Future<Map<String, dynamic>?> _request({
    required HostTarget host,
    required String path,
    String method = 'GET',
    Map<String, String>? queryParams,
    Map<String, dynamic>? body,
    String? secret,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    final candidateIps = <String>[];
    if (host.tailscaleIp.isNotEmpty) {
      candidateIps.add(host.tailscaleIp);
    }
    if (host.directIp != null &&
        host.directIp!.isNotEmpty &&
        !candidateIps.contains(host.directIp!)) {
      candidateIps.add(host.directIp!);
    }
    if (candidateIps.isEmpty) {
      candidateIps.add('127.0.0.1');
    }

    final maskedSecret = (secret != null && secret.length > 4)
        ? '...${secret.substring(secret.length - 4)}'
        : (secret != null && secret.isNotEmpty ? '***' : 'none');

    AppLogger.debug(
      'ConnectorService',
      '[$method] $path target=${host.name} candidates=$candidateIps token=$maskedSecret',
    );

    for (final ip in candidateIps) {
      final uri = Uri.http(
        '$ip:$defaultPort',
        path,
        queryParams?.isNotEmpty == true ? queryParams : null,
      );

      try {
        AppLogger.debug(
          'ConnectorService',
          'Dispatching $method $uri (timeout: ${timeout.inSeconds}s)...',
        );
        final req = await _httpClient.openUrl(method, uri).timeout(timeout);
        req.headers.set('Content-Type', 'application/json; charset=utf-8');
        if (secret != null && secret.isNotEmpty) {
          req.headers.set('X-Peer-Token', secret);
        }

        if (body != null && (method == 'POST' || method == 'PUT')) {
          final payload = utf8.encode(jsonEncode(body));
          req.headers.contentLength = payload.length;
          req.add(payload);
        }

        final resp = await req.close().timeout(timeout);
        final respBody = await utf8.decodeStream(resp).timeout(timeout);

        if (resp.statusCode >= 200 && resp.statusCode < 300) {
          AppLogger.info(
            'ConnectorService',
            '[$method] $uri SUCCESS (HTTP ${resp.statusCode}, ${respBody.length} bytes)',
          );
          lastErrorDetail = null;
          final decoded = jsonDecode(respBody);
          if (decoded is Map<String, dynamic>) {
            return decoded;
          }
          return {'ok': true, 'data': decoded};
        } else {
          lastErrorDetail = 'HTTP ${resp.statusCode}: $respBody';
          AppLogger.warning(
            'ConnectorService',
            '[$method] $uri REJECTED (HTTP ${resp.statusCode}): $respBody',
          );
        }
      } on SocketException catch (e, st) {
        lastErrorDetail =
            'Socket error on $ip: ${e.message} (OS code ${e.osError?.errorCode})';
        AppLogger.warning(
          'ConnectorService',
          'SocketException on $uri: ${e.message} (errno ${e.osError?.errorCode})',
          e,
          st,
        );
      } on TimeoutException catch (e, st) {
        lastErrorDetail =
            'Timeout connecting to $ip:$defaultPort after ${timeout.inSeconds}s';
        AppLogger.warning(
          'ConnectorService',
          'TimeoutException on $uri after ${timeout.inSeconds}s',
          e,
          st,
        );
      } catch (e, st) {
        lastErrorDetail = '${e.runtimeType}: $e';
        AppLogger.error(
          'ConnectorService',
          'Unhandled error connecting to $uri: $e',
          e,
          st,
        );
      }
    }

    AppLogger.error(
      'ConnectorService',
      'All candidates failed for ${host.name} $path. Last error: $lastErrorDetail',
    );
    return null;
  }

  /// Fetch live system health, vitals, role, and git commit details for a single host.
  Future<ConnectorHealthData?> fetchHealth(
    HostTarget host, {
    String? secret,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final res = await _request(
      host: host,
      path: '/api/health',
      method: 'GET',
      secret: secret,
      timeout: timeout,
    );
    if (res != null && res['ok'] == true) {
      return ConnectorHealthData.fromJson(res);
    }
    return null;
  }

  /// Probes all known peers in parallel, dynamically merging any additional peers
  /// reported by the backend's configured_nodes and reconciling user_stopped flags.
  Future<List<ConnectorPeerNodeState>> fetchAllPeersState(
    List<HostTarget> configuredHosts, {
    required Future<String?> Function(HostTarget) getSecretForHost,
    Set<String> localUserStoppedIds = const {},
  }) async {
    final now = DateTime.now();

    // 1. Query all configured hosts in parallel
    final initialResults = await Future.wait(
      configuredHosts.map((host) async {
        final secret = await getSecretForHost(host);
        final health = await fetchHealth(
          host,
          secret: secret,
          timeout: const Duration(seconds: 4),
        );
        final err = health == null ? lastErrorDetail : null;
        return (host: host, health: health, error: err, secret: secret);
      }),
    );

    // 2. Collect mesh-wide user_stopped states and check for any dynamically discovered nodes
    final meshUserStoppedByOs = <String, bool>{};
    final knownIps = <String>{};
    for (final h in configuredHosts) {
      if (h.tailscaleIp.isNotEmpty) knownIps.add(h.tailscaleIp);
      if (h.directIp != null && h.directIp!.isNotEmpty) {
        knownIps.add(h.directIp!);
      }
    }

    final dynamicHosts = <HostTarget>[];
    String? fallbackSecret;

    for (final item in initialResults) {
      if (item.secret != null && item.secret!.isNotEmpty) {
        fallbackSecret ??= item.secret;
      }
      final hData = item.health;
      if (hData != null) {
        for (final entry in hData.peerUserStopped.entries) {
          if (entry.value) {
            meshUserStoppedByOs[entry.key.toLowerCase()] = true;
          }
        }
        for (final cfgNode in hData.configuredNodes) {
          final tsIp = cfgNode['tailscale_ip']?.toString() ?? '';
          final lanIp = cfgNode['lan_ip']?.toString() ?? '';
          final rawHost = cfgNode['host']?.toString() ?? '';
          final candidateIp = tsIp.isNotEmpty
              ? tsIp
              : (rawHost.isNotEmpty &&
                      rawHost != '127.0.0.1' &&
                      rawHost != 'localhost'
                  ? rawHost
                  : lanIp);
          if (candidateIp.isNotEmpty && !knownIps.contains(candidateIp)) {
            knownIps.add(candidateIp);
            final nodeOsStr =
                (cfgNode['os']?.toString() ?? 'linux').toLowerCase();
            final nodeOs = nodeOsStr == 'windows'
                ? HostOs.windows
                : (nodeOsStr == 'macos' ? HostOs.macos : HostOs.linux);
            final label =
                cfgNode['label']?.toString() ??
                cfgNode['name']?.toString() ??
                candidateIp;
            dynamicHosts.add(
              HostTarget(
                id: 'peer-discovered-$nodeOsStr-$candidateIp',
                name: label,
                tailscaleIp: tsIp.isNotEmpty ? tsIp : candidateIp,
                directIp: lanIp.isNotEmpty ? lanIp : null,
                username: cfgNode['ssh_user']?.toString() ?? 'user',
                os: nodeOs,
              ),
            );
          }
        }
      }
    }

    // 3. Probe any dynamically discovered hosts from backend configuration
    final dynamicResults = await Future.wait(
      dynamicHosts.map((host) async {
        final health = await fetchHealth(
          host,
          secret: fallbackSecret,
          timeout: const Duration(seconds: 4),
        );
        return (
          host: host,
          health: health,
          error: health == null ? lastErrorDetail : null,
          secret: fallbackSecret,
        );
      }),
    );

    final allCombined = [...initialResults, ...dynamicResults];

    // 4. Construct final ConnectorPeerNodeState list
    final peerStates = <ConnectorPeerNodeState>[];
    for (final item in allCombined) {
      final host = item.host;
      final health = item.health;
      final osKey = (health?.os ?? host.os.name).toLowerCase();

      if (health != null) {
        peerStates.add(
          ConnectorPeerNodeState(
            host: host,
            connectionState: ConnectorPeerConnectionState.online,
            health: health,
            lastChecked: health.fetchedAt,
          ),
        );
      } else {
        final isStopped =
            (meshUserStoppedByOs[osKey] == true) ||
            localUserStoppedIds.contains(host.id);
        peerStates.add(
          ConnectorPeerNodeState(
            host: host,
            connectionState: isStopped
                ? ConnectorPeerConnectionState.userStopped
                : ConnectorPeerConnectionState.offline,
            errorMessage: item.error ?? 'Peer unreachable on port $defaultPort',
            lastChecked: now,
          ),
        );
      }
    }

    return peerStates;
  }

  /// Discover all available endpoints exposed by the peer server.
  Future<List<ConnectorApiItem>> fetchApis(
    HostTarget host, {
    String? secret,
  }) async {
    final res = await _request(
      host: host,
      path: '/api/deck/apis',
      method: 'GET',
      secret: secret,
    );
    if (res != null && res['endpoints'] is List) {
      return (res['endpoints'] as List)
          .map((e) => ConnectorApiItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  /// Fetch structured error entries from errors.log.
  Future<Map<String, dynamic>> fetchErrors(
    HostTarget host, {
    String? secret,
    int limit = 50,
    String? category,
  }) async {
    final query = <String, String>{'limit': limit.toString()};
    if (category != null && category.isNotEmpty && category != 'ALL') {
      query['category'] = category;
    }

    final res = await _request(
      host: host,
      path: '/api/errors',
      method: 'GET',
      queryParams: query,
      secret: secret,
    );

    if (res != null) {
      final list = <ConnectorErrorItem>[];
      if (res['errors'] is List) {
        for (final item in res['errors'] as List) {
          if (item is Map<String, dynamic>) {
            list.add(ConnectorErrorItem.fromJson(item, peerName: host.name));
          }
        }
      }
      return {
        'ok': true,
        'totalCount': res['total_count'] ?? list.length,
        'filteredCount': res['filtered_count'] ?? list.length,
        'categoryCounts': res['category_counts'] ?? {},
        'lastErrorTime': res['last_error_time'],
        'errors': list,
      };
    }

    return {
      'ok': false,
      'totalCount': 0,
      'categoryCounts': {},
      'errors': <ConnectorErrorItem>[],
    };
  }

  /// Truncate/clear the errors.log file.
  Future<bool> clearErrors(
    HostTarget host, {
    String? secret,
  }) async {
    final res = await _request(
      host: host,
      path: '/api/errors/clear',
      method: 'POST',
      secret: secret,
    );
    return res != null && res['ok'] == true;
  }

  /// Fetch recent media commands activity history.
  Future<List<MediaActivityItem>> fetchMediaActivity(
    HostTarget host, {
    String? secret,
    int limit = 30,
  }) async {
    final res = await _request(
      host: host,
      path: '/api/media/activity',
      method: 'GET',
      queryParams: {'limit': limit.toString()},
      secret: secret,
    );

    if (res != null && res['activities'] is List) {
      return (res['activities'] as List)
          .map(
            (e) => MediaActivityItem.fromJson(
              e as Map<String, dynamic>,
              peerName: host.name,
            ),
          )
          .toList();
    }
    return [];
  }

  /// Fetch media status summary (cooldowns, active jobs, trusted users).
  Future<Map<String, dynamic>?> fetchMediaStatus(
    HostTarget host, {
    String? secret,
  }) async {
    final res = await _request(
      host: host,
      path: '/api/media/status',
      method: 'GET',
      secret: secret,
    );
    return res?['summary'] as Map<String, dynamic>?;
  }

  /// Perform user-initiated start, stop, or restart of a peer node.
  /// Handles both direct self-targeting (when the peer is online) and
  /// mesh-assisted revival/lockout via online peers.
  Future<Map<String, dynamic>> executeLifecycle(
    HostTarget host, {
    required String node,
    required String action,
    bool userStopped = true,
    String? reason,
    String? secret,
    List<HostTarget> otherOnlinePeers = const [],
  }) async {
    final cleanAction = action.toLowerCase().trim();
    final nodeOs = node.toLowerCase().trim();

    if (cleanAction == 'stop') {
      // 1. Mark user_stopped on all other online peers first so their watchdogs
      // never try to auto-revive this node when it goes down.
      for (final other in otherOnlinePeers) {
        if (other.id == host.id) continue;
        unawaited(
          _request(
            host: other,
            path: '/api/peer/lifecycle',
            method: 'POST',
            body: {
              'node': nodeOs,
              'action': 'stop',
              'user_stopped': true,
              'reason': reason ?? 'User-initiated stop from Lapdeck',
            },
            secret: secret,
            timeout: const Duration(seconds: 4),
          ),
        );
      }

      // 2. Send stop directly to the target peer itself
      final res = await _request(
        host: host,
        path: '/api/peer/lifecycle',
        method: 'POST',
        body: {
          'node': 'self',
          'action': 'stop',
          'user_stopped': userStopped,
          'reason': reason ?? 'User-initiated stop from Lapdeck',
        },
        secret: secret,
        timeout: const Duration(seconds: 6),
      );

      if (res != null) return res;
      if (otherOnlinePeers.isNotEmpty) {
        return {
          'ok': true,
          'action': 'stop',
          'node': nodeOs,
          'user_stopped': true,
          'message': 'Peer marked user-stopped across mesh.',
        };
      }
      return {
        'ok': false,
        'error': lastErrorDetail ?? 'Could not reach ${host.name} to stop daemon.',
      };
    }

    if (cleanAction == 'start') {
      // If starting a stopped/offline peer, ask an online peer to revive it via WOL + SSH
      for (final onlinePeer in otherOnlinePeers) {
        if (onlinePeer.id == host.id) continue;
        final res = await _request(
          host: onlinePeer,
          path: '/api/peer/lifecycle',
          method: 'POST',
          body: {
            'node': nodeOs,
            'action': 'start',
            'user_stopped': false,
            'reason': reason ?? 'User-initiated start from Lapdeck',
          },
          secret: secret,
          timeout: const Duration(seconds: 15),
        );
        if (res != null && res['ok'] == true) {
          return res;
        }
      }

      // Also probe the host directly in case it is already running
      final directRes = await _request(
        host: host,
        path: '/api/peer/lifecycle',
        method: 'POST',
        body: {
          'node': 'self',
          'action': 'start',
          'user_stopped': false,
          'reason': reason ?? 'User-initiated start from Lapdeck',
        },
        secret: secret,
        timeout: const Duration(seconds: 5),
      );
      if (directRes != null) return directRes;

      return {
        'ok': false,
        'error': lastErrorDetail ??
            'Could not revive ${host.name} via mesh API.',
      };
    }

    // Default: restart
    final res = await _request(
      host: host,
      path: '/api/peer/lifecycle',
      method: 'POST',
      body: {
        'node': 'self',
        'action': cleanAction,
        'user_stopped': false,
        'reason': reason ?? 'Lifecycle restart initiated from Lapdeck',
      },
      secret: secret,
      timeout: const Duration(seconds: 8),
    );

    if (res != null) return res;

    // Fallback: ask an online peer to restart the target node
    for (final onlinePeer in otherOnlinePeers) {
      if (onlinePeer.id == host.id) continue;
      final peerRes = await _request(
        host: onlinePeer,
        path: '/api/peer/lifecycle',
        method: 'POST',
        body: {
          'node': nodeOs,
          'action': 'restart',
          'user_stopped': false,
          'reason': reason ?? 'Remote restart initiated from Lapdeck',
        },
        secret: secret,
        timeout: const Duration(seconds: 10),
      );
      if (peerRes != null && peerRes['ok'] == true) {
        return peerRes;
      }
    }

    return {
      'ok': false,
      'error': lastErrorDetail ??
          'Network timeout or unreachable host on port $defaultPort',
    };
  }

  /// Promote a Standby node to Telegram Main and demote existing Main peers.
  Future<Map<String, dynamic>> promoteMain(
    HostTarget targetHost, {
    List<HostTarget> allPeers = const [],
    String? reason,
    String? secret,
  }) async {
    final auditReason =
        reason ?? 'Promoted ${targetHost.name} to Telegram Main via Lapdeck';

    // 1. Demote any other online peers first so Telegram polling transfers cleanly
    for (final other in allPeers) {
      if (other.id == targetHost.id) continue;
      try {
        await _request(
          host: other,
          path: '/api/peer/demote',
          method: 'POST',
          body: {'reason': auditReason},
          secret: secret,
          timeout: const Duration(seconds: 4),
        );
      } catch (_) {}
    }

    // 2. Promote the selected Standby peer to Main
    final res = await _request(
      host: targetHost,
      path: '/api/peer/promote',
      method: 'POST',
      body: {
        'reason': auditReason,
        'target_node': targetHost.os.name,
        'demote_peers': true,
      },
      secret: secret,
      timeout: const Duration(seconds: 8),
    );

    return res ??
        {
          'ok': false,
          'error': lastErrorDetail ?? 'Failed to promote ${targetHost.name} to Main',
        };
  }

  /// Fetch current target configuration (workspace, active execution target node, and available targets).
  /// Falls back to /api/health + /api/files/list if the peer hasn't pulled /api/peer/target yet.
  Future<ConnectorTargetConfig?> fetchPeerTargetConfig(
    HostTarget host, {
    String? secret,
    ConnectorHealthData? cachedHealth,
  }) async {
    final res = await _request(
      host: host,
      path: '/api/peer/target',
      method: 'GET',
      secret: secret,
      timeout: const Duration(seconds: 5),
    );

    if (res != null && res['ok'] == true) {
      return ConnectorTargetConfig.fromJson(res);
    }

    // Fallback for peers on older commits: combine /api/health and /api/files/list
    final health = cachedHealth ?? await fetchHealth(host, secret: secret);
    if (health == null) return null;

    final currentWs = health.workspace ?? '';
    final discoveredWorkspaces = <ConnectorWorkspaceTarget>[];

    if (currentWs.isNotEmpty) {
      discoveredWorkspaces.add(
        ConnectorWorkspaceTarget(
          path: currentWs,
          name: _basename(currentWs),
          isCurrent: true,
        ),
      );
    }

    // Query directory listing for current workspace or its parent to discover real folders
    final dirListing = await listDirectories(
      host,
      path: currentWs.isNotEmpty ? currentWs : null,
      secret: secret,
    );
    if (dirListing['ok'] == true) {
      final parentPath = dirListing['parent']?.toString();
      final dirs = dirListing['directories'] as List<String>? ?? [];
      for (final d in dirs) {
        if (!discoveredWorkspaces.any((w) => w.path == d)) {
          discoveredWorkspaces.add(
            ConnectorWorkspaceTarget(
              path: d,
              name: _basename(d),
              isCurrent: d == currentWs,
            ),
          );
        }
      }
      if (parentPath != null && parentPath.isNotEmpty) {
        final parentListing = await listDirectories(
          host,
          path: parentPath,
          secret: secret,
        );
        if (parentListing['ok'] == true) {
          final siblingDirs =
              parentListing['directories'] as List<String>? ?? [];
          for (final d in siblingDirs) {
            if (!discoveredWorkspaces.any((w) => w.path == d)) {
              discoveredWorkspaces.add(
                ConnectorWorkspaceTarget(
                  path: d,
                  name: _basename(d),
                  isCurrent: d == currentWs,
                ),
              );
            }
          }
        }
      }
    }

    return ConnectorTargetConfig(
      hostname: health.hostname,
      os: health.os,
      activeNode: health.activeNode ?? health.os,
      workspace: currentWs,
      model: health.model,
      availableWorkspaces: discoveredWorkspaces,
      availableNodes: health.configuredNodes.isNotEmpty
          ? health.configuredNodes
          : [
              {'name': 'linux', 'label': 'Linux Node', 'os': 'linux'},
              {'name': 'windows', 'label': 'Windows Node', 'os': 'windows'},
            ],
    );
  }

  /// Browse directories on a peer using the existing /api/files/list endpoint.
  Future<Map<String, dynamic>> listDirectories(
    HostTarget host, {
    String? path,
    String? secret,
  }) async {
    final res = await _request(
      host: host,
      path: '/api/files/list',
      method: 'GET',
      queryParams: (path != null && path.isNotEmpty) ? {'path': path} : null,
      secret: secret,
      timeout: const Duration(seconds: 5),
    );

    if (res != null && res['ok'] == true) {
      final currentPath = res['path']?.toString() ?? path ?? '';
      final parentPath = res['parent']?.toString();
      final sep = currentPath.contains('\\') ? '\\' : '/';
      final dirs = <String>[];

      if (res['entries'] is List) {
        for (final entry in res['entries'] as List) {
          if (entry is Map && entry['is_dir'] == true) {
            final name = entry['name']?.toString() ?? '';
            if (name.isEmpty || name.startsWith('.') || name.startsWith('\$')) {
              continue;
            }
            final fullPath = currentPath.endsWith(sep)
                ? '$currentPath$name'
                : '$currentPath$sep$name';
            dirs.add(fullPath);
          }
        }
      }

      return {
        'ok': true,
        'path': currentPath,
        'parent': parentPath,
        'directories': dirs,
      };
    }

    return {
      'ok': false,
      'error': lastErrorDetail ?? 'Could not list directories on ${host.name}',
      'directories': <String>[],
    };
  }

  /// Update target workspace directory and/or active execution target node for a peer.
  Future<Map<String, dynamic>> updatePeerTarget(
    HostTarget host, {
    String? workspace,
    String? activeNode,
    String? model,
    String? secret,
  }) async {
    final body = <String, dynamic>{};
    if (workspace != null && workspace.trim().isNotEmpty) {
      body['workspace'] = workspace.trim();
    }
    if (activeNode != null && activeNode.trim().isNotEmpty) {
      body['active_node'] = activeNode.trim().toLowerCase();
    }
    if (model != null && model.trim().isNotEmpty) {
      body['model'] = model.trim();
    }

    // 1. Try dedicated /api/peer/target endpoint
    final res = await _request(
      host: host,
      path: '/api/peer/target',
      method: 'POST',
      body: body,
      secret: secret,
      timeout: const Duration(seconds: 6),
    );

    if (res != null && res['ok'] == true) {
      return res;
    }

    // 2. If the peer returned 404 (running an older commit without /api/peer/target),
    // verify the directory via /api/files/list and update state.json via /api/sync/pull + /api/sync/push
    if (workspace != null &&
        workspace.trim().isNotEmpty &&
        (lastErrorDetail?.contains('404') ?? false)) {
      final cleanWs = workspace.trim();
      final checkDir = await _request(
        host: host,
        path: '/api/files/list',
        method: 'GET',
        queryParams: {'path': cleanWs},
        secret: secret,
        timeout: const Duration(seconds: 5),
      );
      if (checkDir == null || checkDir['ok'] != true) {
        return {
          'ok': false,
          'error': 'Directory not found or inaccessible on ${host.name}: $cleanWs',
        };
      }

      final pulled = await _request(
        host: host,
        path: '/api/sync/pull',
        method: 'GET',
        queryParams: {'file': 'state.json'},
        secret: secret,
      );
      final statePayload = (pulled != null && pulled['payload'] is Map)
          ? Map<String, dynamic>.from(pulled['payload'] as Map)
          : <String, dynamic>{};
      statePayload['workspace'] = cleanWs;
      if (model != null && model.trim().isNotEmpty) {
        statePayload['model'] = model.trim();
      }

      final pushed = await _request(
        host: host,
        path: '/api/sync/push',
        method: 'POST',
        body: {
          'file': 'state.json',
          'payload': statePayload,
          'merge': false,
          'is_main': true,
        },
        secret: secret,
      );

      if (pushed != null && pushed['ok'] == true) {
        return {
          'ok': true,
          'workspace': cleanWs,
          'active_node': activeNode ?? host.os.name,
          'message': 'Target workspace updated to $cleanWs on ${host.name}',
        };
      }
    }

    return {
      'ok': false,
      'error': lastErrorDetail ?? 'Failed to update target on ${host.name}',
    };
  }

  /// Trigger Git Sync on target node.
  Future<Map<String, dynamic>> triggerGitSync(
    HostTarget host, {
    String? secret,
  }) async {
    final res = await _request(
      host: host,
      path: '/api/peer/git-sync',
      method: 'POST',
      secret: secret,
      timeout: const Duration(seconds: 15),
    );
    return res ??
        {'ok': false, 'error': lastErrorDetail ?? 'Git sync timed out'};
  }

  /// Dynamically execute any discovered API endpoint.
  Future<Map<String, dynamic>> executeDynamicApi(
    HostTarget host, {
    required String path,
    required String method,
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    String? secret,
  }) async {
    final res = await _request(
      host: host,
      path: path,
      method: method,
      queryParams: queryParams,
      body: body,
      secret: secret,
      timeout: const Duration(seconds: 12),
    );
    return res ??
        {
          'ok': false,
          'error': lastErrorDetail ?? 'Request failed or host unreachable',
        };
  }

  String _basename(String fullPath) {
    final normalized = fullPath.replaceAll('\\', '/');
    final trimmed = normalized.endsWith('/') && normalized.length > 1
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
    final idx = trimmed.lastIndexOf('/');
    if (idx >= 0 && idx < trimmed.length - 1) {
      return trimmed.substring(idx + 1);
    }
    return fullPath;
  }
}
