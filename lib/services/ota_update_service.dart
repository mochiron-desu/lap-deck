import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../models/host_target.dart';
import '../models/notification_settings.dart';
import 'app_logger.dart';
import 'notification_service.dart';
import 'ssh_service.dart';
import 'storage_service.dart';

/// Manages peerless GitHub Git OTA hotfix checks, APK downloads, peer-fallback builds,
/// and native Android PackageInstaller upgrades.
class OtaUpdateService {
  static const MethodChannel _channel = MethodChannel(
    'com.mochirondesu.lap_deck/platform',
  );

  final StorageService storage;
  final NotificationService? notificationService;
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10);

  OtaUpdateInfo? _lastCheckInfo;

  OtaUpdateService({
    required this.storage,
    this.notificationService,
  });

  OtaUpdateInfo? get lastCheckInfo => _lastCheckInfo;

  /// Checks GitHub (mochiron-desu/lap-deck) directly over HTTPS for new commits on `main`
  /// and pre-built hotfix APK releases (`hotfix-latest` or latest release) — zero peer connection needed.
  Future<OtaUpdateInfo> checkForGitUpdates({
    String branch = AppVersionInfo.compiledBranch,
  }) async {
    final installedSha = storage.getInstalledCommitSha();
    final pat = await storage.getGithubToken();

    try {
      AppLogger.info(
        'OtaUpdateService',
        'Checking GitHub (${AppVersionInfo.githubRepoSlug}) for Git hotfix updates...',
      );

      // 1. Fetch latest commit on branch
      final commitData = await _githubGetJson(
        'https://api.github.com/repos/${AppVersionInfo.githubRepoSlug}/commits/$branch',
        token: pat,
      );

      String? latestSha;
      String? latestMessage;
      String? latestAuthor;
      DateTime? commitDate;

      if (commitData != null && commitData['sha'] != null) {
        latestSha = commitData['sha'].toString();
        final commitObj = commitData['commit'] as Map<String, dynamic>?;
        latestMessage = commitObj?['message']?.toString().trim();
        final authorObj = commitObj?['author'] as Map<String, dynamic>?;
        latestAuthor = authorObj?['name']?.toString() ??
            (commitData['author'] is Map
                ? commitData['author']['login']?.toString()
                : null);
        final dateStr = authorObj?['date']?.toString();
        if (dateStr != null) {
          commitDate = DateTime.tryParse(dateStr);
        }
      }

      // 2. Check rolling 'hotfix-latest' release (or latest release) for a pre-built APK asset
      String? apkUrl;
      int? apkSize;
      String? releaseTag;

      Map<String, dynamic>? releaseData = await _githubGetJson(
        'https://api.github.com/repos/${AppVersionInfo.githubRepoSlug}/releases/tags/hotfix-latest',
        token: pat,
      );
      releaseData ??= await _githubGetJson(
        'https://api.github.com/repos/${AppVersionInfo.githubRepoSlug}/releases/latest',
        token: pat,
      );

      if (releaseData != null) {
        releaseTag = releaseData['tag_name']?.toString();
        final bodyText = releaseData['body']?.toString() ?? '';
        // If commitData failed (e.g. rate limit), extract SHA from release body if present
        if (latestSha == null) {
          final match = RegExp(r'Commit:\s*([0-9a-fA-F]{7,40})')
              .firstMatch(bodyText);
          if (match != null) {
            latestSha = match.group(1);
          }
        }
        final assets = releaseData['assets'];
        if (assets is List) {
          for (final asset in assets) {
            if (asset is Map) {
              final name = (asset['name']?.toString() ?? '').toLowerCase();
              if (name.endsWith('.apk')) {
                // Use API asset URL when PAT is configured, or browser_download_url for public access
                apkUrl = (pat != null && pat.isNotEmpty)
                    ? (asset['url']?.toString() ??
                        asset['browser_download_url']?.toString())
                    : asset['browser_download_url']?.toString();
                apkSize = (asset['size'] as num?)?.toInt();
                break;
              }
            }
          }
        }
      }

      if (latestSha == null) {
        final errInfo = OtaUpdateInfo(
          state: OtaUpdateState.error,
          installedCommitSha: installedSha,
          errorMessage:
              'Could not query GitHub repository (${AppVersionInfo.githubRepoSlug}). If the repo is private, add a GitHub PAT in Settings.',
          checkedAt: DateTime.now(),
        );
        _lastCheckInfo = errInfo;
        return errInfo;
      }

      final isDifferent = installedSha == 'local-HEAD' ||
          (!latestSha.toLowerCase().startsWith(installedSha.toLowerCase()) &&
              !installedSha.toLowerCase().startsWith(latestSha.toLowerCase()));

      final info = OtaUpdateInfo(
        state: isDifferent
            ? OtaUpdateState.updateAvailable
            : OtaUpdateState.upToDate,
        installedCommitSha: installedSha,
        latestCommitSha: latestSha,
        latestCommitMessage: latestMessage,
        latestAuthor: latestAuthor,
        commitDate: commitDate,
        apkDownloadUrl: apkUrl,
        apkSizeBytes: apkSize,
        releaseTag: releaseTag,
        checkedAt: DateTime.now(),
      );

      _lastCheckInfo = info;
      if (info.state == OtaUpdateState.updateAvailable) {
        await notificationService?.notifyOtaUpdateAvailable(info);
      }
      return info;
    } catch (e, st) {
      AppLogger.error('OtaUpdateService', 'Git OTA check error: $e', e, st);
      final errInfo = OtaUpdateInfo(
        state: OtaUpdateState.error,
        installedCommitSha: installedSha,
        errorMessage: 'Git update check failed: $e',
        checkedAt: DateTime.now(),
      );
      _lastCheckInfo = errInfo;
      return errInfo;
    }
  }

  /// Downloads the hotfix APK directly from GitHub without touching any peer,
  /// saves it to temporary cache, and triggers Android's native PackageInstaller.
  Future<({bool ok, String message, String? localPath})>
      downloadAndInstallGitHotfix({
    required OtaUpdateInfo updateInfo,
    required void Function(double progress, String statusText) onProgress,
  }) async {
    final url = updateInfo.apkDownloadUrl;
    if (url == null || url.isEmpty) {
      return (
        ok: false,
        message:
            'No pre-built APK asset found on GitHub release. Push to main to trigger the GitHub Actions Hotfix builder, or use "Pull & Build via Peer".',
        localPath: null,
      );
    }

    final pat = await storage.getGithubToken();

    try {
      onProgress(0.02, 'Connecting to GitHub release asset...');
      final tempDir = await getTemporaryDirectory();
      final shaTag = updateInfo.shortLatestSha;
      final destFile = File('${tempDir.path}/lapdeck-hotfix-$shaTag.apk');

      HttpClientRequest req = await _httpClient.getUrl(Uri.parse(url));
      req.headers.set('User-Agent', 'LapDeck-OTA-Updater/1.2');
      if (pat != null && pat.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $pat');
      }
      if (url.contains('api.github.com/repos/') && url.contains('/assets/')) {
        req.headers.set('Accept', 'application/octet-stream');
      } else {
        req.headers.set('Accept', '*/*');
      }

      HttpClientResponse resp = await req.close();

      // Handle 302 redirect to GitHub Objects CDN if HttpClient didn't auto-follow
      if (resp.statusCode == 302 || resp.statusCode == 301) {
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        if (loc != null && loc.isNotEmpty) {
          final redirectReq = await _httpClient.getUrl(Uri.parse(loc));
          redirectReq.headers.set('User-Agent', 'LapDeck-OTA-Updater/1.2');
          resp = await redirectReq.close();
        }
      }

      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        return (
          ok: false,
          message:
              'GitHub download failed with HTTP ${resp.statusCode}. Verify release asset permissions.',
          localPath: null,
        );
      }

      final totalBytes = resp.contentLength > 0
          ? resp.contentLength
          : (updateInfo.apkSizeBytes ?? 0);
      int receivedBytes = 0;

      final sink = destFile.openWrite();
      await for (final chunk in resp) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          final pct = (receivedBytes / totalBytes).clamp(0.0, 0.98);
          final mbDone = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          final mbTotal = (totalBytes / (1024 * 1024)).toStringAsFixed(1);
          onProgress(pct, 'Downloading hotfix APK ($mbDone / $mbTotal MB)...');
        } else {
          final mbDone = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
          onProgress(0.5, 'Downloading hotfix APK ($mbDone MB)...');
        }
      }
      await sink.flush();
      await sink.close();

      onProgress(1.0, 'Launching Android Package Installer...');
      if (updateInfo.latestCommitSha != null) {
        await storage.setInstalledCommitSha(updateInfo.latestCommitSha!);
      }

      final launched = await installApkFile(destFile.path);
      if (launched) {
        return (
          ok: true,
          message:
              'Android Package Installer launched for commit ${updateInfo.shortLatestSha}. Confirm the prompt to complete hotfix.',
          localPath: destFile.path,
        );
      } else {
        return (
          ok: false,
          message:
              'Please grant "Install unknown apps" permission for LapDeck, then tap Install Hotfix again.',
          localPath: destFile.path,
        );
      }
    } catch (e, st) {
      AppLogger.error('OtaUpdateService', 'OTA download failed: $e', e, st);
      return (
        ok: false,
        message: 'Hotfix download error: $e',
        localPath: null,
      );
    }
  }

  /// Fallback Path: Pulls the latest Git changes on an online workstation peer,
  /// builds (or grabs the latest built) release APK with the embedded commit SHA,
  /// streams it over SFTP to the phone, and launches the native Android installer.
  Future<({bool ok, String message})> pullAndBuildViaPeer({
    required HostTarget peer,
    required SshService sshService,
    required void Function(double progress, String statusText) onProgress,
    bool forceRebuild = true,
  }) async {
    try {
      final secret = await storage.getHostCredential(peer.id);
      onProgress(0.10, 'Connecting to ${peer.name} and pulling latest Git commits...');

      final String buildScript;
      if (peer.os == HostOs.windows) {
        final winBuildLine = forceRebuild
            ? r'flutter build apk --release --dart-define=GIT_COMMIT_SHA=$sha 2>&1 | Out-Null'
            : '';
        buildScript = '''
\$repo = "\$HOME\\Coding\\misc\\lap-deck"
if (-not (Test-Path \$repo)) { \$repo = "\$HOME\\lap-deck" }
Set-Location \$repo
git pull --ff-only 2>&1 | Out-Null
\$sha = (git rev-parse HEAD).Trim()
$winBuildLine
\$apk = Resolve-Path "build\\app\\outputs\\flutter-apk\\app-release.apk"
Write-Output "LAPDECK_APK_READY|\$sha|\$(\$apk.Path)"
''';
      } else {
        final linuxBuildLine = forceRebuild
            ? 'flutter build apk --release --dart-define=GIT_COMMIT_SHA="\$SHA" >/dev/null 2>&1 || exit 1'
            : '';
        buildScript = '''
export PATH="\$PATH:\$HOME/Coding/Flutter SDK/flutter/bin:\$HOME/flutter/bin:\$HOME/.local/bin"
REPO="\$HOME/Coding/misc/lap-deck"
if [ ! -d "\$REPO" ]; then REPO="\$HOME/lap-deck"; fi
cd "\$REPO" || exit 1
git pull --ff-only >/dev/null 2>&1 || true
SHA=\$(git rev-parse HEAD 2>/dev/null || echo "local-HEAD")
$linuxBuildLine
APK="\$REPO/build/app/outputs/flutter-apk/app-release.apk"
if [ -f "\$APK" ]; then
  echo "LAPDECK_APK_READY|\$SHA|\$APK"
else
  echo "LAPDECK_APK_MISSING|\$SHA|\$APK"
  exit 1
fi
''';
      }

      if (forceRebuild) {
        onProgress(
          0.25,
          'Compiling release APK on ${peer.name} (git pull + flutter build apk)...',
        );
      }

      final execRes = await sshService.executeCommand(
        host: peer,
        command: buildScript,
        password: peer.authMethod == AuthMethod.password ? secret : null,
        privateKeyPem: peer.authMethod == AuthMethod.privateKey ? secret : null,
        timeout: const Duration(seconds: 6),
        executionTimeout: const Duration(minutes: 4),
      );

      final out = execRes.output.trim();
      final match = RegExp(r'LAPDECK_APK_READY\|([^|]+)\|(.+)').firstMatch(out);
      if (!execRes.isSuccess || match == null) {
        return (
          ok: false,
          message:
              'Peer build failed on ${peer.name}: ${execRes.error.isNotEmpty ? execRes.error.trim() : out}',
        );
      }

      final builtSha = match.group(1)!.trim();
      final remoteApkPath = match.group(2)!.trim();

      onProgress(
        0.55,
        'Streaming compiled APK (${builtSha.substring(0, builtSha.length > 7 ? 7 : builtSha.length)}) from ${peer.name}...',
      );

      final tempDir = await getTemporaryDirectory();
      final localApkPath = '${tempDir.path}/lapdeck-peer-$builtSha.apk';

      await sshService.downloadRemoteFile(
        peer,
        remoteApkPath,
        localApkPath,
        secret: secret,
        onProgress: (transferred, total) {
          if (total > 0) {
            final pct = 0.55 + 0.40 * (transferred / total).clamp(0.0, 1.0);
            final mbDone = (transferred / (1024 * 1024)).toStringAsFixed(1);
            final mbTotal = (total / (1024 * 1024)).toStringAsFixed(1);
            onProgress(pct, 'Downloading APK ($mbDone / $mbTotal MB)...');
          }
        },
      );

      onProgress(0.98, 'Launching Android Package Installer...');
      await storage.setInstalledCommitSha(builtSha);
      final launched = await installApkFile(localApkPath);
      return (
        ok: launched,
        message: launched
            ? 'Package Installer launched for commit ${builtSha.length > 7 ? builtSha.substring(0, 7) : builtSha} built via ${peer.name}.'
            : 'Grant "Install unknown apps" permission for LapDeck, then retry.',
      );
    } catch (e, st) {
      AppLogger.error('OtaUpdateService', 'Peer OTA build error: $e', e, st);
      return (ok: false, message: 'Peer build/download error: $e');
    }
  }

  /// Invokes MainActivity.kt to check or request unknown package install permission and launch the APK intent.
  Future<bool> installApkFile(String filePath) async {
    try {
      final res = await _channel.invokeMethod<bool>('installApk', {
        'filePath': filePath,
      });
      return res ?? false;
    } catch (e) {
      AppLogger.error('OtaUpdateService', 'Failed launching APK installer: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>?> _githubGetJson(
    String url, {
    String? token,
  }) async {
    try {
      final req = await _httpClient
          .getUrl(Uri.parse(url))
          .timeout(const Duration(seconds: 8));
      req.headers.set('User-Agent', 'LapDeck-OTA-Updater/1.2');
      req.headers.set('Accept', 'application/vnd.github+json');
      if (token != null && token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      final resp = await req.close().timeout(const Duration(seconds: 8));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final body = await utf8.decodeStream(resp);
        final decoded = json.decode(body);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (_) {}
    return null;
  }
}
