import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../theme/deck_theme.dart';
import '../../models/vitals_data.dart';

class LapdogCard extends StatelessWidget {
  final String? hostName;
  final LapdogStatus status;
  final bool isToggling;
  final Function(bool enableAway) onToggleAway;

  const LapdogCard({
    super.key,
    this.hostName,
    required this.status,
    required this.isToggling,
    required this.onToggleAway,
  });

  @override
  Widget build(BuildContext context) {
    final isInstalled = status.isInstalled;
    final isArmed = isInstalled && status.isAwayArmed;
    final Color stateColor = !status.isVerified
        ? DeckColors.mutedText
        : (!isInstalled
            ? DeckColors.mutedText
            : (isArmed ? DeckColors.warning : DeckColors.healthy));

    final String stateBadge = !status.isVerified
        ? 'UNVERIFIED'
        : (!isInstalled
            ? 'UNAVAILABLE'
            : (isArmed ? 'AWAY ARMED' : 'HOME MODE'));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        border: Border.all(
          color: DeckColors.borderSubtle,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with Title and State Badge
          Row(
            children: [
              Icon(
                isArmed ? Icons.shield : Icons.verified_user_outlined,
                size: 18,
                color: stateColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hostName != null
                      ? 'Lapdog security · $hostName'
                      : 'Lapdog security',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: stateColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  stateBadge,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: stateColor,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            !isInstalled
                ? 'Lapdog daemon was not detected on ${hostName ?? "this device"}.'
                : (isArmed
                    ? 'Away mode is active on ${hostName ?? "this device"}. Webcam capture and Telegram alerts are enabled on failed authentication attempts.'
                    : 'Normal Home mode on ${hostName ?? "this device"}. Non-critical login alerts are suppressed.'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DeckColors.secondaryText,
                  height: 1.4,
                ),
          ),
          const SizedBox(height: 14),

          // Tactile Switch Row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: DeckColors.background,
              border: Border.all(color: DeckColors.borderSubtle, width: 1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Away mode monitoring${hostName != null ? " ($hostName)" : ""}',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: DeckColors.primaryText,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        !isInstalled
                            ? 'Daemon unavailable'
                            : (isArmed ? 'Watchdog armed' : 'Watchdog disarmed'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: DeckColors.mutedText,
                            ),
                      ),
                    ],
                  ),
                ),
                if (isToggling)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DeckColors.primaryAccent,
                    ),
                  )
                else
                  Switch(
                    value: isArmed,
                    activeColor: DeckColors.warning,
                    inactiveThumbColor: DeckColors.mutedText,
                    inactiveTrackColor: DeckColors.surfaceSecondary,
                    onChanged: !isInstalled
                        ? null
                        : (val) {
                            HapticFeedback.heavyImpact();
                            onToggleAway(val);
                          },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${status.sentHistory} events recorded · ${status.pendingEvents} pending',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: DeckColors.secondaryText,
                    ),
              ),
              if (status.lastChecked != null)
                Text(
                  'Checked ${DateFormat('HH:mm:ss').format(status.lastChecked!)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: DeckColors.mutedText,
                      ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
