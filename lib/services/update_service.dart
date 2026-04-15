import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';

const _kSnoozedUntilKey = 'update_snoozed_until_ms';

enum UpdateCheckSource { homeAuto, settingsManual }

class UpdateService {
  static const _latestReleaseUrl =
      'https://api.github.com/repos/${AppConfig.githubOwner}/${AppConfig.githubRepo}/releases/latest';
  static const _tagsUrl =
      'https://api.github.com/repos/${AppConfig.githubOwner}/${AppConfig.githubRepo}/tags?per_page=30';
  static const _releasePageUrl =
      'https://github.com/${AppConfig.githubOwner}/${AppConfig.githubRepo}/releases/latest';
  static const Map<String, String> _githubHeaders = {
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': '${AppConfig.githubRepo}-update-check',
  };

  /// Checks GitHub for a newer release and shows the update dialog if found.
  ///
  /// – Returns immediately (no dialog) if the user snoozed until tomorrow.
  /// – When the update is actually installed, [currentVersion] matches the
  ///   remote version and [_isNewer] returns false — no dialog needed.
  /// – "Später" / launching the installer snoozes until tomorrow 00:00.
  static Future<bool> checkForUpdate(
    BuildContext context, {
    String? currentVersion,
    http.Client? httpClient,
    UpdateCheckSource source = UpdateCheckSource.homeAuto,
  }) async {
    try {
      final localVersion = await _resolveCurrentVersion(currentVersion);
      if (localVersion == null || localVersion.isEmpty) return false;

      final latest = await _fetchLatestInfo(client: httpClient);
      if (latest == null) return false;

      final remoteVersion = latest.version;
      if (!_isNewer(remoteVersion, localVersion)) return false;

      final prefs = await SharedPreferences.getInstance();

      if (source == UpdateCheckSource.homeAuto) {
        // Auto-check respects snooze. Manual check from settings bypasses it.
        final snoozedUntilMs = prefs.getInt(_kSnoozedUntilKey) ?? 0;
        if (snoozedUntilMs > DateTime.now().millisecondsSinceEpoch) {
          return false;
        }
      }

      final assets = latest.assets;

      final androidAsset = Platform.isAndroid
          ? _pickNewestAssetByExtension(assets, '.apk')
          : null;
      final iosIpaAsset = Platform.isIOS
          ? _pickNewestAssetByExtension(assets, '.ipa')
          : null;
      final iosPlistAsset = Platform.isIOS
          ? _pickNewestAssetByExtension(assets, '.plist')
          : null;

      final downloadUrl = Platform.isAndroid
          ? androidAsset?.url
          : iosIpaAsset?.url;
      final fileName = Platform.isAndroid
          ? androidAsset?.name
          : iosIpaAsset?.name;
      final plistUrl = iosPlistAsset?.url;

      if (Platform.isAndroid &&
          downloadUrl == null &&
          latest.releasePageUrl == null) {
        return false;
      }
      if (Platform.isIOS &&
          downloadUrl == null &&
          plistUrl == null &&
          latest.releasePageUrl == null) {
        return false;
      }

      if (!context.mounted) return false;

      showDialog(
        context: context,
        barrierDismissible: false, // must choose "Später" or "Aktualisieren"
        builder: (_) => _UpdateDialog(
          newVersion: remoteVersion,
          downloadUrl: downloadUrl,
          fileName:
              fileName ?? (Platform.isAndroid ? 'update.apk' : 'update.ipa'),
          plistUrl: plistUrl,
          releasePageUrl: latest.releasePageUrl,
          prefs: prefs,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('Update check failed: $e');
      return false;
    }
  }

  static Future<String?> _resolveCurrentVersion(String? explicitVersion) async {
    final cleaned = explicitVersion?.trim() ?? '';
    if (cleaned.isNotEmpty) return cleaned;
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      if (version.isEmpty) return null;
      return version;
    } catch (e) {
      debugPrint('Could not resolve app version: $e');
      return null;
    }
  }

  static Future<_LatestInfo?> _fetchLatestInfo({http.Client? client}) async {
    final effectiveClient = client ?? http.Client();
    final ownsClient = client == null;

    try {
      final releaseResponse = await effectiveClient
          .get(Uri.parse(_latestReleaseUrl), headers: _githubHeaders)
          .timeout(AppConfig.updateCheckTimeout);

      if (releaseResponse.statusCode == 200) {
        final data = jsonDecode(releaseResponse.body) as Map<String, dynamic>;
        final tagName = (data['tag_name'] as String?)?.trim();
        if (tagName != null && tagName.isNotEmpty) {
          final remoteVersion = _normalizeVersion(tagName);
          final rawAssets = data['assets'] as List<dynamic>? ?? const [];
          final assets = rawAssets
              .whereType<Map<String, dynamic>>()
              .toList(growable: false);
          return _LatestInfo(
            version: remoteVersion,
            assets: assets,
            releasePageUrl: data['html_url'] as String? ?? _releasePageUrl,
          );
        }
      }
    } catch (_) {}

    // Fallback: if latest release endpoint fails (or no release exists),
    // use tags for version detection and open releases page in browser.
    try {
      final tagsResponse = await effectiveClient
          .get(Uri.parse(_tagsUrl), headers: _githubHeaders)
          .timeout(AppConfig.updateCheckTimeout);
      if (tagsResponse.statusCode != 200) return null;

      final raw = jsonDecode(tagsResponse.body);
      if (raw is! List) return null;

      String? newest;
      for (final entry in raw) {
        if (entry is! Map<String, dynamic>) continue;
        final name = (entry['name'] as String?)?.trim();
        if (name == null || name.isEmpty) continue;
        final candidate = _normalizeVersion(name);
        if (_extractVersionNumbers(candidate).isEmpty) continue;
        if (newest == null || _isNewer(candidate, newest)) {
          newest = candidate;
        }
      }

      if (newest == null) return null;
      return const _LatestInfo(
        version: '',
        assets: <Map<String, dynamic>>[],
        releasePageUrl: _releasePageUrl,
      ).copyWith(version: newest);
    } catch (_) {
      return null;
    } finally {
      if (ownsClient) {
        effectiveClient.close();
      }
    }
  }

  @visibleForTesting
  static bool debugIsRemoteNewer(String remote, String local) =>
      _isNewer(remote, local);

  @visibleForTesting
  static Future<Map<String, Object?>?> debugFetchLatestInfo(http.Client client) async {
    final info = await _fetchLatestInfo(client: client);
    if (info == null) return null;
    return {
      'version': info.version,
      'assetsCount': info.assets.length,
      'releasePageUrl': info.releasePageUrl,
    };
  }

  static bool _isNewer(String remote, String local) {
    final r = _extractVersionNumbers(remote);
    final l = _extractVersionNumbers(local);
    if (r.isEmpty || l.isEmpty) return false;

    final length = r.length > l.length ? r.length : l.length;
    for (var i = 0; i < length; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return false;
  }

  static String _normalizeVersion(String value) =>
      value.trim().replaceFirst(RegExp(r'^[vV]'), '');

  static List<int> _extractVersionNumbers(String value) =>
      RegExp(r'\d+').allMatches(value).map((m) => int.parse(m.group(0)!)).toList();

  static _DownloadAsset? _pickNewestAssetByExtension(
    List<Map<String, dynamic>> assets,
    String extension,
  ) {
    _DownloadAsset? best;
    for (final asset in assets) {
      final name = (asset['name'] as String? ?? '').trim();
      final url = (asset['browser_download_url'] as String? ?? '').trim();
      if (name.isEmpty || url.isEmpty) continue;
      if (!name.toLowerCase().endsWith(extension)) continue;

      final updatedAtRaw = asset['updated_at'] as String?;
      final updatedAt = updatedAtRaw == null
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : (DateTime.tryParse(updatedAtRaw) ??
                DateTime.fromMillisecondsSinceEpoch(0));
      final candidate = _DownloadAsset(name: name, url: url, updatedAt: updatedAt);

      if (best == null || candidate.updatedAt.isAfter(best.updatedAt)) {
        best = candidate;
      }
    }
    return best;
  }
}

class _DownloadAsset {
  final String name;
  final String url;
  final DateTime updatedAt;

  const _DownloadAsset({
    required this.name,
    required this.url,
    required this.updatedAt,
  });
}

class _LatestInfo {
  final String version;
  final List<Map<String, dynamic>> assets;
  final String? releasePageUrl;

  const _LatestInfo({
    required this.version,
    required this.assets,
    required this.releasePageUrl,
  });

  _LatestInfo copyWith({
    String? version,
    List<Map<String, dynamic>>? assets,
    String? releasePageUrl,
  }) {
    return _LatestInfo(
      version: version ?? this.version,
      assets: assets ?? this.assets,
      releasePageUrl: releasePageUrl ?? this.releasePageUrl,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stateful update dialog
// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { prompt, downloading, installing, error }

class _UpdateDialog extends StatefulWidget {
  final String newVersion;
  final String? downloadUrl;
  final String fileName;
  final String? plistUrl;
  final String? releasePageUrl;
  final SharedPreferences prefs;

  const _UpdateDialog({
    required this.newVersion,
    this.downloadUrl,
    required this.fileName,
    this.plistUrl,
    this.releasePageUrl,
    required this.prefs,
  });

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  _Phase _phase = _Phase.prompt;
  double _progress = 0;
  String _errorMsg = '';
  http.Client? _httpClient;
  bool _busy = false;

  @override
  void dispose() {
    _httpClient?.close();
    super.dispose();
  }

  // ── Persistence helpers ──────────────────────────────────────────────────

  /// Snooze until tomorrow 00:00, so the reminder comes the next day.
  Future<void> _snoozeUntilTomorrow() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1); // midnight
    await widget.prefs.setInt(
      _kSnoozedUntilKey,
      tomorrow.millisecondsSinceEpoch,
    );
  }

  // ── Helper: canLaunchUrl with timeout ────────────────────────────────────
  Future<bool> _canLaunch(Uri uri) async {
    try {
      return await canLaunchUrl(
        uri,
      ).timeout(const Duration(seconds: 3), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  // ── Android ──────────────────────────────────────────────────────────────
  Future<void> _installAndroid() async {
    if (widget.downloadUrl == null) {
      await _openReleasePageFallback();
      return;
    }
    setState(() => _phase = _Phase.downloading);

    final client = http.Client();
    _httpClient = client;
    File? downloadedFile;

    try {
      final request = http.Request('GET', Uri.parse(widget.downloadUrl!));
      final streamedResponse = await client
          .send(request)
          .timeout(AppConfig.downloadTimeout);

      if (streamedResponse.statusCode != 200) {
        throw Exception('HTTP ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      downloadedFile = File('${dir.path}/${widget.fileName}');
      final sink = downloadedFile.openWrite();
      var received = 0;

      await for (final chunk in streamedResponse.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (totalBytes > 0 && mounted) {
          setState(() => _progress = received / totalBytes);
        }
      }
      await sink.close();

      if (!mounted) return;
      setState(() => _phase = _Phase.installing);

      final result = await OpenFilex.open(downloadedFile.path);
      if (result.type != ResultType.done && mounted) {
        final fallbackUri = Uri.parse(widget.downloadUrl!);
        final openedFallback = await launchUrl(
          fallbackUri,
          mode: LaunchMode.externalApplication,
        );
        if (!openedFallback) {
          throw Exception(result.message);
        }
      }

      if (mounted) Navigator.pop(context);

      final fileToClean = downloadedFile;
      Future.delayed(const Duration(minutes: 2), () {
        try {
          fileToClean.deleteSync();
        } catch (_) {}
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _errorMsg = e.toString();
        });
      }
    } finally {
      _httpClient = null;
      client.close();
    }
  }

  Future<void> _openReleasePageFallback() async {
    final url = widget.releasePageUrl;
    if (url == null) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMsg = 'Kein Download-Link für dieses Update gefunden';
      });
      return;
    }

    try {
      setState(() => _phase = _Phase.installing);
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) {
        throw Exception('release-page-launch-failed');
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _errorMsg = 'Release-Seite konnte nicht geöffnet werden';
      });
    }
  }

  // ── iOS ──────────────────────────────────────────────────────────────────
  Future<void> _installIOS() async {
    setState(() => _phase = _Phase.installing);
    final url = widget.downloadUrl;

    // Tier 1: Configured store installers (SideStore, AltStore, ...)
    if (url != null) {
      for (final scheme in AppConfig.iosInstallerSchemes) {
        try {
          final uri = AppConfig.buildIosInstallerUri(scheme, url);
          if (await _launchStoreInstaller(uri)) {
            if (mounted) Navigator.pop(context);
            return;
          }
        } catch (_) {}
      }
    }

    // Tier 2: itms-services (manifest.plist)
    if (widget.plistUrl != null) {
      try {
        final encoded = Uri.encodeComponent(widget.plistUrl!);
        final uri = Uri.parse(
          'itms-services://?action=download-manifest&url=$encoded',
        );
        if (await launchUrl(uri)) {
          if (mounted) Navigator.pop(context);
          return;
        }
      } catch (_) {}
    }

    // Tier 3: Browser fallback
    if (url != null) {
      try {
        final opened = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        if (opened) {
          if (mounted) Navigator.pop(context);
          return;
        }
      } catch (_) {}
    }

    if (widget.releasePageUrl != null) {
      await _openReleasePageFallback();
      return;
    }

    if (mounted) {
      setState(() {
        _phase = _Phase.error;
        _errorMsg = 'Update konnte nicht gestartet werden';
      });
    }
  }

  Future<bool> _launchStoreInstaller(Uri uri) async {
    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalNonBrowserApplication,
      );
      if (opened) return true;
    } catch (_) {}

    try {
      if (!await _canLaunch(uri)) return false;
      return launchUrl(uri);
    } catch (_) {
      return false;
    }
  }

