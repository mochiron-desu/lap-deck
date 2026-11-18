class RemoteFileItem {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime? modifyTime;
  final int? permissions;

  const RemoteFileItem({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    this.modifyTime,
    this.permissions,
  });

  String get formattedSize {
    if (isDirectory) return '--';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool get isHidden => name.startsWith('.') && name != '.' && name != '..';
}
