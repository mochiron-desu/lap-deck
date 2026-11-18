import 'package:flutter/material.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../services/terminal_session_controller.dart';
import 'device_detail_screen.dart';
import 'host_config_dialog.dart';

class DevicesTab extends StatefulWidget {
  final List<HostTarget> hosts;
  final HostTarget? activeHost;
  final StorageService storage;
  final SshService sshService;
  final TerminalSessionController terminalController;
  final Function(HostTarget) onSelectHost;
  final VoidCallback onHostsUpdated;

  const DevicesTab({
    super.key,
    required this.hosts,
    required this.activeHost,
    required this.storage,
    required this.sshService,
    required this.terminalController,
    required this.onSelectHost,
    required this.onHostsUpdated,
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
          widget.onSelectHost(newHost);
          widget.onHostsUpdated();
        },
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
      if (_filter == 'online' && !h.isOnline) return false;
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
                style: const TextStyle(color: DeckColors.primaryText, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search by hostname or IP...',
                  prefixIcon: const Icon(Icons.search, size: 20, color: DeckColors.mutedText),
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
                  _buildFilterChip('Online', 'online', widget.hosts.where((h) => h.isOnline).length),
                  const SizedBox(width: 8),
                  _buildFilterChip('Linux', 'linux', widget.hosts.where((h) => h.os == HostOs.linux).length),
                  const SizedBox(width: 8),
                  _buildFilterChip('Windows', 'windows', widget.hosts.where((h) => h.os == HostOs.windows).length),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Device List
            Expanded(
              child: filteredHosts.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      itemCount: filteredHosts.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final host = filteredHosts[index];
                        final isSelected = host.id == widget.activeHost?.id;
                        return _buildDeviceCard(host, isSelected);
                      },
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? DeckColors.surfaceHighlight : DeckColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? DeckColors.primaryAccent : DeckColors.borderSubtle,
            width: 1,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            color: isSelected ? DeckColors.primaryAccent : DeckColors.secondaryText,
          ),
        ),
      ),
    );
  }

  Widget _buildDeviceCard(HostTarget host, bool isSelected) {
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
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: DeckColors.surfaceSecondary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? DeckColors.primaryAccent.withValues(alpha: 0.6) : DeckColors.borderSubtle,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
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
                const SizedBox(width: 10),
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        host.name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: DeckColors.primaryText,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (isSelected)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: DeckColors.primaryAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            'TARGET',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: DeckColors.primaryAccent),
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  width: 8,
                  height: 8,
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
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${host.tailscaleIp} :${host.port} • ${host.username}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 12,
                color: DeckColors.secondaryText,
              ),
            ),
            if (host.description != null) ...[
              const SizedBox(height: 4),
              Text(
                host.description!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: DeckColors.mutedText,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (host.directIp != null)
                  Text(
                    'LAN: ${host.directIp}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: DeckColors.informational,
                    ),
                  )
                else
                  const SizedBox(),
                Row(
                  children: [
                    Text(
                      'Manage & Telemetry',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: DeckColors.primaryAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 14, color: DeckColors.primaryAccent),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.devices_other, size: 48, color: DeckColors.mutedText),
          const SizedBox(height: 12),
          Text(
            'No matching devices found',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: DeckColors.secondaryText),
          ),
          const SizedBox(height: 4),
          Text(
            'Adjust your search query or filter chips.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: DeckColors.mutedText),
          ),
        ],
      ),
    );
  }
}
