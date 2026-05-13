import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';

class AuthService {
  static final AuthService _instance = AuthService._();
  AuthService._();
  static AuthService get instance => _instance;

  String? _jwtToken;
  String? _refreshToken;
  String? _stableUid;
  String? _username;
  int? _klasseId;
  String? _klasseName;
  String? _classId;
  bool _isAdmin = false;
  bool _isUntisUser = true;

  // Cached prefs instance — avoids repeated getInstance() on every save.
  SharedPreferences? _prefs;

  String? get jwtToken => _jwtToken;
  String? get stableUid => _stableUid;
  String? get userId => _stableUid;
  String? get username => _username;
  int? get webuntisKlasseId => _klasseId;
  String? get webuntisKlasseName => _klasseName;
  String? get classId => _classId;
  bool get isAdmin => _isAdmin;
  bool get isUntisUser => _isUntisUser;
  bool get isSignedIn => _jwtToken != null && _stableUid != null;

  Future<SharedPreferences> _getPrefs() async {
    return _prefs ??= await SharedPreferences.getInstance();
  }

  Future<String?> resolveStableUid() async {
    if (_stableUid != null) return _stableUid;
    final prefs = await _getPrefs();
    final uid = prefs.getString('auth_stable_uid');
    if (uid != null && uid.isNotEmpty) {
      _stableUid = uid;
      return uid;
    }
    return null;
  }

  /// Login with a POKYH-only account (no WebUntis session required).
  Future<void> signInWithPassword(String username, String password) async {
    debugPrint('[AuthService] POKYH-Konto Login für "$username"...');

    final url = Uri.parse('${AppConfig.backendUrl}/auth/login');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': AppConfig.backendApiKey,
        // No X-Server-Key → backend uses local password auth
      },
      body: jsonEncode({
        'username': username.toLowerCase().trim(),
        'password': password,
      }),
    ).timeout(AppConfig.networkTimeout);

    if (response.statusCode != 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(data['error'] ?? 'Anmeldung fehlgeschlagen');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _jwtToken = data['token'] as String;
    _refreshToken = data['refreshToken'] as String;

    final user = data['user'] as Map<String, dynamic>;
    _stableUid = user['stableUid'] as String;
    _username = user['username'] as String;
    _isUntisUser = false;
    _klasseId = 0;
    _klasseName = '';
    _classId = null;
    _isAdmin = user['isAdmin'] as bool? ?? false;

    await _saveToPrefs();
    debugPrint('[AuthService] POKYH-Konto angemeldet: stableUid=$_stableUid');
  }

  Future<void> signInAnonymously(
    String username, {
    int? klasseId,
    String? klasseName,
  }) => signIn(username, klasseId: klasseId, klasseName: klasseName);

  Future<void> signIn(
    String username, {
    int? klasseId,
    String? klasseName,
  }) async {
    debugPrint('[AuthService] Anmeldung für "$username"...');

    final url = Uri.parse('${AppConfig.backendUrl}/auth/login');
    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': AppConfig.backendApiKey,
        'X-Server-Key': AppConfig.backendServerKey,
      },
      body: jsonEncode({
        'username': username.toLowerCase().trim(),
        'klasseId': klasseId ?? 0,
        'klasseName': klasseName ?? '',
      }),
    ).timeout(AppConfig.networkTimeout);

    if (response.statusCode != 200) {
      throw Exception('Backend Auth fehlgeschlagen: ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _jwtToken = data['token'] as String;
    _refreshToken = data['refreshToken'] as String;

    final user = data['user'] as Map<String, dynamic>;
    _stableUid = user['stableUid'] as String;
    _username = user['username'] as String;
    _klasseId = (user['webuntisKlasseId'] as num?)?.toInt();
    _klasseName = user['webuntisKlasseName'] as String?;
    _classId = user['classId'] as String?;
    _isAdmin = user['isAdmin'] as bool? ?? false;
    _isUntisUser = true;

    await _saveToPrefs();
    debugPrint('[AuthService] Angemeldet: stableUid=$_stableUid classId=$_classId isAdmin=$_isAdmin');
  }

  Future<bool> refreshJwt() async {
    final token = _refreshToken;
    if (token == null) return false;
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.backendUrl}/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'X-API-Key': AppConfig.backendApiKey,
        },
        body: jsonEncode({'refreshToken': token}),
      ).timeout(AppConfig.networkTimeout);
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      _jwtToken = data['token'] as String;
      await _saveToPrefs();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      final refresh = _refreshToken;
      final jwt = _jwtToken;
      if (refresh != null && jwt != null) {
        await http.post(
          Uri.parse('${AppConfig.backendUrl}/auth/logout'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $jwt',
          },
          body: jsonEncode({'refreshToken': refresh}),
        ).timeout(AppConfig.networkTimeout);
      }
    } catch (_) {}
    _clear();
    final prefs = await _getPrefs();
    await Future.wait(_prefKeys.map((k) => prefs.remove(k)));
  }

  Future<bool> restoreSession() async {
    final prefs = await _getPrefs();
    final jwt = prefs.getString('auth_jwt_token');
    final refresh = prefs.getString('auth_refresh_token');
    if (jwt == null || refresh == null) return false;
    _jwtToken = jwt;
    _refreshToken = refresh;
    _stableUid = prefs.getString('auth_stable_uid');
    _username = prefs.getString('auth_username');
    _klasseId = prefs.getInt('auth_klasse_id');
    _klasseName = prefs.getString('auth_klasse_name');
    _classId = prefs.getString('auth_class_id');
    _isAdmin = prefs.getBool('auth_is_admin') ?? false;
    _isUntisUser = prefs.getBool('auth_is_untis_user') ?? true;
    return _stableUid != null;
  }

  void _clear() {
    _jwtToken = null;
    _refreshToken = null;
    _stableUid = null;
    _username = null;
    _klasseId = null;
    _klasseName = null;
    _classId = null;
    _isAdmin = false;
    _isUntisUser = true;
  }

  static const _prefKeys = [
    'auth_jwt_token',
    'auth_refresh_token',
    'auth_stable_uid',
    'auth_username',
    'auth_klasse_id',
    'auth_klasse_name',
    'auth_class_id',
    'auth_is_admin',
    'auth_is_untis_user',
  ];

  Future<void> _saveToPrefs() async {
    final prefs = await _getPrefs();
    // Write all keys in parallel.
    await Future.wait([
      if (_jwtToken != null) prefs.setString('auth_jwt_token', _jwtToken!),
      if (_refreshToken != null) prefs.setString('auth_refresh_token', _refreshToken!),
      if (_stableUid != null) prefs.setString('auth_stable_uid', _stableUid!),
      if (_username != null) prefs.setString('auth_username', _username!),
      if (_klasseId != null) prefs.setInt('auth_klasse_id', _klasseId!),
      if (_klasseName != null) prefs.setString('auth_klasse_name', _klasseName!),
      if (_classId != null) prefs.setString('auth_class_id', _classId!),
      prefs.setBool('auth_is_admin', _isAdmin),
      prefs.setBool('auth_is_untis_user', _isUntisUser),
    ]);
  }
}
