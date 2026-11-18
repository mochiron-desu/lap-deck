import 'host_target.dart';

/// Connection state of an individual peer on the Connector mesh.
enum ConnectorPeerConnectionState {
  connecting,
  online,
  offline,
  userStopped;

  String get label => switch (this) {
        ConnectorPeerConnectionState.connecting => 'CONNECTING',
        ConnectorPeerConnectionState.online => 'ONLINE',
        ConnectorPeerConnectionState.offline => 'OFFLINE',
        ConnectorPeerConnectionState.userStopped => 'STOPPED',
      };
}

/// Represents system health and runtime metadata returned by /api/health.
class ConnectorHealthData {
  final bool ok;
  final String hostname;
  final String role;
  final bool isTelegramMain;
  final String roleDescription;
  final String os;
  final String platform;
  final String version;
  final int uptimeSeconds;
  final String lanIp;
  final String tailscaleIp;
  final String? macAddress;
  final String? sshUser;
  final double cpuPercent;
  final double ramPercent;
  final int? ramTotalMb;
  final int? ramAvailableMb;
  final double? diskPercent;
  final double? diskTotalGb;
  final double? diskFreeGb;
  final double? batteryPercent;
  final bool? powerPlugged;
  final String? model;
  final String? conversationId;
  final String? workspace;
  final String? activeNode;
  final bool userStopped;
  final Map<String, bool> peerUserStopped;
  final List<Map<String, dynamic>> configuredNodes;
  final String? gitBranch;
  final String? gitCommit;
  final bool gitClean;
  final DateTime fetchedAt;

  const ConnectorHealthData({
    required this.ok,
    required this.hostname,
    required this.role,
    required this.isTelegramMain,
    required this.roleDescription,
    required this.os,
    required this.platform,
    required this.version,
    required this.uptimeSeconds,
    required this.lanIp,
    required this.tailscaleIp,
    this.macAddress,
    this.sshUser,
    required this.cpuPercent,
    required this.ramPercent,
    this.ramTotalMb,
    this.ramAvailableMb,
    this.diskPercent,
    this.diskTotalGb,
    this.diskFreeGb,
    this.batteryPercent,
    this.powerPlugged,
    this.model,
    this.conversationId,
    this.workspace,
    this.activeNode,
    this.userStopped = false,
    this.peerUserStopped = const {},
    this.configuredNodes = const [],
    this.gitBranch,
    this.gitCommit,
    this.gitClean = true,
    required this.fetchedAt,
  });

  factory ConnectorHealthData.fromJson(Map<String, dynamic> json) {
    final ram = json['ram'] is Map ? json['ram'] as Map : null;
    final disk = json['disk'] is Map ? json['disk'] as Map : null;
    final bat = json['battery'] is Map ? json['battery'] as Map : null;
    final git = json['git'] is Map ? json['git'] as Map : null;

    final stoppedMap = <String, bool>{};
    if (json['peer_user_stopped'] is Map) {
      for (final entry in (json['peer_user_stopped'] as Map).entries) {
        stoppedMap[entry.key.toString().toLowerCase()] = entry.value == true;
      }
    }

    final nodesList = <Map<String, dynamic>>[];
    if (json['configured_nodes'] is List) {
      for (final item in json['configured_nodes'] as List) {
        if (item is Map) {
          nodesList.add(Map<String, dynamic>.from(item));
        }
      }
    }

    return ConnectorHealthData(
      ok: json['ok'] == true,
      hostname: json['hostname']?.toString() ?? 'Unknown',
      role: json['role']?.toString() ?? 'standby',
      isTelegramMain: json['is_telegram_main'] == true ||
          json['role']?.toString().toLowerCase() == 'main',
      roleDescription: json['role_description']?.toString() ?? '',
      os: json['os']?.toString() ?? 'linux',
      platform: json['platform']?.toString() ?? '',
      version: json['version']?.toString() ??
          json['version_str']?.toString() ??
          'unknown',
      uptimeSeconds: (json['uptime_seconds'] as num?)?.toInt() ?? 0,
      lanIp: json['lan_ip']?.toString() ?? '',
      tailscaleIp: json['tailscale_ip']?.toString() ?? '',
      macAddress: json['mac_address']?.toString(),
      sshUser: json['ssh_user']?.toString(),
      cpuPercent: (json['cpu_percent'] as num?)?.toDouble() ?? 0.0,
      ramPercent: (ram?['percent'] as num?)?.toDouble() ?? 0.0,
      ramTotalMb: (ram?['total_mb'] as num?)?.toInt(),
      ramAvailableMb: (ram?['available_mb'] as num?)?.toInt(),
      diskPercent: (disk?['percent'] as num?)?.toDouble(),
      diskTotalGb: (disk?['total_gb'] as num?)?.toDouble(),
      diskFreeGb: (disk?['free_gb'] as num?)?.toDouble(),
      batteryPercent: (bat?['percent'] as num?)?.toDouble(),
      powerPlugged: bat?['power_plugged'] as bool?,
      model: json['model']?.toString(),
      conversationId: json['conversation_id']?.toString(),
      workspace: json['workspace']?.toString(),
      activeNode: json['active_node']?.toString(),
      userStopped: json['user_stopped'] == true,
      peerUserStopped: stoppedMap,
      configuredNodes: nodesList,
      gitBranch: git?['branch']?.toString(),
      gitCommit: git?['commit']?.toString(),
      gitClean: git?['clean'] != false,
      fetchedAt: DateTime.now(),
    );
  }

