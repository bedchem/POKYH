import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

class UpdateService {
  static const _owner = 'bedchem';
  static const _repo = 'POKYH';
  static const _latestReleaseUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// Checks GitHub for a newer release and shows an update dialog if found.
  /// Returns true if an update was found and the dialog was shown.
  /// Silently returns false on any error (no internet, API failure, missing asset).
  static Future<bool> checkForUpdate(
    BuildContext context, {
    required String currentVersion,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(_latestReleaseUrl),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String?;
      if (tagName == null) return false;

      final remoteVersion = tagName.replaceFirst(RegExp(r'^v'), '');
      if (!_isNewer(remoteVersion, currentVersion)) return false;

      final assets = data['assets'] as List<dynamic>?;
      if (assets == null) return false;

      final downloadUrl = _pickAssetUrl(assets);
      if (downloadUrl == null) return false;

      if (!context.mounted) return false;

      _showUpdateDialog(context, remoteVersion, downloadUrl);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if [remote] is strictly newer than [local]
  /// using semantic version comparison.
  static bool _isNewer(String remote, String local) {
    final r = _parseVersion(remote);
    final l = _parseVersion(local);
    if (r == null || l == null) return false;

    for (var i = 0; i < 3; i++) {
      if (r[i] > l[i]) return true;
      if (r[i] < l[i]) return false;
    }
    return false;
  }

  /// Parses "1.2.3" into [1, 2, 3]. Returns null on bad input.
  static List<int>? _parseVersion(String v) {
    final parts = v.split('.');
    if (parts.length != 3) return null;
    try {
      return parts.map(int.parse).toList();
    } catch (_) {
      return null;
    }
  }

  /// Picks the .apk (Android) or .ipa (iOS) browser_download_url from assets.
  static String? _pickAssetUrl(List<dynamic> assets) {
    final ext = Platform.isIOS ? '.ipa' : '.apk';
    for (final asset in assets) {
      final name = (asset as Map<String, dynamic>)['name'] as String? ?? '';
      if (name.toLowerCase().endsWith(ext)) {
        return asset['browser_download_url'] as String?;
      }
    }
    return null;
  }

  static void _showUpdateDialog(
    BuildContext context,
    String newVersion,
    String downloadUrl,
  ) {
    if (Platform.isIOS) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Update verfügbar'),
          content: Text(
            'Eine neue Version ($newVersion) ist verfügbar. Möchtest du sie herunterladen?',
          ),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Später'),
            ),
            CupertinoDialogAction(
              onPressed: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.externalApplication);
              },
              child: const Text('Update'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Update verfügbar',
            style: TextStyle(color: AppTheme.textPrimary),
          ),
          content: Text(
            'Eine neue Version ($newVersion) ist verfügbar. Möchtest du sie herunterladen?',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Später', style: TextStyle(color: AppTheme.textTertiary)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                launchUrl(Uri.parse(downloadUrl), mode: LaunchMode.externalApplication);
              },
              child: const Text('Update', style: TextStyle(color: AppTheme.accent)),
            ),
          ],
        ),
      );
    }
  }
}
