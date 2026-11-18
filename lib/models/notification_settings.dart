/// Immutable configuration governing which native Android notifications LapDeck emits.
class NotificationSettings {
  final bool masterEnabled;
  final bool peerStatusTransitions;
  final bool subsystemAndConnectorErrors;
  final bool lapdogSecurityEvents;
  final bool aiTurnCompletion;
  final bool otaUpdateAvailable;

  const NotificationSettings({
    this.masterEnabled = true,
    this.peerStatusTransitions = true,
    this.subsystemAndConnectorErrors = true,
    this.lapdogSecurityEvents = true,
    this.aiTurnCompletion = true,
    this.otaUpdateAvailable = true,
  });

  NotificationSettings copyWith({
    bool? masterEnabled,
    bool? peerStatusTransitions,
    bool? subsystemAndConnectorErrors,
    bool? lapdogSecurityEvents,
    bool? aiTurnCompletion,
    bool? otaUpdateAvailable,
  }) {
    return NotificationSettings(
      masterEnabled: masterEnabled ?? this.masterEnabled,
      peerStatusTransitions:
          peerStatusTransitions ?? this.peerStatusTransitions,
      subsystemAndConnectorErrors:
          subsystemAndConnectorErrors ?? this.subsystemAndConnectorErrors,
      lapdogSecurityEvents: lapdogSecurityEvents ?? this.lapdogSecurityEvents,
      aiTurnCompletion: aiTurnCompletion ?? this.aiTurnCompletion,
      otaUpdateAvailable: otaUpdateAvailable ?? this.otaUpdateAvailable,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'masterEnabled': masterEnabled,
      'peerStatusTransitions': peerStatusTransitions,
      'subsystemAndConnectorErrors': subsystemAndConnectorErrors,
      'lapdogSecurityEvents': lapdogSecurityEvents,
      'aiTurnCompletion': aiTurnCompletion,
      'otaUpdateAvailable': otaUpdateAvailable,
    };
  }

  factory NotificationSettings.fromMap(Map<String, dynamic> map) {
    return NotificationSettings(
      masterEnabled: map['masterEnabled'] as bool? ?? true,
      peerStatusTransitions: map['peerStatusTransitions'] as bool? ?? true,
      subsystemAndConnectorErrors:
          map['subsystemAndConnectorErrors'] as bool? ?? true,
      lapdogSecurityEvents: map['lapdogSecurityEvents'] as bool? ?? true,
      aiTurnCompletion: map['aiTurnCompletion'] as bool? ?? true,
      otaUpdateAvailable: map['otaUpdateAvailable'] as bool? ?? true,
    );
  }
}

/// Compile-time and runtime version metadata for LapDeck and Git OTA hotfixes.
class AppVersionInfo {
  static const String currentVersion = '1.2.0';
  static const int currentBuildNumber = 37;
  static const String shortVersionBadge = 'v1.2';
  static const String githubRepoSlug = 'mochiron-desu/lap-deck';

  static const String compiledCommitSha = String.fromEnvironment(
    'GIT_COMMIT_SHA',
    defaultValue: 'local-HEAD',
  );
  static const String compiledBranch = String.fromEnvironment(
    'GIT_BRANCH',
    defaultValue: 'main',
  );
}

enum OtaUpdateState {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  buildingOnPeer,
  readyToInstall,
  error;

  String get label => switch (this) {
        OtaUpdateState.idle => 'IDLE',
        OtaUpdateState.checking => 'CHECKING',
        OtaUpdateState.upToDate => 'UP TO DATE',
        OtaUpdateState.updateAvailable => 'UPDATE AVAILABLE',
        OtaUpdateState.downloading => 'DOWNLOADING',
        OtaUpdateState.buildingOnPeer => 'BUILDING ON PEER',
        OtaUpdateState.readyToInstall => 'READY TO INSTALL',
        OtaUpdateState.error => 'CHECK FAILED',
      };
}

/// Immutable snapshot of a Git hotfix / OTA update check.
class OtaUpdateInfo {
  final OtaUpdateState state;
  final String installedCommitSha;
  final String? latestCommitSha;
  final String? latestCommitMessage;
  final String? latestAuthor;
  final DateTime? commitDate;
  final String? apkDownloadUrl;
  final int? apkSizeBytes;
  final String? releaseTag;
  final String? errorMessage;
  final DateTime checkedAt;

  const OtaUpdateInfo({
    required this.state,
    required this.installedCommitSha,
    this.latestCommitSha,
    this.latestCommitMessage,
    this.latestAuthor,
    this.commitDate,
    this.apkDownloadUrl,
    this.apkSizeBytes,
    this.releaseTag,
    this.errorMessage,
    required this.checkedAt,
  });

  bool get hasNewerCommit {
    if (latestCommitSha == null || latestCommitSha!.isEmpty) return false;
    if (installedCommitSha.isEmpty || installedCommitSha == 'local-HEAD') {
      return state == OtaUpdateState.updateAvailable;
    }
    final cleanInstalled = installedCommitSha.trim().toLowerCase();
    final cleanLatest = latestCommitSha!.trim().toLowerCase();
    return !cleanLatest.startsWith(cleanInstalled) &&
        !cleanInstalled.startsWith(cleanLatest);
  }

  bool get hasDirectApkAsset =>
      apkDownloadUrl != null && apkDownloadUrl!.isNotEmpty;

  String get shortInstalledSha => installedCommitSha.length > 7
      ? installedCommitSha.substring(0, 7)
      : installedCommitSha;

  String get shortLatestSha =>
      (latestCommitSha != null && latestCommitSha!.length > 7)
          ? latestCommitSha!.substring(0, 7)
          : (latestCommitSha ?? 'unknown');

  String get formattedApkSize {
    if (apkSizeBytes == null || apkSizeBytes! <= 0) return '';
    final mb = apkSizeBytes! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}
