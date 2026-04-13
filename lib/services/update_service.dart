import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

class UpdateService {
  static const _owner = 'bedchem';
  static const _repo = 'POKYH';
  static const _latestReleaseUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// Checks GitHub for a newer release and shows an update dialog if found.
  /// Returns true if an update was found and the dialog was shown.
  /// Silently returns false on any error.
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
      if (assets == null || assets.isEmpty) return false;

      // Collect relevant asset URLs from the release.
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

      // On Android we need an APK; on iOS we need either a plist or an IPA.
      if (Platform.isAndroid && downloadUrl == null) return false;
      if (Platform.isIOS && downloadUrl == null && plistUrl == null) return false;

      if (!context.mounted) return false;

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UpdateDialog(
          newVersion: remoteVersion,
          downloadUrl: downloadUrl,
          fileName: fileName ?? (Platform.isAndroid ? 'update.apk' : 'update.ipa'),
          plistUrl: plistUrl,
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
// Stateful update dialog – shows prompt → progress → install / error
// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { prompt, downloading, installing, error }

class _UpdateDialog extends StatefulWidget {
  final String newVersion;
  final String? downloadUrl;
  final String fileName;
  final String? plistUrl;

  const _UpdateDialog({
    required this.newVersion,
    this.downloadUrl,
    required this.fileName,
    this.plistUrl,
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

  // ── Android: download APK → open with system installer ──────────────────
  Future<void> _installAndroid() async {
    if (widget.downloadUrl == null) return;
    setState(() => _phase = _Phase.downloading);

    final client = http.Client();
    _httpClient = client;

    try {
      final request = http.Request('GET', Uri.parse(widget.downloadUrl!));
      final streamedResponse =
          await client.send(request).timeout(const Duration(minutes: 10));

      if (streamedResponse.statusCode != 200) {
        throw Exception('HTTP ${streamedResponse.statusCode}');
      }

      final totalBytes = streamedResponse.contentLength ?? 0;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.fileName}');
      final sink = file.openWrite();
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

      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done && mounted) {
        throw Exception(result.message);
      }
      // After the system installer opens, dismiss the dialog.
      if (mounted) Navigator.pop(context);
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

  // ── iOS: prefer itms-services OTA, fallback to direct IPA download ──────
  Future<void> _installIOS() async {
    setState(() => _phase = _Phase.downloading);
    try {
      if (widget.plistUrl != null) {
        // OTA install via itms-services (iOS handles download + install).
        final encoded = Uri.encodeComponent(widget.plistUrl!);
        final url =
            Uri.parse('itms-services://?action=download-manifest&url=$encoded');
        if (!await launchUrl(url)) {
          throw Exception('itms-services konnte nicht geöffnet werden');
        }
        if (mounted) Navigator.pop(context);
        return;
      }

      // No plist → download IPA ourselves, then open it.
      if (widget.downloadUrl == null) {
        throw Exception('Kein Download verfügbar');
      }

      final client = http.Client();
      _httpClient = client;

      try {
        final request = http.Request('GET', Uri.parse(widget.downloadUrl!));
        final streamedResponse =
            await client.send(request).timeout(const Duration(minutes: 10));

        if (streamedResponse.statusCode != 200) {
          throw Exception('HTTP ${streamedResponse.statusCode}');
        }

        final totalBytes = streamedResponse.contentLength ?? 0;
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/${widget.fileName}');
        final sink = file.openWrite();
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

        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done && mounted) {
          throw Exception(result.message);
        }
        if (mounted) Navigator.pop(context);
      } finally {
        _httpClient = null;
        client.close();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Phase.error;
          _errorMsg = e.toString();
        });
      }
    }
  }

  void _startUpdate() {
    if (Platform.isIOS) {
      _installIOS();
    } else {
      _installAndroid();
    }
  }

  void _retry() {
    setState(() {
      _phase = _Phase.prompt;
      _progress = 0;
      _errorMsg = '';
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Platform.isIOS ? _buildCupertino() : _buildMaterial();
  }

  // ── Material (Android) ──────────────────────────────────────────────────
  Widget _buildMaterial() {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(_title(), style: const TextStyle(color: AppTheme.textPrimary)),
      content: _content(false),
      actions: _materialActions(),
    );
  }

  List<Widget> _materialActions() {
    switch (_phase) {
      case _Phase.prompt:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Später',
                style: TextStyle(color: AppTheme.textTertiary)),
          ),
          TextButton(
            onPressed: _startUpdate,
            child: const Text('Aktualisieren',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ];
      case _Phase.downloading:
      case _Phase.installing:
        return [];
      case _Phase.error:
        return [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen',
                style: TextStyle(color: AppTheme.textTertiary)),
          ),
          TextButton(
            onPressed: _retry,
            child: const Text('Erneut versuchen',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ];
    }
  }

  // ── Cupertino (iOS) ─────────────────────────────────────────────────────
  Widget _buildCupertino() {
    return CupertinoAlertDialog(
      title: Text(_title()),
      content: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _content(true),
      ),
      actions: _cupertinoActions(),
    );
  }

  List<Widget> _cupertinoActions() {
    switch (_phase) {
      case _Phase.prompt:
        return [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Später'),
          ),
          CupertinoDialogAction(
            onPressed: _startUpdate,
            child: const Text('Aktualisieren'),
          ),
        ];
      case _Phase.downloading:
      case _Phase.installing:
        return [
          // Empty placeholder so CupertinoAlertDialog renders correctly.
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
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context),
            child: const Text('Schließen'),
          ),
          CupertinoDialogAction(
            onPressed: _retry,
            child: const Text('Erneut versuchen'),
          ),
        ];
    }
  }

  // ── Shared helpers ──────────────────────────────────────────────────────
  String _title() {
    switch (_phase) {
      case _Phase.prompt:
        return 'Update verfügbar';
      case _Phase.downloading:
        return 'Wird heruntergeladen…';
      case _Phase.installing:
        return 'Wird installiert…';
      case _Phase.error:
        return 'Update fehlgeschlagen';
    }
  }

  Widget _content(bool cupertino) {
    final secondaryStyle = cupertino
        ? null
        : const TextStyle(color: AppTheme.textSecondary, fontSize: 14);

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
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.accent),
              ),
            const SizedBox(height: 14),
            Text('Update wird vorbereitet…', style: secondaryStyle ?? const TextStyle(fontSize: 14)),
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
