import 'package:flutter/material.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../services/terminal_session_controller.dart';
import 'device_detail_screen.dart';
import 'host_config_dialog.dart';
import 'terminal_tab.dart';

class DevicesTab extends StatefulWidget {
  final List<HostTarget> hosts;
  final HostTarget? activeHost;
  final StorageService storage;
  final SshService sshService;
  final TerminalSessionController terminalController;
  final Function(HostTarget) onSelectHost;
  final VoidCallback onHostsUpdated;
  final VoidCallback onRefresh;
  final bool isRefreshing;

  const DevicesTab({
    super.key,
    required this.hosts,
    required this.activeHost,
    required this.storage,
    required this.sshService,
    required this.terminalController,
    required this.onSelectHost,
    required this.onHostsUpdated,
    required this.onRefresh,
    this.isRefreshing = false,
  });

  @override
  State<DevicesTab> createState() => _DevicesTabState();
}

class _DevicesTabState extends State<DevicesTab> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _filter = 'all'; // all, online, linux, windows

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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
          widget.onHostsUpdated();
          widget.onSelectHost(newHost);
        },
      ),
    );
  }

  void _openDeviceDetails(HostTarget host, bool isSelected) {
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
  }

  @override
  Widget build(BuildContext context) {
    final filteredHosts = widget.hosts.where((h) {
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        if (!h.name.toLowerCase().contains(q) &&
            !h.tailscaleIp.contains(q) &&
            !(h.description?.toLowerCase().contains(q) ?? false)) {
          return false;
        }
      }
      if (_filter == 'online' && h.peerStatus != PeerStatus.online) {
        return false;
      }
      if (_filter == 'linux' && h.os != HostOs.linux) return false;
      if (_filter == 'windows' && h.os != HostOs.windows) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        backgroundColor: DeckColors.background,
        elevation: 0,
        actions: [
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: widget.isRefreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: DeckColors.primaryAccent,
                    ),
                  )
                : const Icon(
                    Icons.refresh,
                    size: 20,
                    color: DeckColors.secondaryText,
                  ),
            tooltip: 'Refresh Peers',
            onPressed: widget.isRefreshing ? null : widget.onRefresh,
          ),
          IconButton(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.add, color: DeckColors.primaryAccent),
            tooltip: 'Add Device',
            onPressed: _openAddDeviceDialog,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(
                  color: DeckColors.primaryText,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'Search by device name, OS, or IP...',
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 20,
                    color: DeckColors.mutedText,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          }),
                        )
                      : null,
                ),
                onChanged: (val) => setState(() => _searchQuery = val),
              ),
            ),

            // Filter Chips Row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Row(
                children: [
                  _buildFilterChip('All devices', 'all', widget.hosts.length),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Online',
                    'online',
                    widget.hosts
                        .where((h) => h.peerStatus == PeerStatus.online)
                        .length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Linux',
                    'linux',
                    widget.hosts.where((h) => h.os == HostOs.linux).length,
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    'Windows',
                    'windows',
                    widget.hosts.where((h) => h.os == HostOs.windows).length,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Device List
            Expanded(
              child: filteredHosts.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: DeckColors.primaryAccent,
                      backgroundColor: DeckColors.surfaceElevated,
                      onRefresh: () async => widget.onRefresh(),
                      child: ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        itemCount: filteredHosts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final host = filteredHosts[index];
                          final isSelected = host.id == widget.activeHost?.id;
                          return _buildDeviceCard(host, isSelected);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String filterKey, int count) {
    final isSelected = _filter == filterKey;
    return InkWell(
      onTap: () => setState(() => _filter = filterKey),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? DeckColors.surfaceHighlight
              : DeckColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                isSelected ? DeckColors.primaryAccent : DeckColors.borderSubtle,
            width: 1,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? DeckColors.primaryAccent
                    : DeckColors.secondaryText,
              ),
        ),
      ),
    );
  }

  Widget _buildDeviceCard(HostTarget host, bool isSelected) {
    final reachColor = _peerReachabilityColor(host.peerStatus);

    return Container(
      decoration: BoxDecoration(
        color: DeckColors.surfaceSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: DeckColors.borderSubtle,
          width: 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main clickable row: opens Device Details
          InkWell(
            onTap: () => _openDeviceDetails(host, isSelected),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // First line: Device name (never truncated) + Selected indicator + Trailing status & latency
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          switch (host.os) {
                            HostOs.linux => Icons.terminal,
                            HostOs.windows => Icons.window,
                            HostOs.macos => Icons.laptop_mac,
                          },
                          size: 20,
                          color: isSelected
                              ? DeckColors.primaryAccent
                              : DeckColors.secondaryText,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(
                                  host.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: DeckColors.primaryText,
                                      ),
                                ),
                                if (isSelected)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: DeckColors.primaryAccent
                                          .withValues(alpha: 0.14),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Selected',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: DeckColors.primaryAccent,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // Second line: Operating system · Device role or description
                            Text(
                              '${host.osDisplayName} · ${host.roleDisplayName}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: DeckColors.secondaryText,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Trailing information: Connection status + Latency, if available
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: reachColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                host.reachabilityLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                      fontSize: 11,
                                      color: reachColor,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                          if (host.hasFreshLatency) ...[
                            const SizedBox(height: 2),
                            Text(
                              '${host.pingMs} ms',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    fontSize: 11,
                                    color: DeckColors.secondaryText,
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Independent health states (Section 3): Peer, SSH, Remote Agent
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _buildStatePill(
                        'Peer',
                        host.reachabilityLabel,
                        _peerReachabilityColor(host.peerStatus),
                      ),
                      _buildStatePill(
                        'SSH',
                        host.sshStatusLabel,
                        _serviceColor(host.sshStatus),
                      ),
                      _buildStatePill(
                        'Agent',
                        host.agentStatusLabel,
                        _serviceColor(host.agentStatus),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(color: DeckColors.borderSubtle, height: 1),
          // Action bar: Select as Global Target vs Inspect Device Details
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: isSelected
                        ? null
                        : () {
                            widget.onSelectHost(host);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Global target set to ${host.name}',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                    icon: Icon(
                      isSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 16,
                      color: isSelected
                          ? DeckColors.primaryAccent
                          : DeckColors.secondaryText,
                    ),
                    label: Text(
                      isSelected ? 'Selected target' : 'Set as target',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? DeckColors.primaryAccent
                            : DeckColors.secondaryText,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      alignment: Alignment.centerLeft,
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: DeckColors.borderSubtle,
                ),
                IconButton(
                  icon: const Icon(Icons.terminal, size: 18),
                  color: DeckColors.secondaryText,
                  tooltip: 'Open Terminal on ${host.name}',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => TerminalTab(
                          hosts: widget.hosts,
                          activeHost: host,
                          controller: widget.terminalController,
                          storage: widget.storage,
                          onSelectHost: widget.onSelectHost,
                        ),
                      ),
                    );
                  },
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: DeckColors.borderSubtle,
                ),
                Expanded(
                  child: TextButton.icon(
                    onPressed: () => _openDeviceDetails(host, isSelected),
                    icon: const Icon(
                      Icons.open_in_new,
                      size: 15,
                      color: DeckColors.primaryAccent,
                    ),
                    label: const Text(
                      'Device details',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: DeckColors.primaryAccent,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      alignment: Alignment.centerRight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatePill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: DeckColors.background,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: DeckColors.borderSubtle, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 10,
              color: DeckColors.mutedText,
              fontWeight: FontWeight.w500,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Color _peerReachabilityColor(PeerStatus status) {
    return switch (status) {
      PeerStatus.online => DeckColors.healthy,
      PeerStatus.connecting => DeckColors.informational,
      PeerStatus.unreachable || PeerStatus.offline => DeckColors.error,
      PeerStatus.unknown => DeckColors.mutedText,
    };
  }

  Color _serviceColor(ServiceStatus status) {
    return switch (status) {
      ServiceStatus.available => DeckColors.healthy,
      ServiceStatus.connecting => DeckColors.informational,
      ServiceStatus.unavailable => DeckColors.error,
      ServiceStatus.unknown => DeckColors.mutedText,
    };
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.devices_other,
            size: 48,
            color: DeckColors.mutedText,
          ),
          const SizedBox(height: 12),
          Text(
            'No matching devices found',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: DeckColors.secondaryText,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Adjust your search query or filter chips.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DeckColors.mutedText,
                ),
          ),
        ],
      ),
    );
  }
}
