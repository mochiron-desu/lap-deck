import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';

class QuickControlsCard extends StatelessWidget {
  final HostTarget? host;
  final bool isExecuting;
  final String? executingLabel;
  final Function(String actionId, String label, String command) onTrigger;

  const QuickControlsCard({
    super.key,
    this.host,
    required this.isExecuting,
    required this.executingLabel,
    required this.onTrigger,
  });

  @override
  Widget build(BuildContext context) {
    final targetName = host?.name ?? 'workstation';
    final lockTitle = host?.lockActionTitle ?? 'Lock Session';
    final lockCmd =
        host?.lockSessionCommand ?? HostTarget.defaultHosts.first.lockSessionCommand;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.touch_app,
                size: 18,
                color: DeckColors.primaryAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Device controls · $targetName',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: DeckColors.primaryText,
                      ),
                ),
              ),
              if (isExecuting) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: DeckColors.primaryAccent,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  executingLabel ?? 'In progress...',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: DeckColors.primaryAccent,
                      ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Action Grid (normalized equal dimensions)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildControlButton(
                    context,
                    icon: Icons.lock_outline,
                    label: lockTitle,
                    subtitle: 'Lock $targetName',
                    color: DeckColors.primaryAccent,
                    onTap: () => _confirmAction(
                      context,
                      title: '$lockTitle on $targetName?',
                      message: host?.lockConsequenceDescription ??
                          'Locks the active graphical user session on $targetName.',
                      confirmLabel: 'Lock $targetName',
                      confirmColor: DeckColors.primaryAccent,
                      onConfirm: () => onTrigger(
                        'lock-screen',
                        lockTitle,
                        lockCmd,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildControlButton(
                    context,
                    icon: Icons.restart_alt,
                    label: 'Restart Lapdog',
                    subtitle: 'Reset daemon on $targetName',
                    color: DeckColors.warning,
                    onTap: () => onTrigger(
                      'restart-lapdog',
                      'Restart Lapdog',
                      host?.os == HostOs.windows
                          ? 'if (Get-Command lapdog -ErrorAction SilentlyContinue) { lapdog restart } else { Write-Error "Lapdog is not installed on Windows."; exit 127 }'
                          : 'systemctl --user restart lapdog 2>/dev/null || lapdog restart 2>/dev/null',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _buildControlButton(
                    context,
                    icon: Icons.sync,
                    label: 'Sync Skills',
                    subtitle: 'Sync mesh on $targetName',
                    color: DeckColors.informational,
                    onTap: () => onTrigger(
                      'sync-skills',
                      'Sync Skills',
                      host?.os == HostOs.windows
                          ? 'python -m antigravity_sync 2>\$null; exit 0'
                          : 'python3 -m antigravity_sync 2>/dev/null || true',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _buildControlButton(
                    context,
                    icon: Icons.power_settings_new,
                    label: 'Sleep Device',
                    subtitle: 'Suspend $targetName',
                    color: DeckColors.error,
                    onTap: () => _confirmAction(
                      context,
                      title: 'Suspend $targetName?',
                      message:
                          'Puts $targetName (${host?.tailscaleIp ?? ""}) into system sleep mode. Physical wake or Wake-on-LAN will be required to reconnect.',
                      confirmLabel: 'Suspend $targetName',
                      confirmColor: DeckColors.error,
                      onConfirm: () => onTrigger(
                        'sleep-rig',
                        'Sleep Device',
                        host?.sleepDeviceCommand ??
                            'systemctl suspend 2>/dev/null || rundll32.exe powrprof.dll,SetSuspendState 0,1,0',
                      ),
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

  Widget _buildControlButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: DeckColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: isExecuting
            ? null
            : () {
                HapticFeedback.mediumImpact();
                onTap();
              },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(color: DeckColors.borderSubtle, width: 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(icon, size: 16, color: color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: DeckColors.primaryText,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: DeckColors.secondaryText,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceSecondary,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: DeckColors.borderMedium, width: 1),
          borderRadius: BorderRadius.circular(14),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        content: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: DeckColors.background,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}
