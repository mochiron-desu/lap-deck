import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/deck_theme.dart';
import '../../models/command_action.dart';

class QuickActionPad extends StatelessWidget {
  final List<CommandAction> actions;
  final String? runningActionId;
  final Function(CommandAction) onTriggerAction;
  final Function(String customCommand) onRunCustomCommand;

  const QuickActionPad({
    super.key,
    required this.actions,
    required this.runningActionId,
    required this.onTriggerAction,
    required this.onRunCustomCommand,
  });

  @override
  Widget build(BuildContext context) {
    final systemActions = actions.where((a) => a.category == ActionCategory.system).toList();
    final securityActions = actions.where((a) => a.category == ActionCategory.security).toList();
    final otherActions = actions.where((a) => a.category != ActionCategory.system && a.category != ActionCategory.security).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category 1: Security & Lap-Dog Agent
        _buildCategorySection(
          context,
          title: 'LAPDOG SECURITY CONTROLS',
          actions: securityActions,
        ),
        const SizedBox(height: 12),
        // Category 2: System Telemetry
        _buildCategorySection(
          context,
          title: 'HOST DIAGNOSTICS & TELEMETRY',
          actions: systemActions,
        ),
        const SizedBox(height: 12),
        // Category 3: Power & Network
        _buildCategorySection(
          context,
          title: 'MESH & SESSION CONTROLS',
          actions: otherActions,
        ),
      ],
    );
  }

  Widget _buildCategorySection(
    BuildContext context, {
    required String title,
    required List<CommandAction> actions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: DeckColors.textMid,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.5,
            ),
            itemCount: actions.length,
            itemBuilder: (context, index) {
              final action = actions[index];
              final isRunning = runningActionId == action.id;
              return _ActionButton(
                action: action,
                isRunning: isRunning,
                onTap: () {
                  HapticFeedback.mediumImpact();
                  onTriggerAction(action);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final CommandAction action;
  final bool isRunning;
  final VoidCallback onTap;

  const _ActionButton({
    required this.action,
    required this.isRunning,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isRunning ? null : onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: DeckColors.surfaceRack,
            border: Border.all(
              color: action.isDestructive
                  ? DeckColors.alertCrimson.withValues(alpha: 0.5)
                  : DeckColors.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: (action.isDestructive
                          ? DeckColors.alertCrimson
                          : DeckColors.accentOrange)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: isRunning
                    ? const Padding(
                        padding: EdgeInsets.all(6.0),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: DeckColors.accentOrange,
                        ),
                      )
                    : Icon(
                        action.icon,
                        size: 14,
                        color: action.isDestructive
                            ? DeckColors.alertCrimson
                            : DeckColors.accentOrange,
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: action.isDestructive
                            ? DeckColors.alertCrimson
                            : DeckColors.textHigh,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.description,
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
            ],
          ),
        ),
      ),
    );
  }
}
