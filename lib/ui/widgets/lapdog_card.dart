import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/deck_theme.dart';
import '../../models/vitals_data.dart';

class LapdogCard extends StatelessWidget {
  final LapdogStatus status;
  final bool isToggling;
  final Function(bool enableAway) onToggleAway;

  const LapdogCard({
    super.key,
    required this.status,
    required this.isToggling,
    required this.onToggleAway,
  });

  @override
  Widget build(BuildContext context) {
    final isArmed = status.isAwayArmed;
    final stateColor = isArmed ? DeckColors.cautionAmber : DeckColors.phosphorGreen;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeckColors.surfaceRack,
        border: Border.all(
          color: isArmed ? DeckColors.cautionAmber.withValues(alpha: 0.5) : DeckColors.borderSubtle,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Title and State Badge
          Row(
            children: [
              Icon(
                isArmed ? Icons.shield : Icons.verified_user,
                size: 18,
                color: stateColor,
              ),
              const SizedBox(width: 8),
              Text(
                'LAP-DOG SECURITY AGENT',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.12),
                  border: Border.all(color: stateColor.withValues(alpha: 0.4), width: 1),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  isArmed ? 'AWAY ARMED' : 'HOME MODE',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: stateColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            isArmed
                ? 'Away mode is active. Lap-Dog captures webcam photos on failed login attempts and dispatches instant Telegram alerts.'
                : 'Laptop is in normal mode. Non-critical login alerts are suppressed while you work.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 12,
              color: DeckColors.textMid,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),

          // Tactile Switch Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: DeckColors.surfaceInset,
              border: Border.all(color: DeckColors.borderSubtle, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AWAY MODE MONITORING',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: DeckColors.textHigh,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isArmed ? 'Watchdog active' : 'Watchdog disarmed',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: DeckColors.textMuted,
                      ),
                    ),
                  ],
                ),
                if (isToggling)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DeckColors.accentOrange,
                    ),
                  )
                else
                  Switch(
                    value: isArmed,
                    activeColor: DeckColors.cautionAmber,
                    inactiveThumbColor: DeckColors.textMuted,
                    inactiveTrackColor: DeckColors.surfaceRack,
                    onChanged: (val) {
                      HapticFeedback.heavyImpact();
                      onToggleAway(val);
                    },
                  ),
              ],
            ),
          ),
          if (status.sentHistory > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'AUDIT METRICS: ',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10, color: DeckColors.textMuted),
                ),
                Text(
                  '${status.sentHistory} events recorded',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: DeckColors.textMid,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
