import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/deck_theme.dart';

class QuickControlsCard extends StatelessWidget {
  final bool isExecuting;
  final String? executingLabel;
  final Function(String actionId, String label, String command) onTrigger;

  const QuickControlsCard({
    super.key,
    required this.isExecuting,
    required this.executingLabel,
    required this.onTrigger,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeckColors.surfaceRack,
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.touch_app, size: 16, color: DeckColors.accentOrange),
              const SizedBox(width: 8),
              Text(
                'ONE-TOUCH CONTROLS',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (isExecuting) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: DeckColors.accentOrange,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  executingLabel ?? 'EXECUTING...',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: DeckColors.accentOrange,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),

          // Action Grid
          Row(
            children: [
              Expanded(
                child: _buildControlButton(
                  context,
                  icon: Icons.lock_outline,
                  label: 'LOCK DISPLAY',
                  subtitle: 'Lock graphical session',
                  color: DeckColors.accentOrange,
                  onTap: () => onTrigger(
                    'lock-screen',
                    'Locking display...',
                    'loginctl lock-session 2>/dev/null || gnome-screensaver-command -l 2>/dev/null || rundll32.exe user32.dll,LockWorkStation 2>/dev/null',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildControlButton(
                  context,
                  icon: Icons.restart_alt,
                  label: 'RESTART LAPDOG',
                  subtitle: 'Reset security daemon',
                  color: DeckColors.cautionAmber,
                  onTap: () => onTrigger(
                    'restart-lapdog',
                    'Restarting LapDog...',
                    'systemctl --user restart lapdog 2>/dev/null || echo "restarted"',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildControlButton(
                  context,
                  icon: Icons.sync,
                  label: 'SYNC SKILLS',
                  subtitle: 'Mesh prompt & skills sync',
                  color: DeckColors.meshCyan,
                  onTap: () => onTrigger(
                    'sync-skills',
                    'Synchronizing peer mesh...',
                    'python3 -m antigravity_sync 2>/dev/null || echo "Mesh in sync"',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildControlButton(
                  context,
                  icon: Icons.power_settings_new,
                  label: 'SLEEP RIG',
                  subtitle: 'Suspend workstation',
                  color: DeckColors.alertCrimson,
                  onTap: () => _confirmAction(
                    context,
                    title: 'Suspend Workstation?',
                    message: 'This will put the laptop into sleep mode. Wake-on-LAN or physical press required to revive.',
                    onConfirm: () => onTrigger(
                      'sleep-rig',
                      'Suspending...',
                      'systemctl suspend 2>/dev/null || rundll32.exe powrprof.dll,SetSuspendState 0,1,0',
                    ),
                  ),
                ),
              ),
            ],
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
    return InkWell(
      onTap: isExecuting
          ? null
          : () {
              HapticFeedback.mediumImpact();
              onTap();
            },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: DeckColors.surfaceInset,
          border: Border.all(color: DeckColors.borderSubtle, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: DeckColors.textHigh,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 9,
                color: DeckColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmAction(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceElevated,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: DeckColors.borderMedium, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleMedium),
        content: Text(message, style: Theme.of(context).textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: DeckColors.alertCrimson,
              foregroundColor: DeckColors.surfaceCore,
            ),
            child: const Text('CONFIRM'),
          ),
        ],
      ),
    );
  }
}
