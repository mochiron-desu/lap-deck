import 'package:flutter/material.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';
import '../../models/vitals_data.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../services/terminal_session_controller.dart';
import 'device_detail_screen.dart';
import 'host_config_dialog.dart';

class HomeTab extends StatefulWidget {
  final List<HostTarget> hosts;
  final HostTarget? activeHost;
  final VitalsData vitals;
  final LapdogStatus lapdogStatus;
  final bool isVitalsLoading;
  final String? connectionError;
  final StorageService storage;
  final SshService sshService;
  final TerminalSessionController terminalController;
  final Function(HostTarget) onSelectHost;
  final VoidCallback onRefresh;
  final Function(int tabIndex) onNavigateTab;
  final VoidCallback onHostsUpdated;

  const HomeTab({
    super.key,
    required this.hosts,
    required this.activeHost,
    required this.vitals,
    required this.lapdogStatus,
    required this.isVitalsLoading,
    required this.connectionError,
    required this.storage,
    required this.sshService,
    required this.terminalController,
    required this.onSelectHost,
    required this.onRefresh,
    required this.onNavigateTab,
    required this.onHostsUpdated,
  });

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  bool _isTogglingAway = false;

  void _openAddDeviceDialog() {
    showDialog(
      context: context,
      builder: (ctx) => HostConfigDialog(
        onSave: (newHost, secret) async {
          final list = List<HostTarget>.from(widget.hosts)..add(newHost);
          await widget.storage.saveHosts(list);
          if (secret != null) {
            await widget.storage.saveHostCredential(newHost.id, secret);
          }
          widget.onSelectHost(newHost);
          widget.onHostsUpdated();
        },
      ),
    );
  }

