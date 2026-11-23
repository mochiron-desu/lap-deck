import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
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

  void _confirmKillProcess(BuildContext context, ProcessItem proc) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: DeckColors.borderMedium),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: DeckColors.error,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Terminate ${proc.name}?',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: DeckColors.primaryText,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          'Forcefully terminate process "${proc.name}" (PID ${proc.pid}, user ${proc.user})? Unsaved state in this process will be lost.',
          style: const TextStyle(
            fontSize: 13,
            color: DeckColors.secondaryText,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: DeckColors.mutedText),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DeckColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              HapticFeedback.heavyImpact();
              onKillProcess(proc);
            },
            child: Text('Kill PID ${proc.pid}'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          // Header Row
          Row(
            children: [
              const Icon(
                Icons.memory,
                size: 18,
                color: DeckColors.primaryAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Active processes',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: DeckColors.primaryText,
                      ),
                ),
              ),
              InkWell(
                onTap: isLoading ? null : onRefresh,
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(6.0),
                  child: Icon(
                    Icons.refresh,
                    size: 16,
                    color: DeckColors.secondaryText,
                  ),
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
                  color: DeckColors.primaryAccent,
                ),
              ),
            )
          else if (processes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'No active background tasks detected or host unreachable.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: DeckColors.mutedText),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: processes.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: DeckColors.borderSubtle, height: 14),
              itemBuilder: (context, index) {
                final proc = processes[index];
                return Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: DeckColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border:
                            Border.all(color: DeckColors.borderSubtle, width: 1),
                      ),
                      child: const Icon(
                        Icons.code,
                        size: 14,
                        color: DeckColors.secondaryText,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Clipboard.setData(
                            ClipboardData(text: proc.pid.toString()),
                          );
                          ScaffoldMessenger.of(context)
                            ..hideCurrentSnackBar()
                            ..showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Copied PID ${proc.pid} (${proc.name})',
                                ),
                                duration: const Duration(milliseconds: 1200),
                              ),
                            );
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              proc.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: DeckColors.primaryText,
                              ),
                            ),
                            Text(
                              'PID ${proc.pid} · ${proc.user}${proc.memPercent > 0 ? " · ${proc.memPercent.toStringAsFixed(1)}% RAM" : ""}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                color: DeckColors.mutedText,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // CPU Pill
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: DeckColors.background,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: DeckColors.borderSubtle),
                      ),
                      child: Text(
                        '${proc.cpuPercent.toStringAsFixed(1)}% CPU',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: proc.cpuPercent > 50
                              ? DeckColors.error
                              : (proc.cpuPercent > 25
                                  ? DeckColors.warning
                                  : DeckColors.secondaryText),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Tier 3 Destructive End Task Action (with confirmation dialog)
                    InkWell(
                      onTap: () => _confirmKillProcess(context, proc),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: DeckColors.error.withValues(alpha: 0.12),
                          border: Border.all(
                            color: DeckColors.error.withValues(alpha: 0.4),
                            width: 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'KILL',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: DeckColors.error,
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
