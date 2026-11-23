import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/host_target.dart';
import '../../models/notification_settings.dart';
import '../../services/app_logger.dart';
import '../../services/notification_service.dart';
import '../../services/ota_update_service.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../theme/deck_theme.dart';
import '../widgets/log_viewer_sheet.dart';

class SettingsTab extends StatefulWidget {
  final StorageService storage;
  final NotificationService? notificationService;
  final OtaUpdateService? otaUpdateService;
  final SshService? sshService;
  final List<HostTarget> hosts;

  const SettingsTab({
    super.key,
    required this.storage,
    this.notificationService,
    this.otaUpdateService,
    this.sshService,
    this.hosts = const [],
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _enableLanFailover = true;
  int _timeoutSeconds = 4;
  String _connectorToken = '';
  String _githubToken = '';

  late NotificationSettings _notifSettings;
  bool _osNotifGranted = false;

  late OtaUpdateService _otaService;
  OtaUpdateInfo? _otaInfo;
  bool _isCheckingOta = false;
  bool _isInstallingOta = false;
  double _otaProgress = 0.0;
  String _otaStatusText = '';
  String? _otaFeedbackMsg;
  bool _otaFeedbackOk = true;

  @override
  void initState() {
    super.initState();
    _notifSettings = widget.storage.loadNotificationSettings();
    _otaService = widget.otaUpdateService ??
        OtaUpdateService(
          storage: widget.storage,
          notificationService: widget.notificationService,
        );
    _otaInfo = _otaService.lastCheckInfo;
    _loadTokensAndPermissions();
  }

  Future<void> _loadTokensAndPermissions() async {
    final token = await widget.storage.getConnectorToken();
    final ghToken = await widget.storage.getGithubToken() ?? '';
    final granted =
        await (widget.notificationService?.areNotificationsGranted() ??
            Future.value(false));
    if (mounted) {
      setState(() {
        _connectorToken = token;
        _githubToken = ghToken;
        _osNotifGranted = granted;
      });
    }
  }

  Future<void> _updateNotifSettings(NotificationSettings updated) async {
    HapticFeedback.lightImpact();
    setState(() => _notifSettings = updated);
    await widget.storage.saveNotificationSettings(updated);
    if (updated.masterEnabled && !_osNotifGranted) {
      final granted =
          await (widget.notificationService?.requestPermission() ??
              Future.value(false));
      if (mounted) {
        setState(() => _osNotifGranted = granted);
      }
    }
  }

  Future<void> _handleCheckGitUpdates() async {
    if (_isCheckingOta || _isInstallingOta) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isCheckingOta = true;
      _otaFeedbackMsg = null;
    });

    final info = await _otaService.checkForGitUpdates();
    if (!mounted) return;
    setState(() {
      _otaInfo = info;
      _isCheckingOta = false;
      if (info.state == OtaUpdateState.upToDate) {
        _otaFeedbackOk = true;
        _otaFeedbackMsg =
            'App is up to date on Git commit ${info.shortLatestSha}.';
      } else if (info.state == OtaUpdateState.error) {
        _otaFeedbackOk = false;
        _otaFeedbackMsg = info.errorMessage;
      }
    });
  }

