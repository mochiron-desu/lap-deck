import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_logger.dart';
import '../../services/storage_service.dart';
import '../../theme/deck_theme.dart';
import '../widgets/log_viewer_sheet.dart';

class SettingsTab extends StatefulWidget {
  final StorageService storage;

  const SettingsTab({
    super.key,
    required this.storage,
  });

  @override
  State<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<SettingsTab> {
  bool _enableLanFailover = true;
  int _timeoutSeconds = 4;
  String _connectorToken = '';

  @override
  void initState() {
    super.initState();
    _loadConnectorToken();
  }

  Future<void> _loadConnectorToken() async {
    final token = await widget.storage.getConnectorToken();
    if (mounted) setState(() => _connectorToken = token);
  }

  Future<void> _editConnectorTokenDialog() async {
    final controller = TextEditingController(text: _connectorToken);
    final updated = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceElevated,
        title: const Text('Connector API Secret', style: TextStyle(color: DeckColors.primaryText, fontSize: 16)),
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
              style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: DeckColors.primaryText),
              decoration: InputDecoration(
                labelText: 'X-Peer-Token / Secret',
                labelStyle: const TextStyle(color: DeckColors.mutedText),
                filled: true,
                fillColor: DeckColors.surfaceSecondary,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                controller.text = StorageService.defaultConnectorSecret;
              },
              child: const Text('Reset to Default Secret', style: TextStyle(fontSize: 12, color: DeckColors.primaryAccent)),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: DeckColors.mutedText)),
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
      await _loadConnectorToken();
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
            // Section 1: Network & Connection
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
                    title: const Text('Direct LAN failover', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: const Text(
                      'Automatically connect via local 192.168.29.x if Tailscale drops',
                      style: TextStyle(fontSize: 12, color: DeckColors.mutedText),
                    ),
                    value: _enableLanFailover,
                    activeColor: DeckColors.primaryAccent,
                    onChanged: (val) => setState(() => _enableLanFailover = val),
                  ),
                  const Divider(color: DeckColors.borderSubtle, height: 1),
                  ListTile(
                    title: const Text('Connection timeout', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    subtitle: Text(
                      '$_timeoutSeconds seconds before failover',
                      style: const TextStyle(fontSize: 12, color: DeckColors.mutedText),
                    ),
                    trailing: DropdownButton<int>(
                      value: _timeoutSeconds,
                      dropdownColor: DeckColors.surfaceElevated,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 3, child: Text('3s', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 4, child: Text('4s', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 8, child: Text('8s', style: TextStyle(fontSize: 13))),
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

            // Section 2: Connector API Authentication
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
                      const Icon(Icons.vpn_key_outlined, size: 18, color: DeckColors.primaryAccent),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeckColors.secondaryText),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: DeckColors.borderSubtle, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Active Token', style: TextStyle(fontSize: 11, color: DeckColors.mutedText)),
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
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: DeckColors.primaryAccent,
                          side: const BorderSide(color: DeckColors.primaryAccent),
                        ),
                        onPressed: _editConnectorTokenDialog,
                        icon: const Icon(Icons.edit, size: 14),
                        label: const Text('Edit'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Section 3: Diagnostics & Application Logs
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
                      const Icon(Icons.history_edu_outlined, size: 18, color: DeckColors.informational),
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
                          final errors = AppLogger.instance.getRecentEntries(minLevel: LogLevel.warning).length;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                                color: errors > 0 ? DeckColors.error : DeckColors.healthy,
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeckColors.secondaryText),
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
                        icon: const Icon(Icons.copy, size: 18, color: DeckColors.secondaryText),
                        tooltip: 'Copy ADB command',
                        onPressed: () {
                          Clipboard.setData(const ClipboardData(text: 'adb logcat -d -s LAPDECK:V'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Copied "adb logcat -d -s LAPDECK:V" to clipboard'),
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

            // Section 4: Security & Hardware Keystore
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
                      const Icon(Icons.security, size: 18, color: DeckColors.healthy),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: DeckColors.healthy.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'HARDWARE BACKED',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: DeckColors.healthy),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'SSH keys and authentication tokens are encrypted using hardware-backed Android Keystore primitives.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeckColors.secondaryText),
                  ),
                  const SizedBox(height: 12),
                  const Divider(color: DeckColors.borderSubtle, height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Registered Identity', style: TextStyle(fontSize: 12, color: DeckColors.mutedText)),
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

            // Section 5: About & Info
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
                    title: Text('Version', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    trailing: Text('v1.2.0 (Build 37)', style: TextStyle(fontSize: 12, color: DeckColors.mutedText)),
                  ),
                  const Divider(color: DeckColors.borderSubtle, height: 1),
                  const ListTile(
                    title: Text('Architecture', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                    trailing: Text('arm64-v8a • Android 16', style: TextStyle(fontSize: 12, color: DeckColors.mutedText)),
                  ),
                  const Divider(color: DeckColors.borderSubtle, height: 1),
                  ListTile(
                    title: const Text('Registered Author', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
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

