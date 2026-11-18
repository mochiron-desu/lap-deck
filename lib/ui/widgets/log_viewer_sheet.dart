import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/app_logger.dart';
import '../../theme/deck_theme.dart';

class LogViewerSheet extends StatefulWidget {
  const LogViewerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const LogViewerSheet(),
    );
  }

  @override
  State<LogViewerSheet> createState() => _LogViewerSheetState();
}

class _LogViewerSheetState extends State<LogViewerSheet> {
  String _selectedFilter = 'ALL';
  final ScrollController _scrollController = ScrollController();
  String? _logFilePath;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.getLogFilePath().then((path) {
      if (mounted) setState(() => _logFilePath = path);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<LogEntry> _getFilteredEntries() {
    return switch (_selectedFilter) {
      'ERRORS' => AppLogger.instance.getRecentEntries(minLevel: LogLevel.warning),
      'CONNECTOR' => AppLogger.instance.getRecentEntries(tagFilter: 'Connector'),
      'SSH' => AppLogger.instance.getRecentEntries(tagFilter: 'Ssh'),
      _ => AppLogger.instance.getRecentEntries(),
    };
  }

  Future<void> _copyAllLogs() async {
    final text = await AppLogger.instance.exportAllLogsText();
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied ${text.length} bytes of logs to clipboard'),
          backgroundColor: DeckColors.surfaceElevated,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _confirmClearLogs() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceElevated,
        title: const Text('Clear All Logs?', style: TextStyle(color: DeckColors.primaryText, fontSize: 16)),
        content: const Text(
          'This will purge both the in-memory log buffer and persistent storage.',
          style: TextStyle(color: DeckColors.secondaryText, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: DeckColors.mutedText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DeckColors.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await AppLogger.instance.clear();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: DeckColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: DeckColors.borderSubtle, width: 1)),
      ),
      child: ValueListenableBuilder<int>(
        valueListenable: AppLogger.instance.logCounter,
        builder: (context, _, __) {
          final entries = _getFilteredEntries();

          return Column(
            children: [
              // Sheet Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: DeckColors.healthy,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'SYSTEM & DIAGNOSTIC LOGS',
                      style: TextStyle(
                        color: DeckColors.primaryText,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 18, color: DeckColors.secondaryText),
                      tooltip: 'Copy all logs',
                      onPressed: _copyAllLogs,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined, size: 20, color: DeckColors.secondaryText),
                      tooltip: 'Clear logs',
                      onPressed: _confirmClearLogs,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: DeckColors.mutedText),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Filter Chips
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _buildFilterChip('ALL'),
                    const SizedBox(width: 8),
                    _buildFilterChip('ERRORS'),
                    const SizedBox(width: 8),
                    _buildFilterChip('CONNECTOR'),
                    const SizedBox(width: 8),
                    _buildFilterChip('SSH'),
                    const Spacer(),
                    Text(
                      '${entries.length} events',
                      style: const TextStyle(fontSize: 11, color: DeckColors.mutedText),
                    ),
                  ],
                ),
              ),
              const Divider(color: DeckColors.borderSubtle, height: 16),

              // Log Items Viewport
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Text(
                          'No logs recorded under $_selectedFilter filter',
                          style: const TextStyle(color: DeckColors.mutedText, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: entries.length,
                        itemBuilder: (context, index) {
                          final item = entries[index];
                          return _buildLogCard(item);
                        },
                      ),
              ),

              // Footer with ADB inspection path
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: DeckColors.surfaceSecondary,
                  border: Border(top: BorderSide(color: DeckColors.borderSubtle, width: 1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.terminal, size: 14, color: DeckColors.mutedText),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _logFilePath != null
                            ? 'cat $_logFilePath'
                            : 'adb logcat -s LAPDECK',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          color: DeckColors.mutedText,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: const Icon(Icons.copy, size: 14, color: DeckColors.mutedText),
                      tooltip: 'Copy ADB command',
                      onPressed: () {
                        Clipboard.setData(const ClipboardData(
                          text: 'adb logcat -d -s LAPDECK:V',
                        ));
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
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterChip(String label) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? DeckColors.primaryAccent.withValues(alpha: 0.18) : DeckColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? DeckColors.primaryAccent : DeckColors.borderSubtle,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? DeckColors.primaryAccent : DeckColors.secondaryText,
          ),
        ),
      ),
    );
  }

  Widget _buildLogCard(LogEntry entry) {
    final color = switch (entry.level) {
      LogLevel.error => DeckColors.error,
      LogLevel.warning => DeckColors.warning,
      LogLevel.info => DeckColors.healthy,
      LogLevel.debug => DeckColors.mutedText,
    };

    final timeStr = entry.timestamp.toIso8601String().substring(11, 23);

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: entry.level == LogLevel.error
              ? DeckColors.error.withValues(alpha: 0.3)
              : DeckColors.borderSubtle,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  entry.level.label,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                entry.tag,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: DeckColors.primaryText,
                ),
              ),
              const Spacer(),
              Text(
                timeStr,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  color: DeckColors.mutedText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            entry.message,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: DeckColors.secondaryText,
              height: 1.3,
            ),
          ),
          if (entry.error != null) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: DeckColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                entry.error!,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  color: DeckColors.error,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