  void _startUpdate() {
    if (_busy || _phase == _Phase.downloading || _phase == _Phase.installing) {
      return;
    }
    _busy = true;
    if (Platform.isIOS) {
      _installIOS().whenComplete(() => _busy = false);
    } else {
      _installAndroid().whenComplete(() => _busy = false);
    }
  }

  void _retry() => setState(() {
    _phase = _Phase.prompt;
    _progress = 0;
    _errorMsg = '';
  });

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) =>
      Platform.isIOS ? _buildCupertino() : _buildMaterial();

  Widget _buildMaterial() => AlertDialog(
    backgroundColor: AppTheme.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(_title(), style: TextStyle(color: AppTheme.textPrimary)),
    content: _content(false),
    actions: _materialActions(),
  );

  List<Widget> _materialActions() {
    switch (_phase) {
      case _Phase.prompt:
        return [
          TextButton(
            onPressed: () async {
              await _snoozeUntilTomorrow();
              if (mounted) Navigator.pop(context);
            },
            child: Text(
              'Morgen',
              style: TextStyle(color: AppTheme.textTertiary),
            ),
          ),
          TextButton(
            onPressed: _startUpdate,
            child: const Text(
              'Aktualisieren',
              style: TextStyle(color: AppTheme.accent),
            ),
          ),
        ];
      case _Phase.downloading:
      case _Phase.installing:
        return [];
      case _Phase.error:
        return [
          TextButton(
            onPressed: () async {
              await _snoozeUntilTomorrow();
              if (mounted) Navigator.pop(context);
            },
            child: Text(
              'Morgen',
              style: TextStyle(color: AppTheme.textTertiary),
            ),
          ),
          TextButton(
            onPressed: _retry,
            child: const Text(
              'Erneut versuchen',
              style: TextStyle(color: AppTheme.accent),
            ),
          ),
        ];
    }
  }

  Widget _buildCupertino() => CupertinoAlertDialog(
    title: Text(_title()),
    content: Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _content(true),
    ),
    actions: _cupertinoActions(),
  );

  List<Widget> _cupertinoActions() {
    switch (_phase) {
      case _Phase.prompt:
        return [
          CupertinoDialogAction(
            onPressed: () async {
              await _snoozeUntilTomorrow();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Morgen'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: _startUpdate,
            child: const Text('Aktualisieren'),
          ),
        ];
      case _Phase.downloading:
      case _Phase.installing:
        return [
          CupertinoDialogAction(
            onPressed: null,
            child: Text(
              _phase == _Phase.downloading ? 'Lädt…' : 'Installiert…',
              style: const TextStyle(color: CupertinoColors.inactiveGray),
            ),
          ),
        ];
      case _Phase.error:
        return [
          CupertinoDialogAction(
            onPressed: () async {
              await _snoozeUntilTomorrow();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Morgen'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: _retry,
            child: const Text('Erneut versuchen'),
          ),
        ];
    }
  }

  String _title() {
    switch (_phase) {
      case _Phase.prompt:
        return 'Update verfügbar';
      case _Phase.downloading:
        return 'Wird heruntergeladen…';
      case _Phase.installing:
        return Platform.isIOS ? 'Wird übergeben…' : 'Wird installiert…';
      case _Phase.error:
        return 'Update fehlgeschlagen';
    }
  }

  Widget _content(bool cupertino) {
    final secondaryStyle = cupertino
        ? null
        : TextStyle(color: AppTheme.textSecondary, fontSize: 14);

    switch (_phase) {
      case _Phase.prompt:
        return Text(
          'Version ${widget.newVersion} ist verfügbar.\nMöchtest du jetzt aktualisieren?',
          style: secondaryStyle,
        );
      case _Phase.downloading:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: cupertino
                    ? CupertinoColors.systemGrey5
                    : AppTheme.border,
                valueColor: AlwaysStoppedAnimation(
                  cupertino ? CupertinoColors.activeBlue : AppTheme.accent,
                ),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _progress > 0 ? '${(_progress * 100).toInt()} %' : 'Verbinde…',
              style: secondaryStyle ?? const TextStyle(fontSize: 14),
            ),
          ],
        );
      case _Phase.installing:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            if (cupertino)
              const CupertinoActivityIndicator(radius: 14)
            else
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTheme.accent,
                ),
              ),
            const SizedBox(height: 14),
            Text(
              Platform.isIOS
                  ? 'Wird an SideStore übergeben…'
                  : 'Update wird vorbereitet…',
              style: secondaryStyle ?? const TextStyle(fontSize: 14),
            ),
          ],
        );
      case _Phase.error:
        return Text(
          _errorMsg.isNotEmpty ? _errorMsg : 'Unbekannter Fehler',
          style: secondaryStyle ?? const TextStyle(fontSize: 14),
        );
    }
  }
}
