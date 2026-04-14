import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';
import '../theme/app_theme.dart';

const _kLastInstalledVersionKey = 'last_installed_version';
const _kSnoozedUntilKey = 'update_snoozed_until_ms';

class UpdateService {
  static const _latestReleaseUrl =
      'https://api.github.com/repos/${AppConfig.githubOwner}/${AppConfig.githubRepo}/releases/latest';

  /// Checks GitHub for a newer release and shows the update dialog if found.
  ///
  /// – Returns immediately (no dialog) if the user snoozed until tomorrow.
  /// – Once installed the version is marked and the dialog never shows again
  ///   for that version.
  /// – "Später" schedules the next reminder for tomorrow 00:00.
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
          .timeout(AppConfig.updateCheckTimeout);

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String?;
      if (tagName == null) return false;

      final remoteVersion = tagName.replaceFirst(RegExp(r'^v'), '');
      if (!_isNewer(remoteVersion, currentVersion)) return false;

      final prefs = await SharedPreferences.getInstance();

      // Already fully installed this version → never show again.
      final lastInstalled = prefs.getString(_kLastInstalledVersionKey);
      if (lastInstalled == remoteVersion) return false;

      // User chose "Später" — respect snooze until tomorrow.
      final snoozedUntilMs = prefs.getInt(_kSnoozedUntilKey) ?? 0;
      if (snoozedUntilMs > DateTime.now().millisecondsSinceEpoch) return false;

      final assets = data['assets'] as List<dynamic>?;
      if (assets == null || assets.isEmpty) return false;

      String? downloadUrl;
      String? fileName;
      String? plistUrl;

      for (final raw in assets) {
        final asset = raw as Map<String, dynamic>;
        final name = (asset['name'] as String? ?? '').toLowerCase();
        final url = asset['browser_download_url'] as String?;
        if (url == null) continue;

        if (Platform.isAndroid && name.endsWith('.apk')) {
          downloadUrl = url;
          fileName = asset['name'] as String;
        } else if (Platform.isIOS) {
          if (name.endsWith('.ipa')) {
            downloadUrl = url;
            fileName = asset['name'] as String;
          } else if (name.endsWith('.plist')) {
            plistUrl = url;
          }
        }
      }

      if (Platform.isAndroid && downloadUrl == null) return false;
      if (Platform.isIOS && downloadUrl == null && plistUrl == null) return false;

      if (!context.mounted) return false;

