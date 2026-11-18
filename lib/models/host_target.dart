import 'dart:convert';

enum HostOs { linux, windows, macos }
enum AuthMethod { tailscaleSsh, privateKey, password }

class HostTarget {
  final String id;
  final String name;
  final String tailscaleIp;
  final int port;
  final String username;
  final AuthMethod authMethod;
  final HostOs os;
  final String? directIp;
  final String? privateKey; // In-memory or key alias
  final bool isDirect;
  final int? pingMs;
  final bool isOnline;
  final DateTime? lastConnected;
  final String? description;

  const HostTarget({
    required this.id,
    required this.name,
    required this.tailscaleIp,
    this.port = 22,
    required this.username,
    this.authMethod = AuthMethod.tailscaleSsh,
    required this.os,
    this.directIp,
    this.privateKey,
    this.isDirect = false,
    this.pingMs,
    this.isOnline = false,
    this.lastConnected,
    this.description,
  });

  HostTarget copyWith({
    String? id,
    String? name,
    String? tailscaleIp,
    int? port,
    String? username,
    AuthMethod? authMethod,
    HostOs? os,
    String? directIp,
    String? privateKey,
    bool? isDirect,
    int? pingMs,
    bool? isOnline,
    DateTime? lastConnected,
    String? description,
  }) {
    return HostTarget(
      id: id ?? this.id,
      name: name ?? this.name,
      tailscaleIp: tailscaleIp ?? this.tailscaleIp,
      port: port ?? this.port,
      username: username ?? this.username,
      authMethod: authMethod ?? this.authMethod,
      os: os ?? this.os,
      directIp: directIp ?? this.directIp,
      privateKey: privateKey ?? this.privateKey,
      isDirect: isDirect ?? this.isDirect,
      pingMs: pingMs ?? this.pingMs,
      isOnline: isOnline ?? this.isOnline,
      lastConnected: lastConnected ?? this.lastConnected,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'tailscaleIp': tailscaleIp,
      'port': port,
      'username': username,
      'authMethod': authMethod.name,
      'os': os.name,
      'directIp': directIp,
      'isDirect': isDirect,
      'description': description,
    };
  }

  factory HostTarget.fromMap(Map<String, dynamic> map) {
    return HostTarget(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      tailscaleIp: map['tailscaleIp'] ?? '',
      port: map['port'] ?? 22,
      username: map['username'] ?? '',
      authMethod: AuthMethod.values.firstWhere(
        (e) => e.name == map['authMethod'],
        orElse: () => AuthMethod.tailscaleSsh,
      ),
      os: HostOs.values.firstWhere(
        (e) => e.name == map['os'],
        orElse: () => HostOs.linux,
      ),
      directIp: map['directIp'],
      isDirect: map['isDirect'] ?? false,
      description: map['description'],
    );
  }

  String toJson() => json.encode(toMap());
  factory HostTarget.fromJson(String source) => HostTarget.fromMap(json.decode(source));

  static List<HostTarget> get defaultHosts => [
    const HostTarget(
      id: 'host-surajworklaptop',
      name: 'surajworklaptop',
      tailscaleIp: '100.118.7.117',
      port: 22,
      username: 'surajwork',
      authMethod: AuthMethod.tailscaleSsh,
      os: HostOs.linux,
      description: 'Primary Linux Dev Rig • Ubuntu 24.04 LTS',
      isOnline: true,
      isDirect: true,
      pingMs: 1,
    ),
    const HostTarget(
      id: 'host-mochirondesu',
      name: 'mochirondesu',
      tailscaleIp: '100.79.206.82',
      port: 22,
      username: 'suraj',
      authMethod: AuthMethod.tailscaleSsh,
      os: HostOs.windows,
      directIp: '192.168.29.61',
      description: 'Secondary Peer Rig • Windows 11 / WSL2',
      isOnline: true,
      isDirect: true,
      pingMs: 4,
    ),
  ];
}