  String get uptimeHuman {
    final d = Duration(seconds: uptimeSeconds);
    final hours = d.inHours;
    final mins = d.inMinutes % 60;
    if (hours > 24) {
      final days = hours ~/ 24;
      return '${days}d ${hours % 24}h';
    }
    return '${hours}h ${mins}m';
  }

  String get ramSummary {
    if (ramTotalMb != null && ramAvailableMb != null && ramTotalMb! > 0) {
      final usedGb = (ramTotalMb! - ramAvailableMb!) / 1024.0;
      final totalGb = ramTotalMb! / 1024.0;
      return '${ramPercent.toStringAsFixed(1)}% (${usedGb.toStringAsFixed(1)}/${totalGb.toStringAsFixed(1)} GB)';
    }
    return '${ramPercent.toStringAsFixed(1)}%';
  }

  String get diskSummary {
    if (diskPercent == null) return 'N/A';
    if (diskFreeGb != null && diskTotalGb != null) {
      return '${diskPercent!.toStringAsFixed(1)}% (${diskFreeGb!.toStringAsFixed(0)} GB free)';
    }
    return '${diskPercent!.toStringAsFixed(1)}%';
  }
}

/// Live state of an individual peer node in the Connection Management Dashboard.
class ConnectorPeerNodeState {
  final HostTarget host;
  final ConnectorPeerConnectionState connectionState;
  final ConnectorHealthData? health;
  final String? errorMessage;
  final DateTime? lastChecked;

  const ConnectorPeerNodeState({
    required this.host,
    required this.connectionState,
    this.health,
    this.errorMessage,
    this.lastChecked,
  });

  bool get isOnline =>
      connectionState == ConnectorPeerConnectionState.online && health != null;

  bool get isConnecting =>
      connectionState == ConnectorPeerConnectionState.connecting;

  bool get isUserStopped =>
      connectionState == ConnectorPeerConnectionState.userStopped ||
      (health?.userStopped ?? false);

  bool get isMain => isOnline && health!.isTelegramMain;

  bool get isStandby => isOnline && !health!.isTelegramMain;

  String get displayHostname =>
      (health != null && health!.hostname.isNotEmpty)
          ? health!.hostname
          : host.name;

  String get nodeOsKey => (health?.os ?? host.os.name).toLowerCase();

  String get osDisplay {
    if (health != null && health!.platform.isNotEmpty) {
      return health!.platform;
    }
    return host.osDisplayName;
  }

  String get tailscaleIp =>
      (health != null && health!.tailscaleIp.isNotEmpty)
          ? health!.tailscaleIp
          : host.tailscaleIp;

  String get lanIp =>
      (health != null && health!.lanIp.isNotEmpty)
          ? health!.lanIp
          : (host.directIp ?? 'N/A');

