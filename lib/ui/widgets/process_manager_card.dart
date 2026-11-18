import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/deck_theme.dart';
import '../../models/vitals_data.dart';

class ProcessManagerCard extends StatelessWidget {
  final List<ProcessItem> processes;
  final bool isLoading;
  final Function(ProcessItem process) onKillProcess;
  final VoidCallback onRefresh;

  const ProcessManagerCard({
    super.key,
    required this.processes,
    required this.isLoading,
    required this.onKillProcess,
    required this.onRefresh,
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
          // Header Row
          Row(
            children: [
              const Icon(Icons.memory, size: 16, color: DeckColors.accentOrange),
              const SizedBox(width: 8),
              Text(
                'ACTIVE WORKSPACE PROCESSES',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: isLoading ? null : onRefresh,
                child: const Padding(
                  padding: EdgeInsets.all(4.0),
                  child: Icon(Icons.refresh, size: 14, color: DeckColors.textMid),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          if (isLoading && processes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: DeckColors.accentOrange,
                ),
              ),
            )
          else if (processes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'No active background tasks detected or host unreachable.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeckColors.textMuted),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: processes.length,
              separatorBuilder: (_, __) => const Divider(color: DeckColors.borderSubtle, height: 12),
              itemBuilder: (context, index) {
                final proc = processes[index];
                return Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: DeckColors.surfaceInset,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: DeckColors.borderSubtle, width: 1),
                      ),
                      child: const Icon(Icons.code, size: 12, color: DeckColors.textMid),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            proc.name,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: DeckColors.textHigh,
                            ),
                          ),
                          Text(
                            'PID: ${proc.pid} • User: ${proc.user}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 9,
                              color: DeckColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // CPU & MEM Pills
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: DeckColors.surfaceInset,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        '${proc.cpuPercent.toStringAsFixed(1)}% CPU',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: proc.cpuPercent > 30 ? DeckColors.alertCrimson : DeckColors.textMid,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // End Task Action
                    InkWell(
                      onTap: () {
                        HapticFeedback.heavyImpact();
                        onKillProcess(proc);
                      },
                      borderRadius: BorderRadius.circular(3),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: DeckColors.alertCrimson.withValues(alpha: 0.12),
                          border: Border.all(color: DeckColors.alertCrimson.withValues(alpha: 0.4), width: 1),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'KILL',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: DeckColors.alertCrimson,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
