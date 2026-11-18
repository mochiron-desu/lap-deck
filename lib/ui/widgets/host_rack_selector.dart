import 'package:flutter/material.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';

class HostRackSelector extends StatelessWidget {
  final List<HostTarget> hosts;
  final HostTarget? activeHost;
  final Function(HostTarget) onSelectHost;
  final Function(HostTarget) onEditHost;

  const HostRackSelector({
    super.key,
    required this.hosts,
    required this.activeHost,
    required this.onSelectHost,
    required this.onEditHost,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'PEER HOST RACK [${hosts.length} NODES]',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  color: DeckColors.textMid,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'TARGET: ${activeHost?.name.toUpperCase() ?? "NONE"}',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: DeckColors.accentOrange,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: hosts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final host = hosts[index];
            final isSelected = host.id == activeHost?.id;
            return _HostRackCard(
              host: host,
              isSelected: isSelected,
              onTap: () => onSelectHost(host),
              onEdit: () => onEditHost(host),
            );
          },
        ),
      ],
    );
  }
}

class _HostRackCard extends StatelessWidget {
  final HostTarget host;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  const _HostRackCard({
    required this.host,
    required this.isSelected,
    required this.onTap,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final osColor = switch (host.os) {
      HostOs.linux => DeckColors.phosphorGreen,
      HostOs.windows => DeckColors.meshCyan,
      HostOs.macos => DeckColors.cautionAmber,
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? DeckColors.surfaceElevated : DeckColors.surfaceRack,
          border: Border.all(
            color: isSelected ? DeckColors.borderActive : DeckColors.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: IntrinsicHeight(
          child: Row(
            children: [
              // Left Accent Notch indicating active target
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: isSelected ? DeckColors.accentOrange : Colors.transparent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(3),
                    bottomLeft: Radius.circular(3),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Machine Name, OS Badge, Online status
                      Row(
                        children: [
                          Icon(
                            switch (host.os) {
                              HostOs.linux => Icons.terminal,
                              HostOs.windows => Icons.window,
                              HostOs.macos => Icons.laptop_mac,
                            },
                            size: 14,
                            color: isSelected ? DeckColors.accentOrange : DeckColors.textMid,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            host.name,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              letterSpacing: 0.8,
                              color: isSelected ? DeckColors.textHigh : DeckColors.textMid,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // OS Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: osColor.withValues(alpha: 0.12),
                              border: Border.all(color: osColor.withValues(alpha: 0.4), width: 1),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              host.os.name.toUpperCase(),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontSize: 9,
                                color: osColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const Spacer(),
                          // Latency / Status
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: host.isOnline ? DeckColors.phosphorGreen : DeckColors.offlineSteel,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            host.isOnline ? '${host.pingMs ?? 1}ms' : 'OFFLINE',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontSize: 10,
                              color: host.isOnline ? DeckColors.phosphorGreen : DeckColors.offlineSteel,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Edit button
                          InkWell(
                            onTap: onEdit,
                            child: const Padding(
                              padding: EdgeInsets.all(2.0),
                              child: Icon(Icons.tune, size: 14, color: DeckColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // IP & Route Row
                      Row(
                        children: [
                          Text(
                            'TS IP: ',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: DeckColors.textMuted,
                            ),
                          ),
                          Text(
                            host.tailscaleIp,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: DeckColors.textHigh,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            ' :${host.port}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: DeckColors.textMuted,
                            ),
                          ),
                          if (host.directIp != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              '• LAN: ${host.directIp}',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                color: DeckColors.meshCyan,
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            host.username,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: DeckColors.textMid,
                            ),
                          ),
                        ],
                      ),
                      if (host.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          host.description!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: DeckColors.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