  String get roleLabel {
    if (isConnecting) return 'CHECKING';
    if (!isOnline) {
      return isUserStopped ? 'USER STOPPED' : 'OFFLINE';
    }
    return isMain ? 'MAIN' : 'STANDBY';
  }

  ConnectorPeerNodeState copyWith({
    HostTarget? host,
    ConnectorPeerConnectionState? connectionState,
    ConnectorHealthData? health,
    bool clearHealth = false,
    String? errorMessage,
    bool clearError = false,
    DateTime? lastChecked,
  }) {
    return ConnectorPeerNodeState(
      host: host ?? this.host,
      connectionState: connectionState ?? this.connectionState,
      health: clearHealth ? null : (health ?? this.health),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }
}

/// Represents an available workspace directory target on a peer machine.
class ConnectorWorkspaceTarget {
  final String path;
  final String name;
  final bool isGit;
  final bool isCurrent;

  const ConnectorWorkspaceTarget({
    required this.path,
    required this.name,
    this.isGit = false,
    this.isCurrent = false,
  });

  factory ConnectorWorkspaceTarget.fromJson(Map<String, dynamic> json) {
    final p = json['path']?.toString() ?? '';
    return ConnectorWorkspaceTarget(
      path: p,
      name: json['name']?.toString() ?? p,
      isGit: json['is_git'] == true,
      isCurrent: json['is_current'] == true,
    );
  }
}

/// Represents the live target configuration for a peer (returned by /api/peer/target).
class ConnectorTargetConfig {
  final String hostname;
  final String os;
  final String activeNode;
  final String workspace;
  final String? defaultWorkspace;
  final String? model;
  final List<ConnectorWorkspaceTarget> availableWorkspaces;
  final List<Map<String, dynamic>> availableNodes;

  const ConnectorTargetConfig({
    required this.hostname,
    required this.os,
    required this.activeNode,
    required this.workspace,
    this.defaultWorkspace,
    this.model,
    this.availableWorkspaces = const [],
    this.availableNodes = const [],
  });

