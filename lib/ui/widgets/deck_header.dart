import 'package:flutter/material.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';

class DeckHeader extends StatelessWidget {
  final HostTarget? activeHost;
  final bool isMeshActive;
  final VoidCallback onRefresh;
  final VoidCallback onAddHost;

  const DeckHeader({
    super.key,
    required this.activeHost,
    this.isMeshActive = true,
    required this.onRefresh,
    required this.onAddHost,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: DeckColors.surfaceRack,
        border: Border(
          bottom: BorderSide(color: DeckColors.borderSubtle, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            // Status LED & Logo / Deck Title
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isMeshActive ? DeckColors.phosphorGreen : DeckColors.cautionAmber,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (isMeshActive ? DeckColors.phosphorGreen : DeckColors.cautionAmber).withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'LAPDECK',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: DeckColors.surfaceInset,
                        border: Border.all(color: DeckColors.borderSubtle, width: 1),
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        'v1.0.0',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: DeckColors.accentOrange,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      'MESH: ',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                    ),
                    Text(
                      isMeshActive ? 'TAILSCALE ENCRYPTED' : 'OFFLINE',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 10,
                        color: isMeshActive ? DeckColors.meshCyan : DeckColors.alertCrimson,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (activeHost?.pingMs != null) ...[
                      Text(
                        ' • ',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 10),
                      ),
                      Text(
                        '${activeHost!.pingMs}ms',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: DeckColors.phosphorGreen,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            const Spacer(),
            // Host Rack Management Actions
            _HeaderIconButton(
              icon: Icons.refresh,
              tooltip: 'Ping & Refresh Mesh',
              onPressed: onRefresh,
            ),
            const SizedBox(width: 8),
            _HeaderIconButton(
              icon: Icons.add,
              tooltip: 'Add Peer Laptop',
              onPressed: onAddHost,
              isAccent: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool isAccent;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.isAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: isAccent ? DeckColors.accentOrange.withValues(alpha: 0.12) : DeckColors.surfaceInset,
            border: Border.all(
              color: isAccent ? DeckColors.accentOrange : DeckColors.borderSubtle,
              width: 1,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            icon,
            size: 16,
            color: isAccent ? DeckColors.accentOrange : DeckColors.textHigh,
          ),
        ),
      ),
    );
  }
}
