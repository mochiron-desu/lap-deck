import 'package:flutter/material.dart';
import 'host_target.dart';

enum ActionCategory { system, security, tailscale, power, custom }

class CommandAction {
  final String id;
  final String label;
  final String description;
  final String command;
  final IconData icon;
  final ActionCategory category;
  final HostOs? targetOs;
  final bool isDestructive;

  const CommandAction({
    required this.id,
    required this.label,
    required this.description,
    required this.command,
    required this.icon,
    required this.category,
    this.targetOs,
    this.isDestructive = false,
  });

  static List<CommandAction> get defaultActions => [
    const CommandAction(
      id: 'act-sys-telemetry',
      label: 'SYS TELEMETRY',
      description: 'Host load, uptime, RAM allocation and disk metrics',
      command: 'uptime && echo "--- MEMORY ---" && free -h && echo "--- DISK ---" && df -h /',
      icon: Icons.speed,
      category: ActionCategory.system,
    ),
    const CommandAction(
      id: 'act-top-proc',
      label: 'TOP PROCESSES',
      description: 'Top CPU and Memory consuming processes',
      command: 'ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -n 12',
      icon: Icons.memory,
      category: ActionCategory.system,
      targetOs: HostOs.linux,
    ),
    const CommandAction(
      id: 'act-lapdog-status',
      label: 'LAPDOG STATE',
      description: 'Query security daemon status & pending events',
      command: 'lapdog status 2>/dev/null || ~/.local/bin/lapdog status 2>/dev/null || echo "lapdog binary not in path"',
      icon: Icons.security,
      category: ActionCategory.security,
    ),
    const CommandAction(
      id: 'act-lapdog-away',
      label: 'ARM AWAY MODE',
      description: 'Arm laptop monitoring mode (alert triggers enabled)',
      command: 'lapdog away 2>/dev/null || echo "lapdog not found"',
      icon: Icons.shield,
      category: ActionCategory.security,
    ),
    const CommandAction(
      id: 'act-lapdog-back',
      label: 'DISARM AWAY',
      description: 'Disarm laptop away mode (suppress alerts)',
      command: 'lapdog back 2>/dev/null || echo "lapdog not found"',
      icon: Icons.verified_user,
      category: ActionCategory.security,
    ),
    const CommandAction(
      id: 'act-tailscale-mesh',
      label: 'TAILSCALE MESH',
      description: 'Peer routing table and direct connection status',
      command: 'tailscale status',
      icon: Icons.hub,
      category: ActionCategory.tailscale,
    ),
    const CommandAction(
      id: 'act-lock-screen',
      label: 'LOCK DISPLAY',
      description: 'Instantly lock active user graphical session',
      command: 'loginctl lock-session 2>/dev/null || gnome-screensaver-command -l 2>/dev/null || echo "session locked"',
      icon: Icons.lock_outline,
      category: ActionCategory.power,
      isDestructive: true,
    ),
    const CommandAction(
      id: 'act-connector-status',
      label: 'CONNECTOR SERVICE',
      description: 'Check telegram-antigravity-connector process',
      command: 'pgrep -fa "telegram-antigravity-connector" || echo "Connector not running"',
      icon: Icons.sensors,
      category: ActionCategory.system,
    ),
  ];
}
