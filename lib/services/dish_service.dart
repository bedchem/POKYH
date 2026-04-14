import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../models/dish.dart';

List<Dish> _parseDishesInBackground(String jsonString) {
  final decoded = jsonDecode(jsonString);
  if (decoded is Map<String, dynamic>) {
    return Dish.listFromJson(decoded);
  }
  return const [];
}

/// Daten-Strategie:
///
/// 1. Server-Fetch mit 6s Timeout → Cache speichern → UI aktualisiert sich
/// 2. Server nicht erreichbar → Cache von Disk laden
/// 3. Kein Cache → Fehler-Popup
///
/// Die lokale Cache-Datei liegt unter:
///   iOS: App/Library/Application Support/menu_cache.json
///   Android: App/files/menu_cache.json

class DishService {
  static const String _cacheFileName = 'menu_cache.json';
  static const Duration _serverTimeout = Duration(seconds: 6);
  static String? _memoryCache;

  /// Versucht Cache von der Disk zu laden. Gibt null zurück wenn kein Cache.
  Future<List<Dish>?> loadFromCache() async {
    try {
      if (_memoryCache != null && _memoryCache!.isNotEmpty) {
        final dishes = await compute(_parseDishesInBackground, _memoryCache!);
        if (dishes.isNotEmpty) {
          debugPrint('[DishService] Cache (RAM) geladen: ${dishes.length} Gerichte');
          return dishes;
        }
      }

      final file = await _getCacheFile();
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        if (jsonString.isNotEmpty) {
          _memoryCache = jsonString;
          final dishes = await compute(_parseDishesInBackground, jsonString);
          debugPrint('[DishService] Cache geladen: ${dishes.length} Gerichte');
          return dishes;
        }
      }
      debugPrint('[DishService] Kein Cache vorhanden');
    } catch (e) {
      debugPrint('[DishService] Cache-Fehler: $e');
    }
    return null;
  }

  /// Server-Fetch mit 6s Timeout.
  /// Speichert bei Erfolg automatisch in den Cache.
  /// Gibt null zurück bei Fehler/Timeout.
  Future<List<Dish>?> fetchFromServer() async {
    final url = AppConfig.mensaApiUrl;
    debugPrint('[DishService] Fetching: $url');
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'ClassByte/1.0',
        },
      ).timeout(_serverTimeout);

      debugPrint('[DishService] Response: ${response.statusCode}, body length: ${response.body.length}');

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final dishes = await compute(_parseDishesInBackground, response.body);
        if (dishes.isNotEmpty) {
          _memoryCache = response.body;
          debugPrint('[DishService] Parsed ${dishes.length} Gerichte vom Server');
          // Nicht blockierend schreiben: UI bekommt Daten sofort.
          unawaited(_saveToCache(response.body));
          return dishes;
        } else {
          debugPrint('[DishService] JSON konnte nicht in Gerichte geparst werden');
        }
      }
    } on TimeoutException {
      debugPrint('[DishService] Timeout nach ${_serverTimeout.inSeconds}s');
    } on SocketException catch (e) {
      debugPrint('[DishService] Netzwerkfehler: $e');
    } on HandshakeException catch (e) {
      debugPrint('[DishService] SSL-Fehler: $e');
    } catch (e) {
      debugPrint('[DishService] Unbekannter Fehler: $e');
    }
    return null;
  }

  /// Alten Cache löschen (z.B. nach Update)
  Future<void> clearCache() async {
    try {
      _memoryCache = null;
      final file = await _getCacheFile();
      if (await file.exists()) {
        await file.delete();
        debugPrint('[DishService] Cache gelöscht');
      }
    } catch (e) {
      debugPrint('[DishService] Cache löschen fehlgeschlagen: $e');
    }
  }

  /// JSON-String lokal auf dem Gerät speichern
  Future<void> _saveToCache(String jsonString) async {
    try {
      _memoryCache = jsonString;
      final file = await _getCacheFile();
      await file.writeAsString(jsonString);
      debugPrint('[DishService] Cache gespeichert');
    } catch (e) {
      debugPrint('[DishService] Cache speichern fehlgeschlagen: $e');
    }
  }

  /// Pfad zur Cache-Datei
  Future<File> _getCacheFile() async {
    final directory = await _resolveCacheDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}/$_cacheFileName');
  }

  Future<Directory> _resolveCacheDirectory() async {
    try {
      if ((Platform.isIOS || Platform.isMacOS) &&
          Platform.environment['HOME'] != null) {
        return Directory(
          '${Platform.environment['HOME']}/Library/Application Support/ClassByte',
        );
      }
    } catch (e) {
      debugPrint('[DishService] HOME-Pfad nicht verwendbar: $e');
    }

    // Fallback ohne platform channel (um Objective-C FFI-Probleme zu vermeiden).
    return Directory('${Directory.systemTemp.path}/classbyte_cache');
  }
}
