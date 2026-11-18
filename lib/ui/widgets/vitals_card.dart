import 'package:flutter/material.dart';
import '../../theme/deck_theme.dart';
import '../../models/vitals_data.dart';

class VitalsCard extends StatelessWidget {
  final VitalsData vitals;
  final bool isLoading;
  final VoidCallback onRefresh;

  const VitalsCard({
    super.key,
    required this.vitals,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with graceful overflow protection
          Row(
            children: [
              const Icon(Icons.speed, size: 18, color: DeckColors.primaryAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'System vitals',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: DeckColors.primaryText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: isLoading ? null : onRefresh,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: DeckColors.surfaceElevated,
                    border: Border.all(color: DeckColors.borderSubtle, width: 1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoading)
                        const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: DeckColors.primaryAccent,
                          ),
                        )
                      else
                        const Icon(Icons.refresh, size: 12, color: DeckColors.secondaryText),
                      const SizedBox(width: 4),
                      Text(
                        isLoading ? 'Syncing' : 'Refresh',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isLoading ? DeckColors.primaryAccent : DeckColors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Metric 1: CPU Utilization
          _buildMeterRow(
            context,
            label: 'CPU Utilization',
            detail: '${(vitals.cpuPercent * 100).toStringAsFixed(1)}% • Load ${vitals.loadAvg}',
            percent: vitals.cpuPercent,
            barColor: vitals.cpuPercent > 0.8 ? DeckColors.error : DeckColors.primaryAccent,
          ),
          const SizedBox(height: 12),

          // Metric 2: Memory (RAM)
          _buildMeterRow(
            context,
            label: 'Memory (RAM)',
            detail: vitals.ramUsage,
            percent: vitals.ramPercent,
            barColor: vitals.ramPercent > 0.85 ? DeckColors.warning : DeckColors.healthy,
          ),
          const SizedBox(height: 12),

          // Metric 3: Root Storage
          _buildMeterRow(
            context,
            label: 'Root Storage',
            detail: vitals.diskUsage,
            percent: vitals.diskPercent,
            barColor: DeckColors.informational,
          ),
          const Divider(color: DeckColors.borderSubtle, height: 24),

          // Uptime & Status Footnote
          Row(
            children: [
              const Icon(Icons.schedule, size: 14, color: DeckColors.mutedText),
              const SizedBox(width: 6),
              Text(
                'Uptime: ',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: DeckColors.mutedText,
                ),
              ),
              Expanded(
                child: Text(
                  vitals.isVerified ? vitals.uptime : 'Telemetry not verified',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: vitals.isVerified ? DeckColors.primaryText : DeckColors.mutedText,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (vitals.isVerified)
                Text(
                  '${vitals.timestamp.hour.toString().padLeft(2, '0')}:${vitals.timestamp.minute.toString().padLeft(2, '0')}:${vitals.timestamp.second.toString().padLeft(2, '0')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: DeckColors.mutedText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMeterRow(
    BuildContext context, {
    required String label,
    required String detail,
    required double percent,
    required Color barColor,
  }) {
    final clamped = percent.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: DeckColors.secondaryText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                detail,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: DeckColors.primaryText,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: clamped,
            backgroundColor: DeckColors.surfaceElevated,
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}