  Future<void> _handleDownloadGitHotfix() async {
    if (_otaInfo == null || _isInstallingOta) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isInstallingOta = true;
      _otaProgress = 0.02;
      _otaStatusText = 'Starting GitHub OTA hotfix download...';
      _otaFeedbackMsg = null;
    });

    final res = await _otaService.downloadAndInstallGitHotfix(
      updateInfo: _otaInfo!,
      onProgress: (p, status) {
        if (mounted) {
          setState(() {
            _otaProgress = p;
            _otaStatusText = status;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _isInstallingOta = false;
      _otaFeedbackOk = res.ok;
      _otaFeedbackMsg = res.message;
    });
  }

  Future<void> _handleBuildViaPeer(HostTarget peer) async {
    if (widget.sshService == null || _isInstallingOta) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _isInstallingOta = true;
      _otaProgress = 0.05;
      _otaStatusText = 'Connecting to ${peer.name} for Git pull & APK build...';
      _otaFeedbackMsg = null;
    });

    final res = await _otaService.pullAndBuildViaPeer(
      peer: peer,
      sshService: widget.sshService!,
      onProgress: (p, status) {
        if (mounted) {
          setState(() {
            _otaProgress = p;
            _otaStatusText = status;
          });
        }
      },
    );

    if (!mounted) return;
    setState(() {
      _isInstallingOta = false;
      _otaFeedbackOk = res.ok;
      _otaFeedbackMsg = res.message;
    });
  }

  Future<void> _editGithubTokenDialog() async {
    final controller = TextEditingController(text: _githubToken);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceElevated,
        title: const Text(
          'GitHub Personal Access Token (OTA)',
          style: TextStyle(color: DeckColors.primaryText, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Optional GitHub PAT stored in Android Keystore for checking commits and downloading hotfix APK releases from mochiron-desu/lap-deck if the repository is private.',
              style: TextStyle(color: DeckColors.secondaryText, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: DeckColors.primaryText,
              ),
              decoration: InputDecoration(
                labelText: 'ghp_... / github_pat_...',
                labelStyle: const TextStyle(color: DeckColors.mutedText),
                filled: true,
                fillColor: DeckColors.surfaceSecondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
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
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updated != null) {
      await widget.storage.saveGithubToken(updated);
      await _loadTokensAndPermissions();
    }
  }

  Future<void> _editConnectorTokenDialog() async {
    final controller = TextEditingController(text: _connectorToken);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceElevated,
        title: const Text(
          'Connector API Secret',
          style: TextStyle(color: DeckColors.primaryText, fontSize: 16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pre-shared secret used for authenticated calls to telegram-antigravity-connector (PEER_SECRET) on port 8765.',
              style: TextStyle(color: DeckColors.secondaryText, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: DeckColors.primaryText,
              ),
              decoration: InputDecoration(
                labelText: 'X-Peer-Token / Secret',
                labelStyle: const TextStyle(color: DeckColors.mutedText),
                filled: true,
                fillColor: DeckColors.surfaceSecondary,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                controller.text = StorageService.defaultConnectorSecret;
              },
              child: const Text(
                'Reset to Default Secret',
                style: TextStyle(fontSize: 12, color: DeckColors.primaryAccent),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
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
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (updated != null && updated.isNotEmpty) {
      await widget.storage.saveConnectorToken(updated);
      await _loadTokensAndPermissions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Connector token updated'),
            backgroundColor: DeckColors.surfaceElevated,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maskedToken = _connectorToken.length > 8
        ? '${_connectorToken.substring(0, 4)}••••••••${_connectorToken.substring(_connectorToken.length - 4)}'
        : (_connectorToken.isNotEmpty ? '••••••••' : 'Not configured');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: DeckColors.background,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // Section 1: App Hotfix & Git OTA Updates
            _buildSectionHeader('APP HOTFIX & GIT OTA UPDATES'),
            const SizedBox(height: 8),
            _buildOtaHotfixCard(),
            const SizedBox(height: 24),

            // Section 2: Native Android Notifications & Alerts
            _buildSectionHeader('NATIVE NOTIFICATIONS & ALERTS'),
            const SizedBox(height: 8),
            _buildNotificationsCard(),
            const SizedBox(height: 24),

            // Section 3: Network & Connection
            _buildSectionHeader('NETWORK & FAILOVER'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: DeckColors.surfaceSecondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DeckColors.borderSubtle, width: 1),
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text(
                      'Direct LAN failover',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    subtitle: const Text(
                      'Automatically connect via local 192.168.29.x if Tailscale drops',
                      style:
                          TextStyle(fontSize: 12, color: DeckColors.mutedText),
                    ),
                    value: _enableLanFailover,
                    activeColor: DeckColors.primaryAccent,
                    onChanged: (val) =>
                        setState(() => _enableLanFailover = val),
                  ),
                  const Divider(color: DeckColors.borderSubtle, height: 1),
                  ListTile(
                    title: const Text(
                      'Connection timeout',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    subtitle: Text(
                      '$_timeoutSeconds seconds before failover',
                      style: const TextStyle(
                        fontSize: 12,
                        color: DeckColors.mutedText,
                      ),
                    ),
                    trailing: DropdownButton<int>(
                      value: _timeoutSeconds,
                      dropdownColor: DeckColors.surfaceElevated,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(
                          value: 3,
                          child: Text('3s', style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: 4,
                          child: Text('4s', style: TextStyle(fontSize: 13)),
                        ),
                        DropdownMenuItem(
                          value: 8,
                          child: Text('8s', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _timeoutSeconds = val);
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section 4: Connector API Authentication
            _buildSectionHeader('CONNECTOR AUTHENTICATION'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DeckColors.surfaceSecondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DeckColors.borderSubtle, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.vpn_key_outlined,
                        size: 18,
                        color: DeckColors.primaryAccent,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Pre-Shared Secret (PEER_SECRET)',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: DeckColors.primaryText,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Header token passed as X-Peer-Token to the Telegram Antigravity Connector API daemon on port 8765.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: DeckColors.secondaryText),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: DeckColors.borderSubtle, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Active Token',
                            style: TextStyle(
                              fontSize: 11,
                              color: DeckColors.mutedText,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            maskedToken,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: DeckColors.primaryText,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_connectorToken.isNotEmpty)
                            IconButton(
                              tooltip: 'Copy Connector Token',
                              icon: const Icon(
                                Icons.copy_rounded,
                                size: 16,
                                color: DeckColors.secondaryText,
                              ),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                Clipboard.setData(
                                  ClipboardData(text: _connectorToken),
                                );
                                ScaffoldMessenger.of(context)
                                  ..hideCurrentSnackBar()
                                  ..showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Connector PEER_SECRET copied to clipboard',
                                      ),
                                      duration: Duration(milliseconds: 1400),
                                    ),
                                  );
                              },
                            ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DeckColors.primaryAccent,
                              side: const BorderSide(
                                color: DeckColors.primaryAccent,
                              ),
                            ),
                            onPressed: _editConnectorTokenDialog,
                            icon: const Icon(Icons.edit, size: 14),
                            label: const Text('Edit'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section 5: Diagnostics & Application Logs
            _buildSectionHeader('DIAGNOSTICS & SYSTEM LOGS'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DeckColors.surfaceSecondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DeckColors.borderSubtle, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.history_edu_outlined,
                        size: 18,
                        color: DeckColors.informational,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Persistent App Logging',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: DeckColors.primaryText,
                            ),
                      ),
                      const Spacer(),
                      ValueListenableBuilder<int>(
                        valueListenable: AppLogger.instance.logCounter,
                        builder: (ctx, count, _) {
                          final errors = AppLogger.instance
                              .getRecentEntries(minLevel: LogLevel.warning)
                              .length;
                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: errors > 0
                                  ? DeckColors.error.withValues(alpha: 0.15)
                                  : DeckColors.healthy.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              errors > 0 ? '$errors ERRORS' : 'HEALTHY',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: errors > 0
                                    ? DeckColors.error
                                    : DeckColors.healthy,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Captures network socket probes, SSH execution results, HTTP requests, and unhandled errors into a persistent local log.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: DeckColors.secondaryText),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: DeckColors.borderSubtle, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: DeckColors.surfaceElevated,
                          foregroundColor: DeckColors.informational,
                        ),
                        onPressed: () => LogViewerSheet.show(context),
                        icon: const Icon(Icons.analytics_outlined, size: 16),
                        label: const Text('View App Logs'),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.copy,
                          size: 18,
                          color: DeckColors.secondaryText,
                        ),
                        tooltip: 'Copy ADB command',
                        onPressed: () {
                          Clipboard.setData(
                            const ClipboardData(
                              text: 'adb logcat -d -s LAPDECK:V',
                            ),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Copied "adb logcat -d -s LAPDECK:V" to clipboard',
                              ),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section 6: Security & Hardware Keystore
            _buildSectionHeader('SECURITY & CREDENTIALS'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: DeckColors.surfaceSecondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DeckColors.borderSubtle, width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.security,
                        size: 18,
                        color: DeckColors.healthy,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Android Keystore active',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: DeckColors.primaryText,
                            ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: DeckColors.healthy.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'HARDWARE BACKED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: DeckColors.healthy,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'SSH keys and authentication tokens are encrypted using hardware-backed Android Keystore primitives.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: DeckColors.secondaryText),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: DeckColors.borderSubtle, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Registered Identity',
                        style: TextStyle(
                          fontSize: 12,
                          color: DeckColors.mutedText,
                        ),
                      ),
                      Text(
                        'qwerky2003hush@gmail.com',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: DeckColors.primaryText,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section 7: About & Info
            _buildSectionHeader('APPLICATION'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: DeckColors.surfaceSecondary,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: DeckColors.borderSubtle, width: 1),
              ),
              child: Column(
                children: [
                  const ListTile(
                    title: Text(
                      'Version',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    trailing: Text(
                      'v${AppVersionInfo.currentVersion} (Build ${AppVersionInfo.currentBuildNumber})',
                      style:
                          TextStyle(fontSize: 12, color: DeckColors.mutedText),
                    ),
                  ),
                  const Divider(color: DeckColors.borderSubtle, height: 1),
                  ListTile(
                    title: const Text(
                      'Installed Commit SHA',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    onTap: () {
                      final fullSha = widget.storage.getInstalledCommitSha();
                      HapticFeedback.lightImpact();
                      Clipboard.setData(ClipboardData(text: fullSha));
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(
                          SnackBar(
                            content: Text('Copied commit SHA: $fullSha'),
                            duration: const Duration(milliseconds: 1400),
                          ),
                        );
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.storage.getInstalledCommitSha().length > 7
                              ? widget.storage
                                  .getInstalledCommitSha()
                                  .substring(0, 7)
                              : widget.storage.getInstalledCommitSha(),
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 12,
                            color: DeckColors.primaryAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: DeckColors.mutedText,
                        ),
                      ],
                    ),
                  ),
                  const Divider(color: DeckColors.borderSubtle, height: 1),
                  const ListTile(
                    title: Text(
                      'Architecture',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    trailing: Text(
                      'arm64-v8a • Android 16',
                      style:
                          TextStyle(fontSize: 12, color: DeckColors.mutedText),
                    ),
                  ),
                  const Divider(color: DeckColors.borderSubtle, height: 1),
                  ListTile(
                    title: const Text(
                      'Registered Author',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    trailing: Text(
                      'mochiron-desu',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: DeckColors.primaryAccent,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildOtaHotfixCard() {
    final installedSha = widget.storage.getInstalledCommitSha();
    final shortInstalled = installedSha.length > 7
        ? installedSha.substring(0, 7)
        : installedSha;
    final hasUpdate = _otaInfo?.state == OtaUpdateState.updateAvailable;
    final onlinePeers =
        widget.hosts.where((h) => h.peerStatus == PeerStatus.online).toList();
    final fallbackPeers =
        onlinePeers.isNotEmpty ? onlinePeers : widget.hosts.take(2).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasUpdate
              ? DeckColors.primaryAccent.withValues(alpha: 0.7)
              : DeckColors.borderSubtle,
          width: hasUpdate ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.system_update_alt,
                size: 18,
                color: DeckColors.primaryAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Peerless Git Hotfix Updater',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: DeckColors.primaryText,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (hasUpdate
                          ? DeckColors.primaryAccent
                          : DeckColors.healthy)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  hasUpdate ? 'HOTFIX READY' : shortInstalled,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: hasUpdate
                        ? DeckColors.primaryAccent
                        : DeckColors.healthy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Checks ${AppVersionInfo.githubRepoSlug} directly over HTTPS and installs the latest Git hotfix APK in-place without connecting to any peer.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: DeckColors.secondaryText),
          ),
          if (_otaInfo != null &&
              _otaInfo!.latestCommitSha != null &&
              _otaInfo!.latestCommitSha!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
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
                      Text(
                        'LATEST GIT COMMIT (${_otaInfo!.shortLatestSha})',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: DeckColors.primaryAccent,
                        ),
                      ),
                      const Spacer(),
                      if (_otaInfo!.formattedApkSize.isNotEmpty)
                        Text(
                          _otaInfo!.formattedApkSize,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: DeckColors.mutedText,
                          ),
                        ),
                    ],
                  ),
                  if (_otaInfo!.latestCommitMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _otaInfo!.latestCommitMessage!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DeckColors.primaryText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (_isInstallingOta) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: _otaProgress > 0 ? _otaProgress : null,
              color: DeckColors.primaryAccent,
              backgroundColor: DeckColors.background,
              minHeight: 4,
            ),
            const SizedBox(height: 6),
            Text(
              _otaStatusText,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 11,
                color: DeckColors.primaryAccent,
              ),
            ),
          ],
          if (_otaFeedbackMsg != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (_otaFeedbackOk ? DeckColors.healthy : DeckColors.error)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    _otaFeedbackOk
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 16,
                    color:
                        _otaFeedbackOk ? DeckColors.healthy : DeckColors.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _otaFeedbackMsg!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: DeckColors.primaryText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: DeckColors.surfaceElevated,
                  foregroundColor: DeckColors.primaryText,
                ),
                onPressed: _isCheckingOta || _isInstallingOta
                    ? null
                    : _handleCheckGitUpdates,
                icon: _isCheckingOta
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DeckColors.primaryAccent,
                        ),
                      )
                    : const Icon(
                        Icons.sync,
                        size: 16,
                        color: DeckColors.primaryAccent,
                      ),
                label: const Text('Check Git Updates'),
              ),
              if (_otaInfo != null && _otaInfo!.hasDirectApkAsset)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: DeckColors.primaryAccent,
                    foregroundColor: Colors.black,
                  ),
                  onPressed:
                      _isInstallingOta ? null : _handleDownloadGitHotfix,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text(
                    'Install Git Hotfix (${_otaInfo!.shortLatestSha})',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: DeckColors.secondaryText,
                  side: const BorderSide(color: DeckColors.borderSubtle),
                ),
                onPressed: _editGithubTokenDialog,
                icon: const Icon(Icons.key, size: 14),
                label: Text(
                  _githubToken.isNotEmpty ? 'GitHub PAT Set' : 'GitHub PAT',
                ),
              ),
            ],
          ),
          if (widget.sshService != null && fallbackPeers.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(color: DeckColors.borderSubtle, height: 1),
            const SizedBox(height: 10),
            Text(
              'FALLBACK: PULL GIT & BUILD VIA WORKSTATION PEER',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: DeckColors.mutedText,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: fallbackPeers.map((peer) {
                return OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DeckColors.informational,
                    side: const BorderSide(color: DeckColors.borderMedium),
                  ),
                  onPressed: _isInstallingOta
                      ? null
                      : () => _handleBuildViaPeer(peer),
                  icon: const Icon(Icons.build_circle_outlined, size: 15),
                  label: Text(
                    'Pull & Install via ${peer.name}',
                    style: const TextStyle(fontSize: 12),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotificationsCard() {
    return Container(
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                  color: DeckColors.primaryAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Android Notification Channels',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: DeckColors.primaryText,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: (_osNotifGranted
                            ? DeckColors.healthy
                            : DeckColors.warning)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _osNotifGranted ? 'GRANTED' : 'PERMISSION REQUIRED',
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: _osNotifGranted
                          ? DeckColors.healthy
                          : DeckColors.warning,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text(
              'Enable native notifications',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Master toggle for all LapDeck system notifications',
              style: TextStyle(fontSize: 12, color: DeckColors.mutedText),
            ),
            value: _notifSettings.masterEnabled,
            activeColor: DeckColors.primaryAccent,
            onChanged: (val) => _updateNotifSettings(
              _notifSettings.copyWith(masterEnabled: val),
            ),
          ),
          const Divider(color: DeckColors.borderSubtle, height: 1),
          SwitchListTile(
            title: const Text(
              'Peer online / offline transitions',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'Alert when workstations connect or drop off Tailscale/LAN',
              style: TextStyle(fontSize: 11, color: DeckColors.mutedText),
            ),
            value: _notifSettings.peerStatusTransitions,
            activeColor: DeckColors.primaryAccent,
            onChanged: !_notifSettings.masterEnabled
                ? null
                : (val) => _updateNotifSettings(
                      _notifSettings.copyWith(peerStatusTransitions: val),
                    ),
          ),
          const Divider(color: DeckColors.borderSubtle, height: 1),
          SwitchListTile(
            title: const Text(
              'Subsystem & Connector errors',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'Alert on SSH failures, command timeouts, or Connector daemon errors',
              style: TextStyle(fontSize: 11, color: DeckColors.mutedText),
            ),
            value: _notifSettings.subsystemAndConnectorErrors,
            activeColor: DeckColors.primaryAccent,
            onChanged: !_notifSettings.masterEnabled
                ? null
                : (val) => _updateNotifSettings(
                      _notifSettings.copyWith(
                        subsystemAndConnectorErrors: val,
                      ),
                    ),
          ),
          const Divider(color: DeckColors.borderSubtle, height: 1),
          SwitchListTile(
            title: const Text(
              'Lapdog security & session alerts',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'Alert on new pending Lapdog security events or Away mode changes',
              style: TextStyle(fontSize: 11, color: DeckColors.mutedText),
            ),
            value: _notifSettings.lapdogSecurityEvents,
            activeColor: DeckColors.primaryAccent,
            onChanged: !_notifSettings.masterEnabled
                ? null
                : (val) => _updateNotifSettings(
                      _notifSettings.copyWith(lapdogSecurityEvents: val),
                    ),
          ),
          const Divider(color: DeckColors.borderSubtle, height: 1),
          SwitchListTile(
            title: const Text(
              'AI turn completion alerts',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'Alert when an Antigravity AI prompt finishes or fails',
              style: TextStyle(fontSize: 11, color: DeckColors.mutedText),
            ),
            value: _notifSettings.aiTurnCompletion,
            activeColor: DeckColors.primaryAccent,
            onChanged: !_notifSettings.masterEnabled
                ? null
                : (val) => _updateNotifSettings(
                      _notifSettings.copyWith(aiTurnCompletion: val),
                    ),
          ),
          const Divider(color: DeckColors.borderSubtle, height: 1),
          SwitchListTile(
            title: const Text(
              'Git hotfix & update available',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            ),
            subtitle: const Text(
              'Alert when a new LapDeck Git commit / OTA APK build is published',
              style: TextStyle(fontSize: 11, color: DeckColors.mutedText),
            ),
            value: _notifSettings.otaUpdateAvailable,
            activeColor: DeckColors.primaryAccent,
            onChanged: !_notifSettings.masterEnabled
                ? null
                : (val) => _updateNotifSettings(
                      _notifSettings.copyWith(otaUpdateAvailable: val),
                    ),
          ),
          const Divider(color: DeckColors.borderSubtle, height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (!_osNotifGranted)
                  TextButton.icon(
                    onPressed: () async {
                      final granted = await (widget.notificationService
                              ?.requestPermission() ??
                          Future.value(false));
                      if (mounted) {
                        setState(() => _osNotifGranted = granted);
                      }
                    },
                    icon: const Icon(
                      Icons.security_update_good,
                      size: 16,
                      color: DeckColors.warning,
                    ),
                    label: const Text(
                      'Grant OS Permission',
                      style: TextStyle(
                        fontSize: 12,
                        color: DeckColors.warning,
                      ),
                    ),
                  )
                else
                  const SizedBox(),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: DeckColors.primaryAccent,
                    side: const BorderSide(color: DeckColors.primaryAccent),
                  ),
                  onPressed: () async {
                    final ok = await (widget.notificationService
                            ?.sendTestNotification() ??
                        Future.value(false));
                    final granted = await (widget.notificationService
                            ?.areNotificationsGranted() ??
                        Future.value(false));
                    if (mounted) {
                      setState(() => _osNotifGranted = granted);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Test notification dispatched to Android system tray'
                                : 'Notification blocked by OS permission settings',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.notifications_none, size: 16),
                  label: const Text('Send Test Notification'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontSize: 11,
            letterSpacing: 1.0,
            fontWeight: FontWeight.w700,
            color: DeckColors.mutedText,
          ),
    );
  }
}
