import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';

/// Checks GitHub releases for app updates and triggers download + install.
class UpdateService {
  /// GitHub repo to check (owner/repo).
  static const String repo = 'idontknow-you/personal_assistant';

  /// Base URL for GitHub API.
  static const String _apiBase = 'https://api.github.com/repos/$repo/releases/latest';


  /// Check if a newer version is available.
  /// Returns null if up-to-date, or a map with version info.
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final response = await http.get(
        Uri.parse(_apiBase),
        headers: {'Accept': 'application/vnd.github.v3+json'},
      );

      if (response.statusCode != 200) return null;

      final release = jsonDecode(response.body);
      final tagName = release['tag_name'] as String?; // e.g. "v1.1.0"
      final assets = release['assets'] as List? ?? [];

      if (tagName == null) return null;

      // Parse latest version
      final latestVersion = tagName.replaceFirst('v', '');

      // Parse current version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Compare versions
      if (_isNewer(latestVersion, currentVersion)) {
        // Find APK asset
        final apkAsset = assets.firstWhere(
          (a) => (a['name'] as String).endsWith('.apk'),
          orElse: () => null,
        );

        if (apkAsset == null) return null;

        return {
          'version': latestVersion,
          'currentVersion': currentVersion,
          'downloadUrl': apkAsset['browser_download_url'],
          'releaseNotes': release['body'] ?? 'No release notes.',
          'assetName': apkAsset['name'],
        };
      }

      return null; // Up to date
    } catch (e) {
      debugPrint('Update check failed: $e');
      return null;
    }
  }

  /// Download APK and trigger install.
  /// Returns the path to the downloaded APK, or null on failure.
  static Future<String?> downloadApk(
    String downloadUrl,
    Function(double progress)? onProgress,
  ) async {
    try {
      final dir = await getTemporaryDirectory();
      final apkPath = '${dir.path}/personal_os_update.apk';
      final file = File(apkPath);

      // Download with progress
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await http.Client().send(request);

      if (response.statusCode != 200) return null;

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;
      final sink = file.openWrite();

      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0 && onProgress != null) {
          onProgress(receivedBytes / totalBytes);
        }
      }

      await sink.close();
      return apkPath;
    } catch (e) {
      debugPrint('Download failed: $e');
      return null;
    }
  }

  /// Open the APK file to trigger Android's package installer.
  static Future<bool> triggerInstall(String apkPath) async {
    try {
      final result = await OpenFile.open(apkPath);
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('Install trigger failed: $e');
      return false;
    }
  }

  /// Compare two semver strings. Returns true if [latest] > [current].
  static bool _isNewer(String latest, String current) {
    final latestParts = latest.split('.').map(int.tryParse).toList();
    final currentParts = current.split('.').map(int.tryParse).toList();

    for (var i = 0; i < 3; i++) {
      final l = i < latestParts.length ? (latestParts[i] ?? 0) : 0;
      final c = i < currentParts.length ? (currentParts[i] ?? 0) : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }
}