      showDialog(
        context: context,
        barrierDismissible: false, // must choose "Später" or "Aktualisieren"
        builder: (_) => _UpdateDialog(
          newVersion: remoteVersion,
          downloadUrl: downloadUrl,
          fileName: fileName ?? (Platform.isAndroid ? 'update.apk' : 'update.ipa'),
          plistUrl: plistUrl,
          prefs: prefs,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

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

  static List<int>? _parseVersion(String v) {
    final parts = v.split('.');
    if (parts.length != 3) return null;
    try {
      return parts.map(int.parse).toList();
    } catch (_) {
      return null;
    }
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
  final SharedPreferences prefs;

  const _UpdateDialog({
    required this.newVersion,
    this.downloadUrl,
    required this.fileName,
    this.plistUrl,
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

  @override
  void dispose() {
    _httpClient?.close();
    super.dispose();
  }

  // ── Persistence helpers ──────────────────────────────────────────────────

  /// Called after successful install: this version is done, never remind again.
  Future<void> _markInstalled() async {
    await widget.prefs.setString(_kLastInstalledVersionKey, widget.newVersion);
    await widget.prefs.remove(_kSnoozedUntilKey);
  }

  /// "Später": snooze until tomorrow 00:00, so the reminder comes the next day.
  Future<void> _snoozeUntilTomorrow() async {
    final now = DateTime.now();
    final tomorrow = DateTime(now.year, now.month, now.day + 1); // midnight
    await widget.prefs.setInt(_kSnoozedUntilKey, tomorrow.millisecondsSinceEpoch);
  }

  // ── Helper: canLaunchUrl with timeout ────────────────────────────────────
  Future<bool> _canLaunch(Uri uri) async {
    try {
      return await canLaunchUrl(uri).timeout(
        const Duration(seconds: 3),
        onTimeout: () => false,
      );
    } catch (_) {
      return false;
    }
  }

  // ── Android ──────────────────────────────────────────────────────────────
  Future<void> _installAndroid() async {
    if (widget.downloadUrl == null) return;
    setState(() => _phase = _Phase.downloading);

    final client = http.Client();
    _httpClient = client;
    File? downloadedFile;

    try {
      final request = http.Request('GET', Uri.parse(widget.downloadUrl!));
      final streamedResponse =
          await client.send(request).timeout(AppConfig.downloadTimeout);

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
        throw Exception(result.message);
      }

      await _markInstalled();
      if (mounted) Navigator.pop(context);

      final fileToClean = downloadedFile;
      Future.delayed(const Duration(minutes: 2), () {
        try { fileToClean.deleteSync(); } catch (_) {}
      });
    } catch (e) {
      if (mounted) {
        setState(() { _phase = _Phase.error; _errorMsg = e.toString(); });
      }
    } finally {
      _httpClient = null;
      client.close();
    }
  }

  // ── iOS ──────────────────────────────────────────────────────────────────
  Future<void> _installIOS() async {
    setState(() => _phase = _Phase.installing);
    final url = widget.downloadUrl;

    // Tier 1: SideStore
    if (url != null) {
      try {
        final uri = Uri.parse('sidestore://install?url=${Uri.encodeComponent(url)}');
        if (await _canLaunch(uri)) {
          await launchUrl(uri);
          await _markInstalled();
          if (mounted) Navigator.pop(context);
          return;
        }
      } catch (_) {}
    }

    // Tier 2: AltStore
    if (url != null) {
      try {
        final uri = Uri.parse('altstore://install?url=${Uri.encodeComponent(url)}');
        if (await _canLaunch(uri)) {
          await launchUrl(uri);
          await _markInstalled();
          if (mounted) Navigator.pop(context);
          return;
        }
      } catch (_) {}
    }

    // Tier 3: itms-services (manifest.plist)
    if (widget.plistUrl != null) {
      try {
        final encoded = Uri.encodeComponent(widget.plistUrl!);
        final uri = Uri.parse('itms-services://?action=download-manifest&url=$encoded');
        if (await launchUrl(uri)) {
          await _markInstalled();
          if (mounted) Navigator.pop(context);
          return;
        }
      } catch (_) {}
    }

    // Tier 4: Browser fallback
    if (url != null) {
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        await _markInstalled();
        if (mounted) Navigator.pop(context);
        return;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _phase = _Phase.error;
        _errorMsg = 'Update konnte nicht gestartet werden';
      });
    }
  }

  void _startUpdate() {
    if (Platform.isIOS) _installIOS(); else _installAndroid();
  }

  void _retry() => setState(() { _phase = _Phase.prompt; _progress = 0; _errorMsg = ''; });

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
            child: Text('Morgen', style: TextStyle(color: AppTheme.textTertiary)),
          ),
          TextButton(
            onPressed: _startUpdate,
            child: const Text('Aktualisieren', style: TextStyle(color: AppTheme.accent)),
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
            child: Text('Morgen', style: TextStyle(color: AppTheme.textTertiary)),
          ),
          TextButton(
            onPressed: _retry,
            child: const Text('Erneut versuchen', style: TextStyle(color: AppTheme.accent)),
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
      case _Phase.prompt:      return 'Update verfügbar';
      case _Phase.downloading: return 'Wird heruntergeladen…';
      case _Phase.installing:  return Platform.isIOS ? 'Wird übergeben…' : 'Wird installiert…';
      case _Phase.error:       return 'Update fehlgeschlagen';
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
                backgroundColor: cupertino ? CupertinoColors.systemGrey5 : AppTheme.border,
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
                width: 28, height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.accent),
              ),
            const SizedBox(height: 14),
            Text(
              Platform.isIOS ? 'Wird an SideStore übergeben…' : 'Update wird vorbereitet…',
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
