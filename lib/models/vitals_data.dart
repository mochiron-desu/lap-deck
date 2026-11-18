class VitalsData {
  final double cpuPercent;
  final String loadAvg;
  final double ramPercent;
  final String ramUsage;
  final double diskPercent;
  final String diskUsage;
  final String uptime;
  final DateTime timestamp;

  const VitalsData({
    required this.cpuPercent,
    required this.loadAvg,
    required this.ramPercent,
    required this.ramUsage,
    required this.diskPercent,
    required this.diskUsage,
    required this.uptime,
    required this.timestamp,
  });

  factory VitalsData.empty() {
    return VitalsData(
      cpuPercent: 0,
      loadAvg: '0.00',
      ramPercent: 0,
      ramUsage: '0.0 / 0.0 GB',
      diskPercent: 0,
      diskUsage: '0 / 0 GB',
      uptime: 'Offline / Standby',
      timestamp: DateTime.now(),
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

  const LapdogStatus({
    this.isInstalled = false,
    this.isAwayArmed = false,
    this.pendingEvents = 0,
    this.sentHistory = 0,
    this.version = '',
  });
}