  Future<void> _handleToggleAwayMode() async {
    final host = widget.activeHost;
    if (host == null) return;

    final newState = !widget.lapdogStatus.isAwayArmed;
    setState(() => _isTogglingAway = true);

    final secret = await widget.storage.getHostCredential(host.id);
    final cmd = newState ? 'lapdog away 2>/dev/null' : 'lapdog back 2>/dev/null';

    final res = await widget.sshService.executeCommand(
      host: host,
      command: cmd,
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
      password: host.authMethod == AuthMethod.password ? secret : null,
    );

    setState(() => _isTogglingAway = false);

    if (mounted) {
      if (res.isSuccess) {
        widget.onRefresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newState
                  ? 'Lap-Dog Away Mode is now ARMED. Alerts enabled.'
                  : 'Lap-Dog Away Mode DISARMED. Normal home mode.',
            ),
            backgroundColor: newState ? DeckColors.warning : DeckColors.healthy,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to toggle Away Mode: ${res.error}'),
            backgroundColor: DeckColors.error,
          ),
        );
      }
    }
  }

  Future<void> _handleLockDisplay() async {
    final host = widget.activeHost;
    if (host == null) return;

    final secret = await widget.storage.getHostCredential(host.id);
    final res = await widget.sshService.executeCommand(
      host: host,
      command: 'loginctl lock-session 2>/dev/null || gnome-screensaver-command -l 2>/dev/null || rundll32.exe user32.dll,LockWorkStation 2>/dev/null',
      privateKeyPem: host.authMethod == AuthMethod.privateKey ? secret : null,
      password: host.authMethod == AuthMethod.password ? secret : null,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.isSuccess ? 'Workstation display locked' : 'Lock failed: ${res.error}'),
          backgroundColor: res.isSuccess ? DeckColors.surfaceElevated : DeckColors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = widget.connectionError == null;
    final active = widget.activeHost;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // A. Compact Application Header
            _buildAppHeader(isOnline),

            // Diagnostic Alert Banner if disconnected
            if (!isOnline) _buildOfflineBanner(),

            // Scrollable Content
            Expanded(
              child: RefreshIndicator(
                color: DeckColors.primaryAccent,
                backgroundColor: DeckColors.surfaceElevated,
                onRefresh: () async => widget.onRefresh(),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // B. Network Overview Card (3-Second Comprehension)
                      _buildNetworkOverviewCard(isOnline, active),
                      const SizedBox(height: 20),

                      // C. Quick Actions
                      _buildQuickActionsRow(),
                      const SizedBox(height: 24),

                      // D. Connected Devices Overview
                      _buildDevicesSection(),
                      const SizedBox(height: 24),

                      // E. Security Overview
                      _buildSecurityOverviewCard(),
                      const SizedBox(height: 24),

                      // F. Recent Verified Activity
                      _buildActivitySection(),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppHeader(bool isOnline) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: const BoxDecoration(
        color: DeckColors.background,
        border: Border(bottom: BorderSide(color: DeckColors.borderSubtle, width: 1)),
      ),
      child: Row(
        children: [
          Row(
            children: [
              Text(
                'LAPDECK',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: DeckColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: DeckColors.borderSubtle, width: 1),
                ),
                child: Text(
                  'v1.1',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: DeckColors.secondaryText,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          // Refresh Button
          IconButton(
            icon: widget.isVitalsLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: DeckColors.primaryAccent),
                  )
                : const Icon(Icons.refresh, size: 20, color: DeckColors.secondaryText),
            tooltip: 'Refresh Network State',
            onPressed: widget.isVitalsLoading ? null : widget.onRefresh,
          ),
          // Add Device Action
          IconButton(
            icon: const Icon(Icons.add, size: 20, color: DeckColors.primaryAccent),
            tooltip: 'Add Peer Device',
            onPressed: _openAddDeviceDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: DeckColors.error.withValues(alpha: 0.15),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: DeckColors.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.connectionError!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                color: DeckColors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: widget.onRefresh,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text('RETRY', style: TextStyle(color: DeckColors.error, fontWeight: FontWeight.w700, fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkOverviewCard(bool isOnline, HostTarget? active) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isOnline ? DeckColors.healthy : DeckColors.error,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                isOnline ? 'Network healthy' : 'Network degraded',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isOnline ? DeckColors.healthy : DeckColors.error,
                ),
              ),
              const Spacer(),
              Text(
                'Updated just now',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DeckColors.mutedText,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  title: 'CONNECTED PEERS',
                  value: '${widget.hosts.where((h) => h.isOnline).length} of ${widget.hosts.length} online',
                  icon: Icons.hub_outlined,
                ),
              ),
              Container(width: 1, height: 36, color: DeckColors.borderSubtle),
              Expanded(
                child: _buildMetricTile(
                  title: 'MESH LATENCY',
                  value: (active != null && active.isOnline && active.pingMs != null)
                      ? '${active.pingMs} ms'
                      : 'Offline',
                  icon: Icons.speed_outlined,
                ),
              ),
              Container(width: 1, height: 36, color: DeckColors.borderSubtle),
              Expanded(
                child: _buildMetricTile(
                  title: 'TARGET RIG',
                  value: active?.name ?? 'None',
                  icon: Icons.laptop_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetricTile({required String title, required String value, required IconData icon}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontSize: 10,
              letterSpacing: 0.5,
              color: DeckColors.mutedText,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: DeckColors.primaryText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick actions',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: DeckColors.secondaryText,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildActionTile(
                icon: Icons.terminal,
                label: 'Terminal',
                onTap: () => widget.onNavigateTab(2), // Navigate to Terminal tab
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildActionTile(
                icon: Icons.speed,
                label: 'Diagnostics',
                onTap: widget.onRefresh,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildActionTile(
                icon: widget.lapdogStatus.isAwayArmed ? Icons.shield : Icons.verified_user,
                label: widget.lapdogStatus.isAwayArmed ? 'Disarm Away' : 'Arm Away',
                accentColor: widget.lapdogStatus.isAwayArmed ? DeckColors.warning : DeckColors.healthy,
                onTap: _handleToggleAwayMode,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildActionTile(
                icon: Icons.lock_outline,
                label: 'Lock Rig',
                onTap: _handleLockDisplay,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? accentColor,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: DeckColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: DeckColors.borderSubtle, width: 1),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: accentColor ?? DeckColors.primaryAccent),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: DeckColors.primaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Connected devices',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: DeckColors.secondaryText,
              ),
            ),
            TextButton(
              onPressed: () => widget.onNavigateTab(1), // Devices Tab
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'View all (${widget.hosts.length})',
                style: const TextStyle(fontSize: 12, color: DeckColors.primaryAccent),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: widget.hosts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final host = widget.hosts[index];
            final isSelected = host.id == widget.activeHost?.id;
            return _buildDeviceItem(host, isSelected);
          },
        ),
      ],
    );
  }

  Widget _buildDeviceItem(HostTarget host, bool isSelected) {
    return InkWell(
      onTap: () {
        widget.onSelectHost(host);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DeviceDetailScreen(
              host: host,
              storage: widget.storage,
              sshService: widget.sshService,
              terminalController: widget.terminalController,
              onUpdated: widget.onHostsUpdated,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: DeckColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? DeckColors.primaryAccent.withValues(alpha: 0.5) : DeckColors.borderSubtle,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              switch (host.os) {
                HostOs.linux => Icons.terminal,
                HostOs.windows => Icons.window,
                HostOs.macos => Icons.laptop_mac,
              },
              size: 20,
              color: isSelected ? DeckColors.primaryAccent : DeckColors.secondaryText,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        host.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: DeckColors.primaryText,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: DeckColors.primaryAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: DeckColors.primaryAccent),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${host.tailscaleIp} • ${host.description ?? host.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: DeckColors.mutedText,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: host.isOnline ? DeckColors.healthy : DeckColors.mutedText,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  host.isOnline ? '${host.pingMs ?? 50} ms' : 'Offline',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 11,
                    color: host.isOnline ? DeckColors.healthy : DeckColors.mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, size: 16, color: DeckColors.mutedText),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityOverviewCard() {
    final isArmed = widget.lapdogStatus.isAwayArmed;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isArmed ? Icons.shield : Icons.verified_user,
                size: 18,
                color: isArmed ? DeckColors.warning : DeckColors.healthy,
              ),
              const SizedBox(width: 8),
              Text(
                'Lapdog security',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: DeckColors.primaryText,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: (isArmed ? DeckColors.warning : DeckColors.healthy).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isArmed ? 'Away armed' : 'Home mode',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isArmed ? DeckColors.warning : DeckColors.healthy,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isArmed
                ? 'Away mode is active. Webcam capture enabled on failed authentications.'
                : 'Daemon running normally. Non-critical login alerts suppressed.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: DeckColors.secondaryText,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${widget.lapdogStatus.sentHistory} security events audited',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: DeckColors.mutedText,
                ),
              ),
              InkWell(
                onTap: _isTogglingAway ? null : _handleToggleAwayMode,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: DeckColors.surfaceElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: DeckColors.borderSubtle, width: 1),
                  ),
                  child: Row(
                    children: [
                      if (_isTogglingAway)
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(strokeWidth: 1.5, color: DeckColors.primaryAccent),
                        )
                      else
                        Icon(isArmed ? Icons.lock_open : Icons.shield, size: 12, color: DeckColors.primaryAccent),
                      const SizedBox(width: 6),
                      Text(
                        isArmed ? 'Disarm away' : 'Arm away',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: DeckColors.primaryAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActivitySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent activity',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: DeckColors.secondaryText,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: DeckColors.surfaceSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DeckColors.borderSubtle, width: 1),
          ),
          child: Column(
            children: [
              _buildActivityItem(
                icon: Icons.hub,
                title: 'Tailscale peer connected',
                subtitle: 'surajworklaptop (100.118.7.117)',
                time: 'Just now',
              ),
              const Divider(color: DeckColors.borderSubtle, height: 16),
              _buildActivityItem(
                icon: Icons.vpn_key,
                title: 'SSH authentication verified',
                subtitle: 'Ed25519 identity key loaded from Keystore',
                time: '14:47',
              ),
              const Divider(color: DeckColors.borderSubtle, height: 16),
              _buildActivityItem(
                icon: Icons.shield,
                title: 'Lap-Dog watchdog check',
                subtitle: 'Security daemon active with 0 pending alerts',
                time: '14:15',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActivityItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required String time,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: DeckColors.primaryAccent),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: DeckColors.primaryText,
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  color: DeckColors.mutedText,
                ),
              ),
            ],
          ),
        ),
        Text(
          time,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 10,
            color: DeckColors.mutedText,
          ),
        ),
      ],
    );
  }
}
