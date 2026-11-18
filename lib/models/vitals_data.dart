class VitalsData {
  final double cpuPercent;
  final String loadAvg;
  final double ramPercent;
  final String ramUsage;
  final double diskPercent;
  final String diskUsage;
  final String uptime;
  final DateTime timestamp;
  final bool isVerified;

  const VitalsData({
    required this.cpuPercent,
    required this.loadAvg,
    required this.ramPercent,
    required this.ramUsage,
    required this.diskPercent,
    required this.diskUsage,
    required this.uptime,
    required this.timestamp,
    this.isVerified = false,
  });

  factory VitalsData.empty() {
    return VitalsData(
      cpuPercent: 0,
      loadAvg: '0.00',
      ramPercent: 0,
      ramUsage: '0.0 / 0.0 GB',
      diskPercent: 0,
      diskUsage: '0 / 0 GB',
      uptime: 'Unavailable',
      timestamp: DateTime.now(),
      isVerified: false,
    );
  }
}

class ProcessItem {
  final int pid;
  final String name;
  final double cpuPercent;
  final double memPercent;
  final String user;

  const ProcessItem({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    required this.memPercent,
    required this.user,
  });
}

class LapdogStatus {
  final bool isInstalled;
  final bool isAwayArmed;
  final int pendingEvents;
  final int sentHistory;
  final String version;
  final DateTime? lastChecked;
  final bool isVerified;

  const LapdogStatus({
    this.isInstalled = false,
    this.isAwayArmed = false,
    this.pendingEvents = 0,
    this.sentHistory = 0,
    this.version = '',
    this.lastChecked,
    this.isVerified = false,
  });
}

/// Lifecycle feedback states required by Section 6.
enum OperationLifecycleState {
  ready,
  inProgress,
  successful,
  failed,
  timedOut,
  resultUnknown,
  targetUnavailable,
}

extension OperationLifecycleStateExt on OperationLifecycleState {
  String get label {
    return switch (this) {
      OperationLifecycleState.ready => 'Ready',
      OperationLifecycleState.inProgress => 'In progress',
      OperationLifecycleState.successful => 'Successful',
      OperationLifecycleState.failed => 'Failed',
      OperationLifecycleState.timedOut => 'Timed out',
      OperationLifecycleState.resultUnknown => 'Result unknown',
      OperationLifecycleState.targetUnavailable => 'Target unavailable',
    };
  }
}

class OperationFeedback {
  final String id;
  final String operationName;
  final String targetHostId;
  final String targetHostName;
  final OperationLifecycleState state;
  final String summary;
  final String? technicalDetails;
  final DateTime timestamp;

  const OperationFeedback({
    required this.id,
    required this.operationName,
    required this.targetHostId,
    required this.targetHostName,
    required this.state,
    required this.summary,
    this.technicalDetails,
    required this.timestamp,
  });

  bool get isBusy => state == OperationLifecycleState.inProgress;
}

class DiagnosticCheckResult {
  final String id;
  final String title;
  final String description;
  final OperationLifecycleState state;
  final String? detail;
  final int? durationMs;

  const DiagnosticCheckResult({
    required this.id,
    required this.title,
    required this.description,
    this.state = OperationLifecycleState.ready,
    this.detail,
    this.durationMs,
  });

  DiagnosticCheckResult copyWith({
    OperationLifecycleState? state,
    String? detail,
    int? durationMs,
  }) {
    return DiagnosticCheckResult(
      id: id,
      title: title,
      description: description,
      state: state ?? this.state,
      detail: detail ?? this.detail,
      durationMs: durationMs ?? this.durationMs,
    );
  }
}