  factory ConnectorTargetConfig.fromJson(Map<String, dynamic> json) {
    final wsList = <ConnectorWorkspaceTarget>[];
    if (json['available_workspaces'] is List) {
      for (final item in json['available_workspaces'] as List) {
        if (item is Map<String, dynamic>) {
          wsList.add(ConnectorWorkspaceTarget.fromJson(item));
        } else if (item is Map) {
          wsList.add(
            ConnectorWorkspaceTarget.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }

    final nodes = <Map<String, dynamic>>[];
    if (json['available_nodes'] is List) {
      for (final item in json['available_nodes'] as List) {
        if (item is Map) {
          nodes.add(Map<String, dynamic>.from(item));
        }
      }
    }

    return ConnectorTargetConfig(
      hostname: json['hostname']?.toString() ?? '',
      os: json['os']?.toString() ?? 'linux',
      activeNode: json['active_node']?.toString() ?? 'linux',
      workspace: json['workspace']?.toString() ?? '',
      defaultWorkspace: json['default_workspace']?.toString(),
      model: json['model']?.toString(),
      availableWorkspaces: wsList,
      availableNodes: nodes,
    );
  }
}

/// Discovered API endpoint schema descriptor returned by /api/deck/apis.
class ConnectorApiItem {
  final String path;
  final String method;
  final String category;
  final String summary;
  final String description;
  final Map<String, dynamic> parameters;

  const ConnectorApiItem({
    required this.path,
    required this.method,
    required this.category,
    required this.summary,
    required this.description,
    required this.parameters,
  });

  factory ConnectorApiItem.fromJson(Map<String, dynamic> json) {
    return ConnectorApiItem(
      path: json['path']?.toString() ?? '',
      method: (json['method']?.toString() ?? 'GET').toUpperCase(),
      category: json['category']?.toString() ?? 'General',
      summary: json['summary']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      parameters: json['parameters'] is Map<String, dynamic>
          ? json['parameters'] as Map<String, dynamic>
          : {},
    );
  }
}

/// Structured error event parsed from errors.log.
class ConnectorErrorItem {
  final String id;
  final String timestamp;
  final String level;
  final String category;
  final String message;
  final String? sessionId;
  final String? prompt;
  final dynamic details;
  final String? exception;
  final String? traceback;
  final String? peerName;

  const ConnectorErrorItem({
    required this.id,
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.sessionId,
    this.prompt,
    this.details,
    this.exception,
    this.traceback,
    this.peerName,
  });

  factory ConnectorErrorItem.fromJson(
    Map<String, dynamic> json, {
    String? peerName,
  }) {
    return ConnectorErrorItem(
      id: json['id']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
      level: json['level']?.toString() ?? 'ERROR',
      category: json['category']?.toString() ?? 'SYSTEM',
      message: json['message']?.toString() ?? 'Error',
      sessionId: json['session_id']?.toString(),
      prompt: json['prompt']?.toString(),
      details: json['details'],
      exception: json['exception']?.toString(),
      traceback: json['traceback']?.toString(),
      peerName: peerName ?? json['peer_name']?.toString(),
    );
  }
}

/// Media access audit entry returned by /api/media/activity.
class MediaActivityItem {
  final String id;
  final String timestamp;
  final String userId;
  final String userName;
  final String command;
  final String target;
  final String status;
  final Map<String, dynamic> details;
  final String? peerName;

  const MediaActivityItem({
    required this.id,
    required this.timestamp,
    required this.userId,
    required this.userName,
    required this.command,
    required this.target,
    required this.status,
    required this.details,
    this.peerName,
  });

  factory MediaActivityItem.fromJson(
    Map<String, dynamic> json, {
    String? peerName,
  }) {
    return MediaActivityItem(
      id: json['id']?.toString() ?? '',
      timestamp: json['timestamp']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      userName: json['user_name']?.toString() ?? 'Unknown',
      command: json['command']?.toString() ?? '',
      target: json['target']?.toString() ?? '',
      status: json['status']?.toString() ?? 'unknown',
      details: json['details'] is Map<String, dynamic>
          ? json['details'] as Map<String, dynamic>
          : {},
      peerName: peerName ?? json['peer_name']?.toString(),
    );
  }
}

/// Lifecycle state of an individual AI conversation turn in the in-app AI Console.
enum AiTurnStatus {
  streaming,
  completed,
  error,
  aborted;

  String get label => switch (this) {
        AiTurnStatus.streaming => 'IN PROGRESS',
        AiTurnStatus.completed => 'COMPLETED',
        AiTurnStatus.error => 'FAILED',
        AiTurnStatus.aborted => 'ABORTED',
      };
}

/// Immutable representation of a user prompt + Antigravity AI response turn.
class AiConversationTurn {
  final int stepIndex;
  final String prompt;
  final String response;
  final String thinking;
  final List<String> tools;
  final String? currentTool;
  final AiTurnStatus status;
  final String createdAt;
  final int totalTokens;
  final double durationSeconds;
  final String? errorMessage;

  const AiConversationTurn({
    required this.stepIndex,
    required this.prompt,
    this.response = '',
    this.thinking = '',
    this.tools = const [],
    this.currentTool,
    this.status = AiTurnStatus.completed,
    this.createdAt = '',
    this.totalTokens = 0,
    this.durationSeconds = 0.0,
    this.errorMessage,
  });

  AiConversationTurn copyWith({
    int? stepIndex,
    String? prompt,
    String? response,
    String? thinking,
    List<String>? tools,
    String? currentTool,
    bool clearCurrentTool = false,
    AiTurnStatus? status,
    String? createdAt,
    int? totalTokens,
    double? durationSeconds,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AiConversationTurn(
      stepIndex: stepIndex ?? this.stepIndex,
      prompt: prompt ?? this.prompt,
      response: response ?? this.response,
      thinking: thinking ?? this.thinking,
      tools: tools ?? this.tools,
      currentTool: clearCurrentTool ? null : (currentTool ?? this.currentTool),
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      totalTokens: totalTokens ?? this.totalTokens,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  factory AiConversationTurn.fromJson(Map<String, dynamic> json) {
    final rawTools = json['tools'];
    final toolsList = <String>[];
    if (rawTools is List) {
      for (final t in rawTools) {
        final s = t?.toString() ?? '';
        if (s.isNotEmpty) toolsList.add(s);
      }
    }
    final statusStr = (json['status']?.toString() ?? 'completed').toLowerCase();
    final turnStatus = switch (statusStr) {
      'streaming' || 'in_progress' => AiTurnStatus.streaming,
      'error' || 'failed' => AiTurnStatus.error,
      'aborted' => AiTurnStatus.aborted,
      _ => AiTurnStatus.completed,
    };

    return AiConversationTurn(
      stepIndex: (json['step_index'] as num?)?.toInt() ?? 0,
      prompt: json['prompt']?.toString() ?? '',
      response: json['response']?.toString() ?? '',
      thinking: json['thinking']?.toString() ?? '',
      tools: toolsList,
      status: turnStatus,
      createdAt: json['created_at']?.toString() ?? '',
      totalTokens: (json['total_tokens'] as num?)?.toInt() ?? 0,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 0.0,
      errorMessage: json['error']?.toString(),
    );
  }
}

/// Real-time NDJSON stream event emitted by POST /api/turn (stream: true).
class AiStreamEvent {
  final String event; // 'init', 'thinking', 'stream', 'heartbeat', 'final'
  final String? conversationId;
  final String? accumulatedText;
  final String? currentTool;
  final String? thinking;
  final bool? ok;
  final String? status;
  final String? responseText;
  final int? totalTokens;
  final double? durationSeconds;
  final String? error;
  final bool isTimeout;
  final bool isCrash;

  const AiStreamEvent({
    required this.event,
    this.conversationId,
    this.accumulatedText,
    this.currentTool,
    this.thinking,
    this.ok,
    this.status,
    this.responseText,
    this.totalTokens,
    this.durationSeconds,
    this.error,
    this.isTimeout = false,
    this.isCrash = false,
  });

  factory AiStreamEvent.fromJson(Map<String, dynamic> json) {
    return AiStreamEvent(
      event: json['event']?.toString() ?? 'stream',
      conversationId: json['conversation_id']?.toString(),
      accumulatedText: json['accumulated_text']?.toString(),
      currentTool: json['current_tool']?.toString(),
      thinking: json['thinking']?.toString(),
      ok: json['ok'] as bool?,
      status: json['status']?.toString(),
      responseText: json['response_text']?.toString(),
      totalTokens: (json['total_tokens'] as num?)?.toInt(),
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble(),
      error: json['error']?.toString(),
      isTimeout: json['is_timeout'] == true,
      isCrash: json['is_crash'] == true,
    );
  }
}

/// Summary of an indexed past conversation from prompts.db / context search.
class AiSessionSummary {
  final String conversationId;
  final String workspace;
  final String previewPrompt;
  final String timestamp;
  final int promptCount;

  const AiSessionSummary({
    required this.conversationId,
    required this.workspace,
    required this.previewPrompt,
    required this.timestamp,
    this.promptCount = 1,
  });

  factory AiSessionSummary.fromJson(Map<String, dynamic> json) {
    final cid = json['conversation_id']?.toString() ??
        json['conv_id']?.toString() ??
        '';
    final ws = json['workspace']?.toString() ??
        json['folder']?.toString() ??
        '';
    String promptText = json['prompt']?.toString() ??
        json['last_prompt']?.toString() ??
        json['preview']?.toString() ??
        '';
    if (promptText.isEmpty && json['prompts'] is List) {
      final list = json['prompts'] as List;
      if (list.isNotEmpty) {
        final lastItem = list.last;
        if (lastItem is Map) {
          promptText = lastItem['prompt']?.toString() ?? '';
        } else {
          promptText = lastItem.toString();
        }
      }
    }
    return AiSessionSummary(
      conversationId: cid,
      workspace: ws,
      previewPrompt: promptText,
      timestamp: json['timestamp']?.toString() ??
          json['created_at']?.toString() ??
          json['last_active']?.toString() ??
          '',
      promptCount: (json['prompt_count'] as num?)?.toInt() ??
          (json['count'] as num?)?.toInt() ??
          1,
    );
  }
}

