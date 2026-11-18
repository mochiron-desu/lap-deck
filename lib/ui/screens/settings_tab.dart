import 'package:flutter/material.dart';
import '../../theme/deck_theme.dart';
import '../../services/storage_service.dart';

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

  @override
  Widget build(BuildContext context) {
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

            // Section 2: Security & Hardware Keystore
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

            // Section 3: About & Info
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
                    trailing: Text('v1.1.0 (Build 36)', style: TextStyle(fontSize: 12, color: DeckColors.mutedText)),
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
