import 'package:flutter/material.dart';
import '../../theme/deck_theme.dart';
import '../../models/host_target.dart';

class HostConfigDialog extends StatefulWidget {
  final HostTarget? initialHost;
  final Function(HostTarget updatedHost, String? secret) onSave;
  final Function(String hostId)? onDelete;

  const HostConfigDialog({
    super.key,
    this.initialHost,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<HostConfigDialog> createState() => _HostConfigDialogState();
}

class _HostConfigDialogState extends State<HostConfigDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _ipController;
  late final TextEditingController _portController;
  late final TextEditingController _userController;
  late final TextEditingController _directIpController;
  late final TextEditingController _secretController;
  late final TextEditingController _descController;
  late HostOs _selectedOs;
  late AuthMethod _selectedAuth;

  @override
  void initState() {
    super.initState();
    final h = widget.initialHost;
    _nameController = TextEditingController(text: h?.name ?? '');
    _ipController = TextEditingController(text: h?.tailscaleIp ?? '');
    _portController = TextEditingController(text: h?.port.toString() ?? '22');
    _userController = TextEditingController(text: h?.username ?? 'surajwork');
    _directIpController = TextEditingController(text: h?.directIp ?? '');
    _secretController = TextEditingController();
    _descController = TextEditingController(text: h?.description ?? '');
    _selectedOs = h?.os ?? HostOs.linux;
    _selectedAuth = h?.authMethod ?? AuthMethod.tailscaleSsh;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _userController.dispose();
    _directIpController.dispose();
    _secretController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final name = _nameController.text.trim();
    final ip = _ipController.text.trim();
    final user = _userController.text.trim();

    if (name.isEmpty || ip.isEmpty || user.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Host name, IP, and username are required.')),
      );
      return;
    }

    final port = int.tryParse(_portController.text.trim()) ?? 22;

    final updated = HostTarget(
      id: widget.initialHost?.id ?? 'host-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      tailscaleIp: ip,
      port: port,
      username: user,
      authMethod: _selectedAuth,
      os: _selectedOs,
      directIp: _directIpController.text.trim().isEmpty ? null : _directIpController.text.trim(),
      description: _descController.text.trim().isEmpty ? null : _descController.text.trim(),
      isOnline: widget.initialHost?.isOnline ?? true,
      pingMs: widget.initialHost?.pingMs ?? 1,
    );

    final secret = _secretController.text.trim().isEmpty ? null : _secretController.text.trim();
    widget.onSave(updated, secret);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialHost != null;

    return Dialog(
      backgroundColor: DeckColors.surfaceElevated,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: DeckColors.borderMedium, width: 1),
        borderRadius: BorderRadius.circular(4),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  const Icon(Icons.settings_ethernet, size: 16, color: DeckColors.accentOrange),
                  const SizedBox(width: 8),
                  Text(
                    isEditing ? 'CONFIGURE PEER NODE' : 'ENROLL NEW PEER NODE',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      letterSpacing: 1.0,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const Divider(color: DeckColors.borderSubtle, height: 20),

              // Host Name & OS
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'HOSTNAME / RIG ALIAS',
                        hintText: 'surajworklaptop',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: DropdownButtonFormField<HostOs>(
                      value: _selectedOs,
                      decoration: const InputDecoration(labelText: 'OS TYPE'),
                      dropdownColor: DeckColors.surfaceRack,
                      items: HostOs.values.map((os) {
                        return DropdownMenuItem(
                          value: os,
                          child: Text(
                            os.name.toUpperCase(),
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedOs = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Tailscale IP & SSH Port
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'TAILSCALE IP',
                        hintText: '100.118.7.117',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'PORT',
                        hintText: '22',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Username & Direct LAN IP
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _userController,
                      decoration: const InputDecoration(
                        labelText: 'SSH USERNAME',
                        hintText: 'surajwork',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _directIpController,
                      decoration: const InputDecoration(
                        labelText: 'OPTIONAL LAN IP',
                        hintText: '192.168.29.61',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Auth Method Selection
              DropdownButtonFormField<AuthMethod>(
                value: _selectedAuth,
                decoration: const InputDecoration(labelText: 'AUTHENTICATION METHOD'),
                dropdownColor: DeckColors.surfaceRack,
                items: const [
                  DropdownMenuItem(
                    value: AuthMethod.tailscaleSsh,
                    child: Text('TAILSCALE SSH (ZERO-KEY MESH AUTH)'),
                  ),
                  DropdownMenuItem(
                    value: AuthMethod.privateKey,
                    child: Text('ED25519 / RSA PRIVATE KEY PEM'),
                  ),
                  DropdownMenuItem(
                    value: AuthMethod.password,
                    child: Text('STANDARD PASSWORD AUTH'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _selectedAuth = val);
                },
              ),
              const SizedBox(height: 12),

              // Secret / Key Input if not Tailscale SSH
              if (_selectedAuth != AuthMethod.tailscaleSsh) ...[
                TextField(
                  controller: _secretController,
                  obscureText: _selectedAuth == AuthMethod.password,
                  maxLines: _selectedAuth == AuthMethod.privateKey ? 4 : 1,
                  decoration: InputDecoration(
                    labelText: _selectedAuth == AuthMethod.password
                        ? 'SSH PASSWORD (STORED IN KEYSTORE)'
                        : 'PRIVATE KEY PEM STRING',
                    hintText: _selectedAuth == AuthMethod.password
                        ? '••••••••'
                        : '-----BEGIN OPENSSH PRIVATE KEY-----',
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Description / Role Notes
              TextField(
                controller: _descController,
                decoration: const InputDecoration(
                  labelText: 'DESCRIPTION / WORKSPACE NOTE',
                  hintText: 'Primary Ubuntu development rig',
                ),
              ),
              const SizedBox(height: 16),

              // Actions Row
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isEditing && widget.onDelete != null) ...[
                    TextButton(
                      onPressed: () {
                        widget.onDelete!(widget.initialHost!.id);
                        Navigator.of(context).pop();
                      },
                      child: Text(
                        'DELETE NODE',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: DeckColors.alertCrimson,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(
                      'CANCEL',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: DeckColors.textMid,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _handleSave,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: DeckColors.accentOrange,
                      foregroundColor: DeckColors.surfaceCore,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    ),
                    child: Text(
                      isEditing ? 'SAVE NODE' : 'ADD NODE',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: DeckColors.surfaceCore,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
