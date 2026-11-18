import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/host_target.dart';
import '../../models/remote_file_item.dart';
import '../../services/ssh_service.dart';
import '../../services/storage_service.dart';
import '../../theme/deck_theme.dart';

class RemoteFileExplorerScreen extends StatefulWidget {
  final HostTarget host;
  final SshService sshService;
  final StorageService storageService;

  const RemoteFileExplorerScreen({
    super.key,
    required this.host,
    required this.sshService,
    required this.storageService,
  });

  @override
  State<RemoteFileExplorerScreen> createState() =>
      _RemoteFileExplorerScreenState();
}

class _RemoteFileExplorerScreenState extends State<RemoteFileExplorerScreen> {
  String _currentPath = '.';
  String _canonicalPath = '';
  List<RemoteFileItem> _items = [];
  bool _isLoading = true;
  String? _error;
  bool _showHidden = false;
  String _searchFilter = '';
  final TextEditingController _searchController = TextEditingController();

  // Transfer state
  bool _isTransferring = false;
  String _transferLabel = '';
  double _transferProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadDirectory(_currentPath);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String?> _getSecret() async {
    return await widget.storageService.getHostCredential(widget.host.id);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final secret = await _getSecret();
      final items = await widget.sshService.listRemoteFiles(
        widget.host,
        path,
        secret: secret,
      );

      String canonical = path;
      try {
        canonical = await widget.sshService.resolveRemoteAbsolutePath(
          widget.host,
          path,
          secret: secret,
        );
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _currentPath = path;
        _canonicalPath = canonical;
        _items = items;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _navigateUp() {
    if (_currentPath == '.' || _currentPath == '/' || _currentPath.isEmpty) {
      if (_canonicalPath.isNotEmpty && _canonicalPath != '/') {
        final parent = _getParentPath(_canonicalPath);
        _loadDirectory(parent);
      }
      return;
    }
    final parent = _getParentPath(_currentPath);
    _loadDirectory(parent);
  }

  String _getParentPath(String path) {
    var p = path.replaceAll('\\', '/');
    if (p.endsWith('/') && p.length > 1) {
      p = p.substring(0, p.length - 1);
    }
    final lastSlash = p.lastIndexOf('/');
    if (lastSlash == -1) return '.';
    if (lastSlash == 0) return '/';
    return p.substring(0, lastSlash);
  }

  List<RemoteFileItem> get _filteredItems {
    return _items.where((item) {
      if (!_showHidden && item.isHidden) return false;
      if (_searchFilter.trim().isEmpty) return true;
      return item.name.toLowerCase().contains(_searchFilter.toLowerCase());
    }).toList();
  }

  Future<void> _handleDownload(RemoteFileItem item) async {
    final secret = await _getSecret();
    setState(() {
      _isTransferring = true;
      _transferLabel = 'Downloading ${item.name}...';
      _transferProgress = 0.0;
    });

    try {
      Directory? baseDir;
      try {
        baseDir = await getDownloadsDirectory();
      } catch (_) {}
      baseDir ??= await getApplicationDocumentsDirectory();

      final destinationPath = '${baseDir.path}/${item.name}';

      await widget.sshService.downloadRemoteFile(
        widget.host,
        item.path,
        destinationPath,
        secret: secret,
        onProgress: (received, total) {
          if (!mounted) return;
          if (total > 0) {
            setState(() {
              _transferProgress = (received / total).clamp(0.0, 1.0);
            });
          }
        },
      );

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: DeckColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: DeckColors.healthy, width: 1),
          ),
          content: Text(
            'Downloaded ${item.name} (${item.formattedSize})',
            style: const TextStyle(color: DeckColors.primaryText),
          ),
          action: SnackBarAction(
            label: 'Share / Open',
            textColor: DeckColors.primaryAccent,
            onPressed: () {
              SharePlus.instance.share(
                ShareParams(files: [XFile(destinationPath)]),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: DeckColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: DeckColors.error, width: 1),
          ),
          content: Text(
            'Download failed: $e',
            style: const TextStyle(color: DeckColors.error),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTransferring = false;
        });
      }
    }
  }

  Future<void> _handleUpload() async {
    final result = await FilePicker.pickFiles();
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    final picked = result.files.first;
    final localPath = picked.path;
    if (localPath == null) return;

    final fileName = picked.name;
    final targetRemotePath = _currentPath == '/' || _currentPath == '.'
        ? (_currentPath == '.' ? fileName : '/$fileName')
        : (_currentPath.endsWith('/')
            ? '$_currentPath$fileName'
            : '$_currentPath/$fileName');

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DeckColors.borderMedium, width: 1),
        ),
        title: Text(
          'Upload File to ${widget.host.name}?',
          style: const TextStyle(
            color: DeckColors.primaryText,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'File: $fileName',
              style: const TextStyle(
                color: DeckColors.primaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Size: ${(picked.size / 1024).toStringAsFixed(1)} KB',
              style: const TextStyle(color: DeckColors.secondaryText, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Text(
              'Destination directory:\n${_canonicalPath.isNotEmpty ? _canonicalPath : _currentPath}',
              style: GoogleFonts.jetBrainsMono(
                color: DeckColors.mutedText,
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: DeckColors.secondaryText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DeckColors.primaryAccent,
              foregroundColor: DeckColors.background,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Upload'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final secret = await _getSecret();
    setState(() {
      _isTransferring = true;
      _transferLabel = 'Uploading $fileName...';
      _transferProgress = 0.0;
    });

    try {
      await widget.sshService.uploadRemoteFile(
        widget.host,
        localPath,
        targetRemotePath,
        secret: secret,
        onProgress: (sent, total) {
          if (!mounted) return;
          if (total > 0) {
            setState(() {
              _transferProgress = (sent / total).clamp(0.0, 1.0);
            });
          }
        },
      );

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: DeckColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: DeckColors.healthy, width: 1),
          ),
          content: Text(
            'Uploaded $fileName to ${widget.host.name}',
            style: const TextStyle(color: DeckColors.healthy),
          ),
        ),
      );
      _loadDirectory(_currentPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: DeckColors.surfaceElevated,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: DeckColors.error, width: 1),
          ),
          content: Text(
            'Upload failed: $e',
            style: const TextStyle(color: DeckColors.error),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isTransferring = false;
        });
      }
    }
  }

  Future<void> _handleCreateFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DeckColors.borderMedium, width: 1),
        ),
        title: const Text(
          'New Remote Folder',
          style: TextStyle(
            color: DeckColors.primaryText,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: DeckColors.primaryText),
          decoration: const InputDecoration(
            hintText: 'Folder name',
            hintStyle: TextStyle(color: DeckColors.mutedText),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel', style: TextStyle(color: DeckColors.secondaryText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DeckColors.primaryAccent,
              foregroundColor: DeckColors.background,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final targetPath = _currentPath == '/' || _currentPath == '.'
        ? (_currentPath == '.' ? name : '/$name')
        : (_currentPath.endsWith('/') ? '$_currentPath$name' : '$_currentPath/$name');

    try {
      final secret = await _getSecret();
      await widget.sshService.createRemoteDirectory(
        widget.host,
        targetPath,
        secret: secret,
      );
      _loadDirectory(_currentPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: DeckColors.surfaceElevated,
          content: Text('Failed to create folder: $e', style: const TextStyle(color: DeckColors.error)),
        ),
      );
    }
  }

  Future<void> _handleDelete(RemoteFileItem item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: DeckColors.surfaceSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DeckColors.error, width: 1),
        ),
        title: Text(
          'Delete ${item.isDirectory ? "Folder" : "File"}?',
          style: const TextStyle(
            color: DeckColors.primaryText,
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'Are you sure you want to permanently delete "${item.name}" from ${widget.host.name}?',
          style: const TextStyle(color: DeckColors.secondaryText, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: DeckColors.secondaryText)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: DeckColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final secret = await _getSecret();
      await widget.sshService.deleteRemoteItem(
        widget.host,
        item.path,
        isDirectory: item.isDirectory,
        secret: secret,
      );
      _loadDirectory(_currentPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: DeckColors.surfaceElevated,
          content: Text('Delete failed: $e', style: const TextStyle(color: DeckColors.error)),
        ),
      );
    }
  }

  IconData _getFileIcon(RemoteFileItem item) {
    if (item.isDirectory) return Icons.folder;
    final ext = item.name.contains('.') ? item.name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'sh':
      case 'ps1':
      case 'json':
      case 'yaml':
      case 'yml':
      case 'html':
      case 'css':
        return Icons.code;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
      case 'webp':
        return Icons.image_outlined;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
      case 'rar':
        return Icons.archive_outlined;
      case 'pdf':
      case 'txt':
      case 'md':
      case 'doc':
      case 'docx':
        return Icons.description_outlined;
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
        return Icons.video_file_outlined;
      case 'mp3':
      case 'wav':
      case 'ogg':
      case 'flac':
        return Icons.audio_file_outlined;
      default:
        return Icons.insert_drive_file_outlined;
    }
  }

  Color _getFileColor(RemoteFileItem item) {
    if (item.isDirectory) return DeckColors.primaryAccent;
    final ext = item.name.contains('.') ? item.name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'sh':
      case 'ps1':
      case 'json':
      case 'yaml':
      case 'yml':
        return DeckColors.informational;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
      case 'svg':
      case 'webp':
        return DeckColors.healthy;
      case 'zip':
      case 'tar':
      case 'gz':
      case '7z':
        return DeckColors.warning;
      case 'pdf':
      case 'txt':
      case 'md':
        return DeckColors.secondaryText;
      default:
        return DeckColors.mutedText;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DeckColors.background,
      appBar: AppBar(
        backgroundColor: DeckColors.background,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Files · ${widget.host.name}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: DeckColors.primaryText,
                  ),
            ),
            Text(
              '${widget.host.osDisplayName} · SFTP',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: DeckColors.secondaryText,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _showHidden ? 'Hide dotfiles' : 'Show dotfiles',
            icon: Icon(
              _showHidden ? Icons.visibility : Icons.visibility_off,
              color: _showHidden ? DeckColors.primaryAccent : DeckColors.secondaryText,
            ),
            onPressed: () {
              setState(() {
                _showHidden = !_showHidden;
              });
            },
          ),
          IconButton(
            tooltip: 'New Folder',
            icon: const Icon(Icons.create_new_folder_outlined, color: DeckColors.secondaryText),
            onPressed: _handleCreateFolder,
          ),
          IconButton(
            tooltip: 'Upload File',
            icon: const Icon(Icons.upload_file, color: DeckColors.primaryAccent),
            onPressed: _handleUpload,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Transfer Progress Banner
            if (_isTransferring)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: DeckColors.surfaceElevated,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _transferLabel,
                          style: const TextStyle(
                            color: DeckColors.primaryAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${(_transferProgress * 100).toStringAsFixed(0)}%',
                          style: GoogleFonts.jetBrainsMono(
                            color: DeckColors.primaryAccent,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: _transferProgress > 0 ? _transferProgress : null,
                      backgroundColor: DeckColors.borderSubtle,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        DeckColors.primaryAccent,
                      ),
                      minHeight: 3,
                    ),
                  ],
                ),
              ),

            // Path & Navigation Header Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                color: DeckColors.surfaceSecondary,
                border: Border(
                  bottom: BorderSide(color: DeckColors.borderSubtle, width: 1),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Go to Home directory',
                    icon: const Icon(Icons.home_outlined, size: 20),
                    color: DeckColors.secondaryText,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _loadDirectory('.'),
                  ),
                  IconButton(
                    tooltip: 'Up one directory',
                    icon: const Icon(Icons.arrow_upward, size: 20),
                    color: DeckColors.secondaryText,
                    visualDensity: VisualDensity.compact,
                    onPressed: _navigateUp,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: DeckColors.background,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: DeckColors.borderSubtle, width: 1),
                      ),
                      child: Text(
                        _canonicalPath.isNotEmpty ? _canonicalPath : _currentPath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: DeckColors.primaryText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) {
                    setState(() {
                      _searchFilter = val;
                    });
                  },
                  style: const TextStyle(fontSize: 13, color: DeckColors.primaryText),
                  decoration: InputDecoration(
                    hintText: 'Search files in folder...',
                    hintStyle: const TextStyle(color: DeckColors.mutedText, fontSize: 13),
                    prefixIcon: const Icon(Icons.search, size: 18, color: DeckColors.secondaryText),
                    suffixIcon: _searchFilter.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16, color: DeckColors.secondaryText),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _searchFilter = '';
                              });
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    filled: true,
                    fillColor: DeckColors.surfaceElevated,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: DeckColors.borderSubtle, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: DeckColors.borderSubtle, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: DeckColors.primaryAccent, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),

            // Directory Listing Body
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(
                            strokeWidth: 2,
                            color: DeckColors.primaryAccent,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Reading remote directory...',
                            style: TextStyle(
                              color: DeckColors.secondaryText,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24.0),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.error_outline,
                                  size: 36,
                                  color: DeckColors.error,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Failed to read directory',
                                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        color: DeckColors.primaryText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 11,
                                    color: DeckColors.secondaryText,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: DeckColors.surfaceElevated,
                                    foregroundColor: DeckColors.primaryText,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      side: const BorderSide(color: DeckColors.borderSubtle),
                                    ),
                                  ),
                                  onPressed: () => _loadDirectory(_currentPath),
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _filteredItems.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.folder_open,
                                    size: 40,
                                    color: DeckColors.mutedText,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _searchFilter.isNotEmpty
                                        ? 'No matching files found'
                                        : 'Directory is empty',
                                    style: const TextStyle(
                                      color: DeckColors.secondaryText,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              color: DeckColors.primaryAccent,
                              backgroundColor: DeckColors.surfaceElevated,
                              onRefresh: () => _loadDirectory(_currentPath),
                              child: ListView.separated(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                itemCount: _filteredItems.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(color: DeckColors.borderSubtle, height: 1),
                                itemBuilder: (context, index) {
                                  final item = _filteredItems[index];
                                  final icon = _getFileIcon(item);
                                  final color = _getFileColor(item);

                                  return ListTile(
                                    contentPadding:
                                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    leading: Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(icon, color: color, size: 20),
                                    ),
                                    title: Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: item.isDirectory
                                            ? DeckColors.primaryText
                                            : DeckColors.primaryText.withValues(alpha: 0.9),
                                        fontWeight: item.isDirectory
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        fontSize: 13,
                                      ),
                                    ),
                                    subtitle: Row(
                                      children: [
                                        Text(
                                          item.formattedSize,
                                          style: GoogleFonts.jetBrainsMono(
                                            fontSize: 11,
                                            color: DeckColors.mutedText,
                                          ),
                                        ),
                                        if (item.modifyTime != null) ...[
                                          const Text(
                                            ' • ',
                                            style: TextStyle(color: DeckColors.mutedText),
                                          ),
                                          Text(
                                            DateFormat('MMM d, HH:mm').format(item.modifyTime!),
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: DeckColors.mutedText,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    trailing: item.isDirectory
                                        ? const Icon(
                                            Icons.chevron_right,
                                            color: DeckColors.mutedText,
                                            size: 18,
                                          )
                                        : Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                tooltip: 'Download ${item.name}',
                                                icon: const Icon(
                                                  Icons.download_rounded,
                                                  size: 18,
                                                  color: DeckColors.primaryAccent,
                                                ),
                                                onPressed: () => _handleDownload(item),
                                              ),
                                              PopupMenuButton<String>(
                                                icon: const Icon(
                                                  Icons.more_vert,
                                                  size: 18,
                                                  color: DeckColors.secondaryText,
                                                ),
                                                color: DeckColors.surfaceSecondary,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  side: const BorderSide(
                                                    color: DeckColors.borderSubtle,
                                                  ),
                                                ),
                                                onSelected: (val) {
                                                  if (val == 'download') {
                                                    _handleDownload(item);
                                                  } else if (val == 'delete') {
                                                    _handleDelete(item);
                                                  }
                                                },
                                                itemBuilder: (ctx) => [
                                                  const PopupMenuItem(
                                                    value: 'download',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.download, size: 16, color: DeckColors.primaryAccent),
                                                        SizedBox(width: 8),
                                                        Text('Download to device', style: TextStyle(color: DeckColors.primaryText, fontSize: 13)),
                                                      ],
                                                    ),
                                                  ),
                                                  const PopupMenuItem(
                                                    value: 'delete',
                                                    child: Row(
                                                      children: [
                                                        Icon(Icons.delete_outline, size: 16, color: DeckColors.error),
                                                        SizedBox(width: 8),
                                                        Text('Delete', style: TextStyle(color: DeckColors.error, fontSize: 13)),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                    onTap: () {
                                      if (item.isDirectory) {
                                        _loadDirectory(item.path);
                                      } else {
                                        _handleDownload(item);
                                      }
                                    },
                                    onLongPress: () {
                                      _handleDelete(item);
                                    },
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
