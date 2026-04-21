import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../utils/error_message.dart';

class WebUntisException implements Exception {
  final String message;
  final bool isAuthError;
  WebUntisException(this.message, {this.isAuthError = false});
  @override
  String toString() => message;
}

class WebUntisService {
  static const String _baseUrl = AppConfig.webUntisBaseUrl;
  static const String _school = AppConfig.webUntisSchool;
  static const String _schoolNameCookie = AppConfig.webUntisSchoolNameCookie;
  static const Duration _timeout = AppConfig.networkTimeout;
  static const Duration _timetableTTL = AppConfig.timetableCacheTTL;
  static const Duration _gradesTTL = AppConfig.gradesCacheTTL;

  // Persistent HTTP client — reuses TCP/TLS connections across requests.
  final http.Client _client = http.Client();

  String? _sessionId;
  String? _bearerToken;
  int? _studentId;
  int? _klasseId;
  String? _klasseName;
  int? _schoolYearId;
  List<TimeGridUnit>? _timeGrid;
  String? _username;

  bool get isLoggedIn => _sessionId != null && _studentId != null;
  String? get username => _username;
  int? get studentId => _studentId;
  int? get klasseId => _klasseId;
  String? get klasseName => _klasseName;
  String get persistenceScopeKey {
    final id = _studentId;
    if (id != null) return 'student_$id';

    final name = _username?.trim().toLowerCase();
    if (name != null && name.isNotEmpty) {
      final normalized = name.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      return 'user_$normalized';
    }

    return 'anonymous';
  }

  /// Profile image cache
  Uint8List? _profileImageBytes;
  bool _profileImageFetched = false;

  String? get profileImageUrl {
    if (_studentId == null || _sessionId == null) return null;
    return '$_baseUrl/api/portrait/students/$_studentId?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Uint8List? get profileImageBytes => _profileImageBytes;
  bool get profileImageFetched => _profileImageFetched;

  Future<Uint8List?> fetchProfileImage() async {
    if (_studentId == null || _sessionId == null) return null;
    try {
      final url = '$_baseUrl/api/portrait/students/$_studentId';
      final response = await _client
          .get(Uri.parse(url), headers: {'Cookie': _cookieHeader})
          .timeout(const Duration(seconds: 10));

      _profileImageFetched = true;
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        _profileImageBytes = response.bodyBytes;
        return _profileImageBytes;
      }
      _profileImageBytes = null;
      return null;
    } catch (_) {
      _profileImageFetched = true;
      _profileImageBytes = null;
      return null;
    }
  }

  String get cookieHeader => _cookieHeader;

  String get _cookieHeader =>
      'JSESSIONID=${_sessionId ?? ""}; schoolname="$_schoolNameCookie"';

  // ── Timetable in-memory cache ─────────────────────────────────────────────

  final Map<String, _CachedData<List<TimetableEntry>>> _timetableCache = {};

  /// Returns cached timetable for the given week start, or null if expired/missing.
  List<TimetableEntry>? getCachedWeek(DateTime weekStart) {
    final key = _weekKey(weekStart);
    final cached = _timetableCache[key];
    if (cached == null || cached.isExpired(_timetableTTL)) return null;
    return cached.data;
  }

  void _cacheTimetable(DateTime weekStart, List<TimetableEntry> entries) {
    _timetableCache[_weekKey(weekStart)] = _CachedData(entries);
    _saveTimetableDiskCache(weekStart, entries);
  }

  String _weekKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Grades in-memory cache ────────────────────────────────────────────────

  _CachedData<List<SubjectGrades>>? _gradesCache;

  List<SubjectGrades>? get cachedGrades {
    final c = _gradesCache;
    if (c == null || c.isExpired(_gradesTTL)) return null;
    return c.data;
  }

  // ── Absences in-memory cache ──────────────────────────────────────────────

  _CachedData<List<AbsenceEntry>>? _absencesCache;

  List<AbsenceEntry>? get cachedAbsences {
    final c = _absencesCache;
    if (c == null || c.isExpired(_gradesTTL)) return null;
    return c.data;
  }

  void _clearCaches() {
    _timetableCache.clear();
    _gradesCache = null;
    _messagesCache = null;
    _absencesCache = null;
  }

  // ── AUTH ──────────────────────────────────────────────────────────────────

  Future<bool> login(String username, String password) async {
    try {
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/jsonrpc.do?school=$_school'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'id': '1',
              'method': 'authenticate',
              'params': {
                'user': username,
                'password': password,
                'client': 'pockyh',
              },
            }),
          )
          .timeout(_timeout);

      if (response.statusCode != 200) return false;

      final data = _parseJsonResponse(response.body);
      if (data['result'] == null) return false;

      final result = data['result'];
      _sessionId = result['sessionId'];
      _studentId = result['personId'];
      _klasseId = result['klasseId'];
      _username = username;

      final setCookie = response.headers['set-cookie'];
      if (setCookie != null) {
        final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(setCookie);
        if (match != null) _sessionId = match.group(1);
      }

      // Run all init calls in parallel.
      await Future.wait([
        _fetchBearerToken(),
        _fetchSchoolYear(),
        _fetchTimeGrid(),
        _fetchKlasseName(),
      ]);

      await saveSession();
      await _loadReadMessageIds();

      return true;
    } on TimeoutException {
      throw WebUntisException(
        'Verbindung abgelaufen. Bitte versuche es erneut.',
      );
    } catch (e) {
      if (e is WebUntisException) rethrow;
      throw WebUntisException('Netzwerkfehler: ${simplifyErrorMessage(e)}');
    }
  }

  Future<void> _fetchBearerToken() async {
    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/api/token/new'),
            headers: {'Cookie': _cookieHeader},
          )
          .timeout(_timeout);

      if (response.statusCode == 200) {
        final candidate = response.body.trim().replaceAll('"', '');
        // Only store it if it looks like a real JWT, not an HTML error page.
        if (_isValidBearerToken(candidate)) {
          _bearerToken = candidate;
        }
      }
    } catch (_) {}
  }

  static bool _isValidBearerToken(String? token) {
    if (token == null || token.isEmpty) return false;
    if (token.contains('<') || token.contains('\n') || token.contains('\r')) {
      return false;
    }
    // A JWT has exactly two dots separating three base64url segments.
    return token.contains('.');
  }

  Future<void> _fetchSchoolYear() async {
    try {
      final result = await _rpc('getCurrentSchoolyear', {});
      if (result is Map) {
        _schoolYearId = result['id'] as int?;
      }
    } catch (_) {}
  }

  Future<void> _fetchTimeGrid() async {
    try {
      final result = await _rpc('getTimegridUnits', {});
      if (result is List && result.isNotEmpty) {
        final units = result[0]['timeUnits'] as List? ?? [];
        _timeGrid = units
            .map(
              (u) => TimeGridUnit(
                name: u['name']?.toString() ?? '',
                startTime: u['startTime'] ?? 0,
                endTime: u['endTime'] ?? 0,
              ),
            )
            .toList();
      }
    } catch (_) {}
  }

  Future<void> _fetchKlasseName() async {
    if (_klasseId == null) return;
    try {
      final result = await _rpc('getKlassen', {});
      if (result is List) {
        for (final klasse in result) {
          if (klasse['id'] == _klasseId) {
            _klasseName = klasse['name']?.toString();
            break;
          }
        }
      }
    } catch (_) {}
  }

  Future<bool> validateSession() async {
    final prefs = await SharedPreferences.getInstance();
    final lastActiveMs = prefs.getInt(_kSessionLastActiveTimeKey);
    if (lastActiveMs != null &&
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(lastActiveMs),
            ) >=
            _sessionExpirationAfterClose) {
      await clearSession();
      return false;
    }

    if (_sessionId == null) return false;
    try {
      await _rpc('getCurrentSchoolyear', {});
      return true;
    } on WebUntisException catch (e) {
      return !e.isAuthError;
    } catch (_) {
      return true;
    }
  }

  List<TimeGridUnit> get timeGrid => _timeGrid ?? [];

  String? getLessonNumber(int startTime) {
    if (_timeGrid == null) return null;
    for (final unit in _timeGrid!) {
      if (unit.startTime == startTime) return unit.name;
    }
    return null;
  }

  Future<void> logout() async {
    try {
      if (_sessionId != null) {
        await _client
            .post(
              Uri.parse('$_baseUrl/jsonrpc.do?school=$_school'),
              headers: {
                'Content-Type': 'application/json',
                'Cookie': _cookieHeader,
              },
              body: jsonEncode({
                'jsonrpc': '2.0',
                'id': '1',
                'method': 'logout',
                'params': {},
              }),
            )
            .timeout(const Duration(seconds: 5));
      }
    } catch (_) {}
    _sessionId = null;
    _studentId = null;
    _bearerToken = null;
    _klasseId = null;
    _klasseName = null;
    _schoolYearId = null;
    _profileImageBytes = null;
    _profileImageFetched = false;
    _clearCaches();
    await clearSession();
  }

  // ── SESSION PERSISTENCE ───────────────────────────────────────────────────

  static const String _kSessionLastActiveTimeKey =
      'session_last_active_time_v1';
  static const Duration _sessionExpirationAfterClose = Duration(minutes: 1);

  Future<void> _touchLastActiveTime([SharedPreferences? prefs]) async {
    final instance = prefs ?? await SharedPreferences.getInstance();
    await instance.setInt(
      _kSessionLastActiveTimeKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<void> saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_sessionId != null) await prefs.setString('sessionId', _sessionId!);
    if (_studentId != null) await prefs.setInt('studentId', _studentId!);
    if (_bearerToken != null) {
      await prefs.setString('bearerToken', _bearerToken!);
    }
    if (_klasseId != null) await prefs.setInt('klasseId', _klasseId!);
    if (_klasseName != null) await prefs.setString('klasseName', _klasseName!);
    if (_schoolYearId != null) {
      await prefs.setInt('schoolYearId', _schoolYearId!);
    }
    if (_username != null) await prefs.setString('username', _username!);
    await _touchLastActiveTime(prefs);
  }

  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _sessionId = prefs.getString('sessionId');
      _studentId = prefs.getInt('studentId');
      _bearerToken = prefs.getString('bearerToken');
      _klasseId = prefs.getInt('klasseId');
      _klasseName = prefs.getString('klasseName');
      _schoolYearId = prefs.getInt('schoolYearId');
      _username = prefs.getString('username');

      if (_sessionId == null || _studentId == null) return false;

      final lastActiveMs = prefs.getInt(_kSessionLastActiveTimeKey);
      if (lastActiveMs != null &&
          DateTime.now().difference(
                DateTime.fromMillisecondsSinceEpoch(lastActiveMs),
              ) >=
              _sessionExpirationAfterClose) {
        await clearSession();
        return false;
      }

      // Pre-warm caches from disk immediately — no network needed.
      _loadGradesDiskCache(prefs);
      _loadTimetableDiskCache(prefs);
      await _loadReadMessageIds();
      await _touchLastActiveTime(prefs);

      // Refresh bearer token in the background so the first timetable load
      // is not blocked. If the saved bearer is still valid it will be used
      // right away; the fresh one replaces it once available.
      _fetchBearerToken().then((_) => saveSession()).ignore();

      // Trust the stored session — no validation network call on startup.
      // If the session has actually expired the first real API call will
      // return a 401 and the screen redirects to login automatically.
      return true;
    } catch (_) {
      await clearSession();
      return false;
    }
  }

  Future<void> clearSession() async {
    _sessionId = null;
    _studentId = null;
    _bearerToken = null;
    _klasseId = null;
    _klasseName = null;
    _schoolYearId = null;
    _username = null;
    _readMessageIds = {};
    _clearCaches();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('sessionId');
    await prefs.remove('studentId');
    await prefs.remove('bearerToken');
    await prefs.remove('klasseId');
    await prefs.remove('klasseName');
    await prefs.remove('schoolYearId');
    await prefs.remove('username');
    await prefs.remove(_kSessionLastActiveTimeKey);
  }

  // ── TIMETABLE ─────────────────────────────────────────────────────────────

  Future<List<TimetableEntry>> getWeekTimetable({DateTime? weekStart}) async {
    final start = weekStart ?? _getMonday(DateTime.now());

    // Return from cache if still fresh.
    final cached = getCachedWeek(start);
    if (cached != null) return cached;

    final dateStr =
        '${start.year}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';

    try {
      final response = await _client
          .get(
            Uri.parse(
              '$_baseUrl/api/public/timetable/weekly/data?elementType=5&elementId=$_studentId&date=$dateStr&formatId=1',
            ),
            headers: {'Cookie': _cookieHeader},
          )
          .timeout(_timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw WebUntisException('Sitzung abgelaufen', isAuthError: true);
      }

      if (response.statusCode != 200) {
        throw WebUntisException('Fehler beim Laden des Stundenplans');
      }

      final data = _parseJsonResponse(response.body);
      final resultData = data['data']?['result']?['data'];
      if (resultData == null) {
        _cacheTimetable(start, []);
        return [];
      }

      final elements = resultData['elements'] as List? ?? [];
      final elementMap = <String, Map<String, dynamic>>{};
      for (final e in elements) {
        final type = e['type'];
        final id = e['id'];
        elementMap['$type-$id'] = Map<String, dynamic>.from(e);
      }

      final periodsMap =
          resultData['elementPeriods'] as Map<String, dynamic>? ?? {};
      final periods = periodsMap['$_studentId'] as List? ?? [];

      final entries = <TimetableEntry>[];
      for (final p in periods) {
        entries.add(TimetableEntry.fromWeeklyApi(p, elementMap));
      }

      entries.sort((a, b) {
        final dateComp = a.date.compareTo(b.date);
        return dateComp != 0 ? dateComp : a.startTime.compareTo(b.startTime);
      });

      _cacheTimetable(start, entries);
      return entries;
    } on TimeoutException {
      throw WebUntisException('Verbindung abgelaufen');
    } catch (e) {
      if (e is WebUntisException) rethrow;
      throw WebUntisException('Netzwerkfehler: ${simplifyErrorMessage(e)}');
    }
  }

  Future<List<TimetableEntry>> getTimetable({DateTime? date}) async {
    final target = date ?? DateTime.now();
    final monday = _getMonday(target);
    final entries = await getWeekTimetable(weekStart: monday);
    final targetInt = _dateToInt(target);
    return entries.where((e) => e.date == targetInt).toList();
  }

  // ── GRADES ────────────────────────────────────────────────────────────────

  Future<List<SubjectGrades>> getAllGrades({bool forceRefresh = false}) async {
    if (_studentId == null || _bearerToken == null) {
      throw WebUntisException('Nicht angemeldet oder kein Token');
    }

    // Return memory-cached data if still fresh and not forced.
    if (!forceRefresh) {
      final mem = cachedGrades;
      if (mem != null) return mem;
    }

    if (_schoolYearId == null) {
      await _fetchSchoolYear();
      if (_schoolYearId == null) {
        throw WebUntisException('Schuljahr konnte nicht ermittelt werden');
      }
    }

    try {
      // Step 1: fetch lesson list.
      final listResponse = await _client
          .get(
            Uri.parse(
              '$_baseUrl/api/classreg/grade/grading/list?studentId=$_studentId&schoolyearId=$_schoolYearId',
            ),
            headers: {
              'Authorization': 'Bearer $_bearerToken',
              'Cookie': _cookieHeader,
            },
          )
          .timeout(const Duration(seconds: 20));

      if (listResponse.statusCode == 401 || listResponse.statusCode == 403) {
        throw WebUntisException('Sitzung abgelaufen', isAuthError: true);
      }

      if (listResponse.statusCode != 200) {
        throw WebUntisException('Fehler beim Laden der Notenliste');
      }

      final listData = jsonDecode(listResponse.body);
      final lessons = listData['data']?['lessons'] as List? ?? [];

      if (lessons.isEmpty) return [];

      // Step 2: fetch all lesson grades IN PARALLEL — was sequential before.
      final futures = lessons.map((lesson) => _fetchLessonGrades(lesson));
      final fetched = await Future.wait(futures);

      final results = fetched.whereType<SubjectGrades>().toList();
      results.sort((a, b) => a.subjectName.compareTo(b.subjectName));

      // Update memory cache.
      _gradesCache = _CachedData(results);

      // Persist to disk for next cold launch.
      _saveGradesDiskCache(results);

      return results;
    } on TimeoutException {
      throw WebUntisException('Verbindung abgelaufen');
    } catch (e) {
      if (e is WebUntisException) rethrow;
      throw WebUntisException(
        'Fehler beim Laden der Noten: ${simplifyErrorMessage(e)}',
      );
    }
  }

  Future<SubjectGrades?> _fetchLessonGrades(Map<String, dynamic> lesson) async {
    final lessonId = lesson['id'];
    final subjectName = lesson['subjects'] ?? '';
    final teacherName = lesson['teachers'] ?? '';
    try {
      final response = await _client
          .get(
            Uri.parse(
              '$_baseUrl/api/classreg/grade/grading/lesson?studentId=$_studentId&lessonId=$lessonId',
            ),
            headers: {
              'Authorization': 'Bearer $_bearerToken',
              'Cookie': _cookieHeader,
            },
          )
          .timeout(_timeout);

      if (response.statusCode != 200) return null;

      final gradeData = _parseJsonResponse(response.body);
      final grades = gradeData['data']?['grades'] as List? ?? [];

      final gradeEntries = grades
          .map((g) => GradeEntry.fromJson(g))
          .where((g) => g.markValue > 0)
          .toList();

      gradeEntries.sort((a, b) => a.date.compareTo(b.date));

      return SubjectGrades(
        lessonId: lessonId,
        subjectName: subjectName,
        teacherName: teacherName,
        grades: gradeEntries,
      );
    } catch (_) {
      return null;
    }
  }

  // ── ABSENCES ─────────────────────────────────────────────────────────────

  Future<List<AbsenceEntry>> getAbsences({bool forceRefresh = false}) async {
    if (_studentId == null) {
      throw WebUntisException('Nicht angemeldet', isAuthError: true);
    }

    // Refresh the token if missing or stale (e.g. stored HTML from a prior expired session).
    if (!_isValidBearerToken(_bearerToken)) {
      await _fetchBearerToken();
    }
    if (!_isValidBearerToken(_bearerToken)) {
      throw WebUntisException('Sitzung abgelaufen', isAuthError: true);
    }

    if (!forceRefresh) {
      final mem = cachedAbsences;
      if (mem != null) return mem;
    }

    final now = DateTime.now();
    final startYear = now.month >= 9 ? now.year : now.year - 1;
    final startDate = '${startYear}0901';
    final endDate =
        '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';

    try {
      final response = await _client
          .get(
            Uri.parse(
              '$_baseUrl/api/classreg/absences/students?studentId=$_studentId&startDate=$startDate&endDate=$endDate&excuseStatusId=-1',
            ),
            headers: {
              'Authorization': 'Bearer $_bearerToken',
              'Cookie': _cookieHeader,
            },
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw WebUntisException('Sitzung abgelaufen', isAuthError: true);
      }

      if (response.statusCode != 200) {
        throw WebUntisException('Fehler beim Laden der Abwesenheiten');
      }

      final body = _parseJsonResponse(response.body);
      final data = body['data'];
      final List raw =
          (data is Map ? (data['absences'] ?? data['absence'] ?? data) : body)
              as List? ??
          [];

      final entries = raw
          .whereType<Map<String, dynamic>>()
          .map(AbsenceEntry.fromJson)
          .toList();

      entries.sort((a, b) => b.startDate.compareTo(a.startDate));

      _absencesCache = _CachedData(entries);
      return entries;
    } on TimeoutException {
      throw WebUntisException('Verbindung abgelaufen');
    } on FormatException {
      throw WebUntisException('Sitzung abgelaufen', isAuthError: true);
    } catch (e) {
      if (e is WebUntisException) rethrow;
      throw WebUntisException(
        'Fehler beim Laden der Abwesenheiten: ${simplifyErrorMessage(e)}',
      );
    }
  }

  // ── HOMEWORK ──────────────────────────────────────────────────────────────

  final Map<String, _CachedData<List<HomeworkEntry>>> _homeworkCache = {};

  /// Returns homework for the week containing [weekStart].
  /// Keyed by the Monday date string; expires with the same TTL as the timetable.
  Future<List<HomeworkEntry>> getHomework({DateTime? weekStart}) async {
    final start = weekStart ?? _getMonday(DateTime.now());
    final key = _weekKey(start);

    final cached = _homeworkCache[key];
    if (cached != null && !cached.isExpired(_timetableTTL)) return cached.data;

    try {
      final end = start.add(const Duration(days: 6));
      final startStr =
          '${start.year}${start.month.toString().padLeft(2, '0')}${start.day.toString().padLeft(2, '0')}';
      final endStr =
          '${end.year}${end.month.toString().padLeft(2, '0')}${end.day.toString().padLeft(2, '0')}';

      final response = await _client
          .get(
            Uri.parse(
              '$_baseUrl/api/homeworks/lessons?startDate=$startStr&endDate=$endStr',
            ),
            headers: {'Cookie': _cookieHeader},
          )
          .timeout(_timeout);

      if (response.statusCode != 200) {
        _homeworkCache[key] = _CachedData([]);
        return [];
      }

      final data = _parseJsonResponse(response.body);
      final list = data['data']?['homeworks'] as List? ?? [];
      final entries = list
          .map((h) => HomeworkEntry.fromJson(h as Map<String, dynamic>))
          .toList();

      _homeworkCache[key] = _CachedData(entries);
      return entries;
    } catch (_) {
      _homeworkCache[key] = _CachedData([]);
      return [];
    }
  }

  // ── MESSAGES ──────────────────────────────────────────────────────────────

  _CachedData<List<MessagePreview>>? _messagesCache;
  static const Duration _messagesTTL = AppConfig.messagesCacheTTL;
  Set<int> _readMessageIds = {};

  List<MessagePreview>? get cachedMessages => _messagesCache?.data;

  int get unreadMessageCount =>
      (_messagesCache?.data ?? []).where((m) => !m.isRead).length;

  Future<List<MessagePreview>> getMessages({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached = _messagesCache;
      if (cached != null && !cached.isExpired(_messagesTTL)) return cached.data;
    }

    if (_bearerToken == null) {
      throw WebUntisException('Nicht angemeldet', isAuthError: true);
    }

    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/api/rest/view/v1/messages'),
            headers: {
              'Authorization': 'Bearer $_bearerToken',
              'Cookie': _cookieHeader,
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw WebUntisException('Sitzung abgelaufen', isAuthError: true);
      }

      if (response.statusCode != 200) {
        throw WebUntisException('Fehler beim Laden der Mitteilungen');
      }

      final data = _parseJsonResponse(response.body);
      final messages = _applyLocalReadState(_parseMessageList(data));
      _messagesCache = _CachedData(messages);
      return messages;
    } on TimeoutException {
      throw WebUntisException('Verbindung abgelaufen');
    } catch (e) {
      if (e is WebUntisException) rethrow;
      throw WebUntisException(
        'Fehler beim Laden der Mitteilungen: ${simplifyErrorMessage(e)}',
      );
    }
  }

  Future<MessageDetail> getMessageDetail(int messageId) async {
    if (_bearerToken == null) {
      throw WebUntisException('Nicht angemeldet', isAuthError: true);
    }

    try {
      final response = await _client
          .get(
            Uri.parse('$_baseUrl/api/rest/view/v1/messages/$messageId'),
            headers: {
              'Authorization': 'Bearer $_bearerToken',
              'Cookie': _cookieHeader,
            },
          )
          .timeout(_timeout);

      if (response.statusCode == 401 || response.statusCode == 403) {
        throw WebUntisException('Sitzung abgelaufen', isAuthError: true);
      }

      if (response.statusCode != 200) {
        throw WebUntisException('Fehler beim Laden der Nachricht');
      }

      final data = _parseJsonResponse(response.body);
      // Unwrap server envelope: {"data": {...}} → use inner map.
      final Map<String, dynamic> messageJson;
      if (data is Map<String, dynamic>) {
        messageJson = (data['data'] as Map<String, dynamic>?) ?? data;
      } else {
        messageJson = {};
      }
      final detail = MessageDetail.fromJson(messageJson);

      // Mark as read locally in the cached list
      await _markReadInCache(messageId);

      return detail.copyWith(
        isRead: _readMessageIds.contains(messageId) || detail.isRead,
      );
    } on TimeoutException {
      throw WebUntisException('Verbindung abgelaufen');
    } catch (e) {
      if (e is WebUntisException) rethrow;
      throw WebUntisException(
        'Fehler beim Laden der Nachricht: ${simplifyErrorMessage(e)}',
      );
    }
  }

  /// Fetches the attachment list for a message separately.
  /// Used as a fallback when the detail endpoint returns no attachments
  /// but the list endpoint indicates attachments exist.
  Future<List<MessageAttachment>> getMessageAttachments(int messageId) async {
    if (_bearerToken == null) return [];

    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'Cookie': _cookieHeader,
    };

    final urls = [
      '$_baseUrl/api/rest/view/v1/messages/$messageId/attachments',
      // Some servers only include file metadata in the message detail payload.
      '$_baseUrl/api/rest/view/v1/messages/$messageId',
    ];

    try {
      for (final url in urls) {
        final response = await _client
            .get(Uri.parse(url), headers: headers)
            .timeout(_timeout);

        if (response.statusCode == 401 || response.statusCode == 403) {
          return [];
        }
        if (response.statusCode != 200) {
          continue;
        }

        final data = _parseJsonResponse(response.body);
        final list = _extractAttachmentList(data);
        if (list.isEmpty) continue;

        return list
            .whereType<Map>()
            .map(
              (a) => MessageAttachment.fromJson(Map<String, dynamic>.from(a)),
            )
            .toList();
      }

      return [];
    } catch (_) {
      return [];
    }
  }

  List<dynamic> _extractAttachmentList(dynamic raw) {
    if (raw is List) return raw;
    if (raw is! Map) return const [];

    List<dynamic>? listFrom(dynamic source) {
      if (source is List) return source;
      if (source is! Map) return null;

      const keys = [
        'attachments',
        'messageFile',
        'files',
        'fileAttachments',
        'attachment',
        'items',
        'content',
      ];

      for (final k in keys) {
        final v = source[k];
        if (v is List) return v;
      }

      final data = source['data'];
      if (data is List) return data;
      if (data is Map) {
        final nested = listFrom(data);
        if (nested != null) return nested;
      }

      final result = source['result'];
      if (result is Map) {
        final nested = listFrom(result);
        if (nested != null) return nested;
      }

      return null;
    }

    return listFrom(raw) ?? const [];
  }

  /// Downloads an attachment and saves it to the temp directory.
  /// Returns the local file path ready for opening with open_filex.
  ///
  /// Tries URLs in order:
  ///   1. [directUrl]  — if the API returned a ready-made download URL
  ///   2. /messages/{id}/attachments/{attachmentId}
  ///   3. /messages/{id}/attachments/{attachmentId}/content
  Future<String> downloadAttachment({
    required int messageId,
    required int attachmentId,
    required String fileName,
    String? directUrl,
    String? storageId,
  }) async {
    if (!_isValidBearerToken(_bearerToken)) {
      await _fetchBearerToken();
    }
    if (_bearerToken == null) {
      throw WebUntisException('Nicht angemeldet', isAuthError: true);
    }

    final baseUri = Uri.parse(_baseUrl.endsWith('/') ? _baseUrl : '$_baseUrl/');

    String? normalizedDirectUrl;
    if (directUrl != null && directUrl.trim().isNotEmpty) {
      final trimmed = directUrl.trim();
      normalizedDirectUrl = trimmed.startsWith('http')
          ? trimmed
          : baseUri.resolve(trimmed).toString();
    }

    final candidates = <String>[];
    if (normalizedDirectUrl != null) {
      candidates.add(normalizedDirectUrl);
    }

    if (storageId != null && storageId.isNotEmpty) {
      candidates.add(
        '$_baseUrl/api/rest/view/v1/messages/$messageId/attachments/$storageId',
      );
      candidates.add(
        '$_baseUrl/api/rest/view/v1/messages/$messageId/attachments/$storageId/content',
      );
      candidates.add(
        '$_baseUrl/api/rest/view/v1/messages/$messageId/storage/$storageId',
      );
    }

    if (attachmentId > 0) {
      candidates.add(
        '$_baseUrl/api/rest/view/v1/messages/$messageId/attachments/$attachmentId',
      );
      candidates.add(
        '$_baseUrl/api/rest/view/v1/messages/$messageId/attachments/$attachmentId/content',
      );
    }

    if (candidates.isEmpty) {
      throw WebUntisException('Anhang hat keine gueltige Download-URL/ID');
    }

    final headers = {
      'Authorization': 'Bearer $_bearerToken',
      'Cookie': _cookieHeader,
    };

    // Encrypted S3 downloads may require a signed storage URL plus custom headers.
    if (storageId != null && storageId.isNotEmpty) {
      try {
        final infoUrl =
            '$_baseUrl/api/rest/view/v1/messages/$messageId/attachmentstorageurl';
        final infoResponse = await _client
            .get(Uri.parse(infoUrl), headers: headers)
            .timeout(AppConfig.downloadTimeout);

        if (infoResponse.statusCode == 200) {
          final infoJson = jsonDecode(infoResponse.body);
          final downloadUrl = infoJson['downloadUrl']?.toString();
          final additionalHeaders = infoJson['additionalHeaders'] as List?;

          if (downloadUrl != null && downloadUrl.isNotEmpty) {
            final request = http.Request('GET', Uri.parse(downloadUrl));

            if (additionalHeaders != null) {
              for (final item in additionalHeaders) {
                if (item is Map) {
                  item.forEach((key, value) {
                    if (key is String && value != null) {
                      request.headers[key] = value.toString();
                    }
                  });
                }
              }
            }

            final streamResponse = await request.send().timeout(
              AppConfig.downloadTimeout,
            );
            if (streamResponse.statusCode == 200) {
              final bytes = await streamResponse.stream.toBytes();
              if (bytes.isNotEmpty) {
                final dir = await getTemporaryDirectory();
                final safeName = fileName.replaceAll(
                  RegExp(r'[/\\:*?"<>|]'),
                  '_',
                );
                final file = File('${dir.path}/$safeName');
                await file.writeAsBytes(bytes);
                return file.path;
              }
            }
          }
        }
      } catch (_) {
        // Continue with fallback URL candidates.
      }
    }

    http.Response? lastResponse;
    for (final urlString in candidates) {
      try {
        final response = await _client
            .get(Uri.parse(urlString), headers: headers)
            .timeout(AppConfig.downloadTimeout);

        if (response.statusCode == 401 || response.statusCode == 403) {
          throw WebUntisException('Sitzung abgelaufen', isAuthError: true);
        }

        final contentType = response.headers['content-type'] ?? '';
        if (response.statusCode == 200 &&
            !contentType.contains('text/html') &&
            response.bodyBytes.isNotEmpty) {
          final dir = await getTemporaryDirectory();
          final safeName = fileName.replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
          final file = File('${dir.path}/$safeName');
          await file.writeAsBytes(response.bodyBytes);
          return file.path;
        }

        lastResponse = response;
      } on WebUntisException {
        rethrow;
      } on TimeoutException {
        throw WebUntisException('Verbindung abgelaufen');
      } catch (_) {
        // Network error on this candidate — try the next one.
      }
    }

    if (lastResponse != null) {
      final ct = lastResponse.headers['content-type'] ?? '';
      if (ct.contains('text/html')) {
        throw WebUntisException(
          'Anhang nicht verfügbar – bitte neu anmelden',
          isAuthError: true,
        );
      }
      throw WebUntisException(
        'Anhang konnte nicht geladen werden (HTTP ${lastResponse.statusCode})',
      );
    }
    throw WebUntisException('Anhang konnte nicht heruntergeladen werden');
  }

  Future<void> markMessageAsRead(int messageId) async {
    if (_bearerToken == null) return;

    try {
      await _client
          .post(
            Uri.parse(
              '$_baseUrl/api/rest/view/v1/messages/$messageId/markasread',
            ),
            headers: {
              'Authorization': 'Bearer $_bearerToken',
              'Cookie': _cookieHeader,
            },
          )
          .timeout(_timeout);

      await _markReadInCache(messageId);
    } catch (_) {}
  }

  Future<void> _markReadInCache(int messageId) async {
    if (_readMessageIds.add(messageId)) {
      await _saveReadMessageIds();
    }

    final cached = _messagesCache?.data;
    if (cached == null) return;
    final updated = cached.map((m) {
      if (m.id == messageId && !m.isRead) {
        return MessagePreview(
          id: m.id,
          subject: m.subject,
          contentPreview: m.contentPreview,
          senderName: m.senderName,
          senderId: m.senderId,
          sentDate: m.sentDate,
          isRead: true,
          hasAttachments: m.hasAttachments,
          recipientGroup: m.recipientGroup,
        );
      }
      return m;
    }).toList();
    _messagesCache = _CachedData(updated);
  }

  List<MessagePreview> _applyLocalReadState(List<MessagePreview> messages) {
    if (_readMessageIds.isEmpty) return messages;
    return messages
        .map(
          (m) => _readMessageIds.contains(m.id) ? m.copyWith(isRead: true) : m,
        )
        .toList();
  }

  String get _readIdsKey =>
      'message_read_ids_v1_${AppConfig.webUntisSchool}_$persistenceScopeKey';

  Future<void> _loadReadMessageIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_readIdsKey);
      if (saved == null) {
        _readMessageIds = {};
        return;
      }

      _readMessageIds = saved
          .map((s) => int.tryParse(s))
          .whereType<int>()
          .where((id) => id > 0)
          .toSet();
    } catch (_) {
      _readMessageIds = {};
    }
  }

  Future<void> _saveReadMessageIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _readIdsKey,
        (_readMessageIds.map((id) => id.toString()).toList()..sort()),
      );
    } catch (_) {}
  }

  List<MessagePreview> _parseMessageList(dynamic data) {
    List<dynamic> messageList = [];

    if (data is List) {
      messageList = data;
    } else if (data is Map) {
      // Handle various WebUntis response wrappers
      messageList =
          (data['incomingMessages'] as List?) ??
          (data['messages'] as List?) ??
          (data['data']?['incomingMessages'] as List?) ??
          (data['data']?['messages'] as List?) ??
          (data['data'] is List ? data['data'] as List : []);
    }

    return messageList
        .map((m) => MessagePreview.fromJson(m as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => b.sentDate.compareTo(a.sentDate));
  }

  // ── GRADES DISK CACHE ─────────────────────────────────────────────────────

  static const _kGradesCacheKey = 'grades_cache_v1';
  static const _kGradesCacheTimeKey = 'grades_cache_time_v1';
  static const _kTimetableCachePrefix = 'timetable_cache_v1_';
  static const _kTimetableCacheTimePrefix = 'timetable_cache_time_v1_';

  void _saveGradesDiskCache(List<SubjectGrades> grades) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(grades.map((s) => s.toJson()).toList());
      await prefs.setString(_kGradesCacheKey, encoded);
      await prefs.setInt(
        _kGradesCacheTimeKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  void _loadGradesDiskCache(SharedPreferences prefs) {
    try {
      final timeMs = prefs.getInt(_kGradesCacheTimeKey);
      if (timeMs == null) return;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(timeMs),
      );
      if (age > const Duration(hours: 12)) return;

      final encoded = prefs.getString(_kGradesCacheKey);
      if (encoded == null) return;

      final list = (jsonDecode(encoded) as List)
          .map((j) => SubjectGrades.fromJson(j as Map<String, dynamic>))
          .toList();

      // Only pre-warm if no fresher data is already in memory.
      _gradesCache ??= _CachedData(list);
    } catch (_) {}
  }

  // ── TIMETABLE DISK CACHE ──────────────────────────────────────────────────

  void _saveTimetableDiskCache(
    DateTime weekStart,
    List<TimetableEntry> entries,
  ) async {
    try {
      final key = _weekKey(weekStart);
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(entries.map((e) => e.toJson()).toList());
      await prefs.setString('$_kTimetableCachePrefix$key', encoded);
      await prefs.setInt(
        '$_kTimetableCacheTimePrefix$key',
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {}
  }

  void _loadTimetableDiskCache(SharedPreferences prefs) {
    try {
      final now = DateTime.now();
      final allKeys = prefs.getKeys();
      for (final storeKey in allKeys) {
        if (!storeKey.startsWith(_kTimetableCachePrefix)) continue;
        final weekKey = storeKey.substring(_kTimetableCachePrefix.length);
        if (_timetableCache.containsKey(weekKey)) continue;

        final timeMs = prefs.getInt('$_kTimetableCacheTimePrefix$weekKey');
        if (timeMs == null) continue;
        final age = now.difference(DateTime.fromMillisecondsSinceEpoch(timeMs));
        if (age > const Duration(days: 7)) continue;

        final encoded = prefs.getString(storeKey);
        if (encoded == null) continue;
        final list = (jsonDecode(encoded) as List)
            .map((j) => TimetableEntry.fromJson(j as Map<String, dynamic>))
            .toList();
        _timetableCache[weekKey] = _CachedData(list);
      }
    } catch (_) {}
  }

  /// Clears in-memory and disk caches (grades + timetable). Does NOT clear
  /// the session — call this when the user explicitly wants a fresh reload.
  Future<void> clearLocalCaches() async {
    _clearCaches();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kGradesCacheKey);
      await prefs.remove(_kGradesCacheTimeKey);
      final timetableKeys = prefs
          .getKeys()
          .where(
            (k) =>
                k.startsWith(_kTimetableCachePrefix) ||
                k.startsWith(_kTimetableCacheTimePrefix),
          )
          .toList();
      for (final k in timetableKeys) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  dynamic _parseJsonResponse(String responseBody) {
    final trimmed = responseBody.trimLeft();
    if (trimmed.startsWith('<')) {
      throw WebUntisException('Sitzung abgelaufen', isAuthError: true);
    }
    return jsonDecode(responseBody);
  }

  Future<dynamic> _rpc(String method, Map<String, dynamic> params) async {
    if (_sessionId == null) {
      throw WebUntisException('Nicht angemeldet', isAuthError: true);
    }

    final response = await _client
        .post(
          Uri.parse('$_baseUrl/jsonrpc.do?school=$_school'),
          headers: {
            'Content-Type': 'application/json',
            'Cookie': _cookieHeader,
          },
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': '1',
            'method': method,
            'params': params,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw WebUntisException('Server-Fehler: ${response.statusCode}');
    }

    final data = _parseJsonResponse(response.body);
    if (data['error'] != null) {
      final code = data['error']['code'];
      if (code == -8520 || code == -8509) {
        throw WebUntisException('Sitzung abgelaufen', isAuthError: true);
      }
      throw WebUntisException(data['error']['message'] ?? 'Unbekannter Fehler');
    }

    return data['result'];
  }

  int _dateToInt(DateTime d) => int.parse(
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}',
  );

  DateTime _getMonday(DateTime date) =>
      date.subtract(Duration(days: date.weekday - 1));
}

// ── Generic cache wrapper ─────────────────────────────────────────────────────

class _CachedData<T> {
  final T data;
  final DateTime _fetchedAt;

  _CachedData(this.data) : _fetchedAt = DateTime.now();

  bool isExpired(Duration ttl) => DateTime.now().difference(_fetchedAt) > ttl;
}

// ── MODELS ────────────────────────────────────────────────────────────────────

class TimetableEntry {
  final int id;
  final int lessonId;
  final int date;
  final int startTime;
  final int endTime;
  final String subjectName;
  final String subjectLong;
  final String teacherName;
  final String roomName;
  final String cellState;
  final String lessonText;
  final bool isCancelled;
  final bool isExam;

  /// True when the API marks this period as a substitution
  /// (cellState == 'SUBSTITUTION' or is.substitution == true).
  final bool isSubstitution;

  /// True when this period was added on top of the normal schedule
  /// (cellState == 'ADDITIONAL' or is.additional == true).
  final bool isAdditional;

  /// Original subject short name before substitution (from element state=='ABSENT').
  final String originalSubjectName;

  /// Original subject long name before substitution.
  final String originalSubjectLong;

  /// Original teacher name before substitution (from element state=='ABSENT').
  final String originalTeacherName;

  TimetableEntry({
    required this.id,
    required this.lessonId,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.subjectName,
    required this.subjectLong,
    required this.teacherName,
    required this.roomName,
    required this.cellState,
    required this.lessonText,
    required this.isCancelled,
    required this.isExam,
    this.isSubstitution = false,
    this.isAdditional = false,
    this.originalSubjectName = '',
    this.originalSubjectLong = '',
    this.originalTeacherName = '',
  });

  factory TimetableEntry.fromWeeklyApi(
    Map<String, dynamic> j,
    Map<String, Map<String, dynamic>> elementMap,
  ) {
    final elements = j['elements'] as List? ?? [];

    String subjectName = '';
    String subjectLong = '';
    String teacherName = '';
    String roomName = '';
    String originalSubjectName = '';
    String originalSubjectLong = '';
    String originalTeacherName = '';

    for (final el in elements) {
      final type = el['type'];
      final id = el['id'];
      final elState = el['state']?.toString() ?? '';
      final lookup = elementMap['$type-$id'];
      // Also look up the original element via orgId if present
      final orgId = el['orgId'];
      final orgLookup = orgId != null ? elementMap['$type-$orgId'] : null;

      if (lookup == null && orgLookup == null) continue;

      // 'ABSENT' = this is the original element that is absent/changed
      // 'SUBSTITUTED' = this is the replacement element
      // '' / null = normal (no change)
      final isAbsent = elState == 'ABSENT';
      final isSubstituted = elState == 'SUBSTITUTED';

      switch (type) {
        case 3: // SUBJECT
          if (isAbsent) {
            // Original subject (absent/changed)
            final src = lookup ?? orgLookup;
            if (src != null) {
              originalSubjectName = src['name'] ?? '';
              originalSubjectLong = src['longName'] ?? src['displayname'] ?? '';
            }
          } else {
            // Active subject (replacement or unchanged).
            // Prefer SUBSTITUTED element over an unchanged one so that
            // Zusatzstunde / Vertretung subjects aren't overwritten by the
            // original subject when element order in the API response varies.
            final src = lookup ?? orgLookup;
            if (src != null && (isSubstituted || subjectName.isEmpty)) {
              subjectName = src['name'] ?? '';
              subjectLong = src['longName'] ?? src['displayname'] ?? '';
            }
          }
          break;
        case 2: // TEACHER
          if (isAbsent) {
            final src = lookup ?? orgLookup;
            if (src != null) {
              final name = src['name'] ?? '';
              if (originalTeacherName.isNotEmpty) {
                originalTeacherName += ', $name';
              } else {
                originalTeacherName = name;
              }
            }
          } else {
            final src = lookup ?? orgLookup;
            if (src != null) {
              final name = src['name'] ?? '';
              if (teacherName.isNotEmpty) {
                teacherName += ', $name';
              } else {
                teacherName = name;
              }
            }
          }
          break;
        case 4: // ROOM
          if (!isAbsent) {
            final src = lookup ?? orgLookup;
            if (src != null) roomName = src['name'] ?? '';
          }
          break;
      }
    }

    // Fallback: if we have original info but no active subject (same subject, teacher substituted)
    // keep the subject showing normally (subject didn't change, only teacher did)
    if (subjectName.isEmpty && originalSubjectName.isNotEmpty) {
      subjectName = originalSubjectName;
      subjectLong = originalSubjectLong;
      // Don't clear originalSubjectName — we still want the strikethrough for teacher change
    }

    final isMap = j['is'] as Map<String, dynamic>? ?? {};

    return TimetableEntry(
      id: j['id'] ?? 0,
      lessonId: j['lessonId'] ?? 0,
      date: j['date'] ?? 0,
      startTime: j['startTime'] ?? 0,
      endTime: j['endTime'] ?? 0,
      subjectName: subjectName,
      subjectLong: subjectLong,
      teacherName: teacherName,
      roomName: roomName,
      cellState: j['cellState']?.toString() ?? '',
      lessonText: j['lessonText']?.toString() ?? '',
      isCancelled:
          j['cellState'] == 'CANCEL' ||
          j['code']?.toString() == 'cancelled' ||
          (isMap['cancelled'] == true),
      isExam: isMap['exam'] == true,
      isSubstitution:
          j['cellState'] == 'SUBSTITUTION' || (isMap['substitution'] == true),
      isAdditional:
          j['cellState'] == 'ADDITIONAL' || (isMap['additional'] == true),
    );
  }

  String get startFormatted {
    final h = startTime ~/ 100;
    final m = startTime % 100;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String get endFormatted {
    final h = endTime ~/ 100;
    final m = endTime % 100;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String get displayName => subjectLong.isNotEmpty
      ? subjectLong
      : (subjectName.isNotEmpty ? subjectName : lessonText);

  Map<String, dynamic> toJson() => {
    'id': id,
    'lessonId': lessonId,
    'date': date,
    'startTime': startTime,
    'endTime': endTime,
    'subjectName': subjectName,
    'subjectLong': subjectLong,
    'teacherName': teacherName,
    'roomName': roomName,
    'cellState': cellState,
    'lessonText': lessonText,
    'isCancelled': isCancelled,
    'isExam': isExam,
    'isSubstitution': isSubstitution,
    'isAdditional': isAdditional,
    'originalSubjectName': originalSubjectName,
    'originalSubjectLong': originalSubjectLong,
    'originalTeacherName': originalTeacherName,
  };

  factory TimetableEntry.fromJson(Map<String, dynamic> j) => TimetableEntry(
    id: (j['id'] as num? ?? 0).toInt(),
    lessonId: (j['lessonId'] as num? ?? 0).toInt(),
    date: (j['date'] as num? ?? 0).toInt(),
    startTime: (j['startTime'] as num? ?? 0).toInt(),
    endTime: (j['endTime'] as num? ?? 0).toInt(),
    subjectName: j['subjectName'] as String? ?? '',
    subjectLong: j['subjectLong'] as String? ?? '',
    teacherName: j['teacherName'] as String? ?? '',
    roomName: j['roomName'] as String? ?? '',
    cellState: j['cellState'] as String? ?? '',
    lessonText: j['lessonText'] as String? ?? '',
    isCancelled: j['isCancelled'] == true,
    isExam: j['isExam'] == true,
    isSubstitution: j['isSubstitution'] == true,
    isAdditional: j['isAdditional'] == true,
    originalSubjectName: j['originalSubjectName'] as String? ?? '',
    originalSubjectLong: j['originalSubjectLong'] as String? ?? '',
    originalTeacherName: j['originalTeacherName'] as String? ?? '',
  );
}

class SubjectGrades {
  final int lessonId;
  final String subjectName;
  final String teacherName;
  final List<GradeEntry> grades;

  SubjectGrades({
    required this.lessonId,
    required this.subjectName,
    required this.teacherName,
    required this.grades,
  });

  double? get average {
    final values = grades
        .map((g) => g.markDisplayValue)
        .where((v) => v > 0)
        .toList();
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  int get positiveCount => grades.where((g) => g.markDisplayValue >= 6).length;
  int get negativeCount => grades
      .where((g) => g.markDisplayValue < 6 && g.markDisplayValue > 0)
      .length;

  Map<String, dynamic> toJson() => {
    'lessonId': lessonId,
    'subjectName': subjectName,
    'teacherName': teacherName,
    'grades': grades.map((g) => g.toJson()).toList(),
  };

  factory SubjectGrades.fromJson(Map<String, dynamic> j) => SubjectGrades(
    lessonId: j['lessonId'] ?? 0,
    subjectName: j['subjectName'] ?? '',
    teacherName: j['teacherName'] ?? '',
    grades: (j['grades'] as List? ?? [])
        .map((g) => GradeEntry.fromCacheJson(g as Map<String, dynamic>))
        .toList(),
  );
}

class GradeEntry {
  final int id;
  final String text;
  final int date;
  final String markName;
  final int markValue;
  final double markDisplayValue;
  final String examType;

  GradeEntry({
    required this.id,
    required this.text,
    required this.date,
    required this.markName,
    required this.markValue,
    required this.markDisplayValue,
    required this.examType,
  });

  factory GradeEntry.fromJson(Map<String, dynamic> j) {
    final mark = j['mark'] as Map<String, dynamic>? ?? {};
    final examType = j['examType'] as Map<String, dynamic>? ?? {};

    return GradeEntry(
      id: j['id'] ?? 0,
      text: j['text']?.toString() ?? '',
      date: j['date'] ?? 0,
      markName: mark['name']?.toString() ?? '',
      markValue: mark['markValue'] ?? 0,
      markDisplayValue: (mark['markDisplayValue'] as num?)?.toDouble() ?? 0.0,
      examType:
          examType['longname']?.toString() ??
          examType['name']?.toString() ??
          '',
    );
  }

  factory GradeEntry.fromCacheJson(Map<String, dynamic> j) => GradeEntry(
    id: j['id'] ?? 0,
    text: j['text'] ?? '',
    date: j['date'] ?? 0,
    markName: j['markName'] ?? '',
    markValue: j['markValue'] ?? 0,
    markDisplayValue: (j['markDisplayValue'] as num?)?.toDouble() ?? 0.0,
    examType: j['examType'] ?? '',
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'date': date,
    'markName': markName,
    'markValue': markValue,
    'markDisplayValue': markDisplayValue,
    'examType': examType,
  };

  String get dateFormatted {
    final s = date.toString();
    if (s.length != 8) return s;
    return '${s.substring(6)}.${s.substring(4, 6)}.${s.substring(0, 4)}';
  }
}

class TimeGridUnit {
  final String name;
  final int startTime;
  final int endTime;

  TimeGridUnit({
    required this.name,
    required this.startTime,
    required this.endTime,
  });

  String get startFormatted {
    final h = startTime ~/ 100;
    final m = startTime % 100;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  String get endFormatted {
    final h = endTime ~/ 100;
    final m = endTime % 100;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }
}

// ── MESSAGE MODELS ───────────────────────────────────────────────────────────

class MessagePreview {
  final int id;
  final String subject;
  final String contentPreview;
  final String senderName;
  final int senderId;
  final DateTime sentDate;
  final bool isRead;
  final bool hasAttachments;
  final String recipientGroup;

  const MessagePreview({
    required this.id,
    required this.subject,
    required this.contentPreview,
    required this.senderName,
    required this.senderId,
    required this.sentDate,
    required this.isRead,
    required this.hasAttachments,
    required this.recipientGroup,
  });

  MessagePreview copyWith({
    int? id,
    String? subject,
    String? contentPreview,
    String? senderName,
    int? senderId,
    DateTime? sentDate,
    bool? isRead,
    bool? hasAttachments,
    String? recipientGroup,
  }) {
    return MessagePreview(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      contentPreview: contentPreview ?? this.contentPreview,
      senderName: senderName ?? this.senderName,
      senderId: senderId ?? this.senderId,
      sentDate: sentDate ?? this.sentDate,
      isRead: isRead ?? this.isRead,
      hasAttachments: hasAttachments ?? this.hasAttachments,
      recipientGroup: recipientGroup ?? this.recipientGroup,
    );
  }

  factory MessagePreview.fromJson(Map<String, dynamic> j) {
    // Parse sender — may be a nested object or flat fields
    String senderName = '';
    int senderId = 0;
    final sender = j['sender'];
    if (sender is Map) {
      senderName = (sender['displayName'] ?? sender['name'] ?? '').toString();
      senderId = (sender['userId'] ?? sender['id'] ?? 0) as int;
    } else {
      senderName = (j['senderName'] ?? j['sender'] ?? '').toString();
      senderId = (j['senderId'] ?? 0) as int;
    }

    // Parse date — may be ISO string or epoch millis
    DateTime sentDate;
    final dateField =
        j['sentDateTime'] ?? j['sentDate'] ?? j['date'] ?? j['createDate'];
    if (dateField is String) {
      sentDate = DateTime.tryParse(dateField) ?? DateTime.now();
    } else if (dateField is int) {
      sentDate = dateField > 9999999999
          ? DateTime.fromMillisecondsSinceEpoch(dateField)
          : DateTime.fromMillisecondsSinceEpoch(dateField * 1000);
    } else {
      sentDate = DateTime.now();
    }

    return MessagePreview(
      id: (j['id'] ?? 0) as int,
      subject: (j['subject'] ?? j['title'] ?? '').toString(),
      contentPreview:
          (j['contentPreview'] ?? j['preview'] ?? j['content'] ?? '')
              .toString(),
      senderName: senderName,
      senderId: senderId,
      sentDate: sentDate,
      isRead: (j['isRead'] ?? j['read'] ?? j['readDate'] != null) == true,
      hasAttachments:
          (j['hasAttachments'] ??
              j['attachmentCount'] != null &&
                  (j['attachmentCount'] ?? 0) > 0) ==
          true,
      recipientGroup: (j['recipientGroup'] ?? j['group'] ?? '').toString(),
    );
  }

  String get sentDateFormatted {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(sentDate.year, sentDate.month, sentDate.day);
    final diff = today.difference(msgDay).inDays;

    if (diff == 0) {
      return '${sentDate.hour.toString().padLeft(2, '0')}:${sentDate.minute.toString().padLeft(2, '0')}';
    } else if (diff == 1) {
      return 'Gestern';
    } else if (diff < 7) {
      const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
      return days[sentDate.weekday - 1];
    } else {
      return '${sentDate.day.toString().padLeft(2, '0')}.${sentDate.month.toString().padLeft(2, '0')}.${sentDate.year}';
    }
  }
}

class MessageDetail {
  final int id;
  final String subject;
  final String body;
  final String senderName;
  final int senderId;
  final DateTime sentDate;
  final bool isRead;
  final List<MessageAttachment> attachments;

  const MessageDetail({
    required this.id,
    required this.subject,
    required this.body,
    required this.senderName,
    required this.senderId,
    required this.sentDate,
    required this.isRead,
    required this.attachments,
  });

  MessageDetail copyWith({
    int? id,
    String? subject,
    String? body,
    String? senderName,
    int? senderId,
    DateTime? sentDate,
    bool? isRead,
    List<MessageAttachment>? attachments,
  }) {
    return MessageDetail(
      id: id ?? this.id,
      subject: subject ?? this.subject,
      body: body ?? this.body,
      senderName: senderName ?? this.senderName,
      senderId: senderId ?? this.senderId,
      sentDate: sentDate ?? this.sentDate,
      isRead: isRead ?? this.isRead,
      attachments: attachments ?? this.attachments,
    );
  }

  factory MessageDetail.fromJson(Map<String, dynamic> j) {
    String senderName = '';
    int senderId = 0;
    final sender = j['sender'];
    if (sender is Map) {
      senderName = (sender['displayName'] ?? sender['name'] ?? '').toString();
      senderId = (sender['userId'] ?? sender['id'] ?? 0) as int;
    } else {
      senderName = (j['senderName'] ?? j['sender'] ?? '').toString();
      senderId = (j['senderId'] ?? 0) as int;
    }

    DateTime sentDate;
    final dateField =
        j['sentDateTime'] ?? j['sentDate'] ?? j['date'] ?? j['createDate'];
    if (dateField is String) {
      sentDate = DateTime.tryParse(dateField) ?? DateTime.now();
    } else if (dateField is int) {
      sentDate = dateField > 9999999999
          ? DateTime.fromMillisecondsSinceEpoch(dateField)
          : DateTime.fromMillisecondsSinceEpoch(dateField * 1000);
    } else {
      sentDate = DateTime.now();
    }

    // Parse body — may be HTML or plain text
    String body =
        (j['body'] ?? j['content'] ?? j['text'] ?? j['contentPreview'] ?? '')
            .toString();
    // Strip HTML tags for clean display
    body = body.replaceAll(RegExp(r'<br\s*/?>'), '\n');
    body = body.replaceAll(RegExp(r'<[^>]*>'), '');
    body = body.replaceAll('&nbsp;', ' ');
    body = body.replaceAll('&amp;', '&');
    body = body.replaceAll('&lt;', '<');
    body = body.replaceAll('&gt;', '>');
    body = body.replaceAll('&quot;', '"');
    body = body.trim();

    // WebUntis uses different field names/wrappers depending on server version.
    final attachmentList =
        _coerceList(j['attachments']) ??
        _coerceList(j['messageFile']) ??
        _coerceList(j['files']) ??
        _coerceList(j['fileAttachments']) ??
        _coerceList(j['attachment']) ??
        _coerceList(j['data']) ??
        const [];

    final normalAttachments = attachmentList
        .whereType<Map>()
        .map((a) => MessageAttachment.fromJson(Map<String, dynamic>.from(a)))
        .toList();

    final storageList = (j['storageAttachments'] as List? ?? [])
        .whereType<Map>()
        .toList();
    final storageAttachments = storageList
        .map(
          (a) =>
              MessageAttachment.fromStorageJson(Map<String, dynamic>.from(a)),
        )
        .toList();

    final allAttachments = normalAttachments.isNotEmpty
        ? normalAttachments
        : storageAttachments;

    return MessageDetail(
      id: (j['id'] ?? 0) as int,
      subject: (j['subject'] ?? j['title'] ?? '').toString(),
      body: body,
      senderName: senderName,
      senderId: senderId,
      sentDate: sentDate,
      isRead: (j['isRead'] ?? j['read'] ?? true) == true,
      attachments: allAttachments,
    );
  }

  static List<dynamic>? _coerceList(dynamic value) {
    if (value is List) return value;
    if (value is Map) {
      final direct = value['attachments'];
      if (direct is List) return direct;
      final messageFile = value['messageFile'];
      if (messageFile is List) return messageFile;
      final files = value['files'];
      if (files is List) return files;
      final data = value['data'];
      if (data is List) return data;
      if (data is Map) return _coerceList(data);
      final result = value['result'];
      if (result is Map) return _coerceList(result);
    }
    return null;
  }

  String get sentDateFormatted {
    return '${sentDate.day.toString().padLeft(2, '0')}.${sentDate.month.toString().padLeft(2, '0')}.${sentDate.year} '
        '${sentDate.hour.toString().padLeft(2, '0')}:${sentDate.minute.toString().padLeft(2, '0')}';
  }
}

class MessageAttachment {
  final int id;
  final String storageId;
  final String name;
  final String? url;
  final int? size;

  const MessageAttachment({
    required this.id,
    this.storageId = '',
    required this.name,
    this.url,
    this.size,
  });

  factory MessageAttachment.fromJson(Map<String, dynamic> j) {
    final resolvedUrl =
        j['url']?.toString() ??
        j['downloadUrl']?.toString() ??
        j['href']?.toString() ??
        j['src']?.toString();

    final parsedId = _parseInt(j['id'] ?? j['storageId'] ?? j['fileId'] ?? 0);

    return MessageAttachment(
      id: parsedId > 0 ? parsedId : _parseIdFromUrl(resolvedUrl),
      storageId: j['storageId']?.toString() ?? '',
      name:
          (j['name'] ??
                  j['fileName'] ??
                  j['originalName'] ??
                  j['src'] ??
                  'Anhang')
              .toString(),
      url: resolvedUrl,
      size: _parseInt2(j['size'] ?? j['fileSize'] ?? j['length']),
    );
  }

  factory MessageAttachment.fromStorageJson(Map<String, dynamic> j) {
    return MessageAttachment(
      id: 0,
      storageId: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? 'Anhang',
      url: null,
      size: null,
    );
  }

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  static int? _parseInt2(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static int _parseIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return 0;
    final match = RegExp(r'/attachments/(\d+)').firstMatch(url);
    if (match == null) return 0;
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }
}

// ── HOMEWORK MODEL ────────────────────────────────────────────────────────────

class HomeworkEntry {
  final int id;
  final int lessonId;
  final int date;
  final int dueDate;
  final String text;
  final bool completed;

  const HomeworkEntry({
    required this.id,
    required this.lessonId,
    required this.date,
    required this.dueDate,
    required this.text,
    required this.completed,
  });

  factory HomeworkEntry.fromJson(Map<String, dynamic> j) => HomeworkEntry(
    id: j['id'] ?? 0,
    lessonId: j['lessonId'] ?? 0,
    date: j['date'] ?? 0,
    dueDate: j['dueDate'] ?? 0,
    text: j['text']?.toString() ?? '',
    completed: j['completed'] == true,
  );

  /// Due-date formatted as DD.MM.YYYY
  String get dueDateFormatted {
    final s = dueDate.toString();
    if (s.length != 8) return s;
    return '${s.substring(6)}.${s.substring(4, 6)}.${s.substring(0, 4)}';
  }
}

// ── ABSENCE MODEL ─────────────────────────────────────────────────────────────

class AbsenceEntry {
  final int id;
  final int startDate; // YYYYMMDD
  final int endDate; // YYYYMMDD
  final int startTime; // HHMM
  final int endTime; // HHMM
  final bool isExcused;
  final String? reasonName; // e.g. "Krankheit", "Sonstige"
  final String?
  absenceType; // e.g. "Vorwegentschuldigung", "Nachentschuldigung"
  final String? subjectName;
  final String? teacherName;
  final String? note; // student note / Bemerkung
  final String? excuseNote; // excuse text from teacher
  final int hours;

  const AbsenceEntry({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.startTime,
    required this.endTime,
    required this.isExcused,
    this.reasonName,
    this.absenceType,
    this.subjectName,
    this.teacherName,
    this.note,
    this.excuseNote,
    required this.hours,
  });

  factory AbsenceEntry.fromJson(Map<String, dynamic> j) {
    final excuseStatus = j['excuseStatus']?.toString() ?? '';
    final isExcused =
        j['isExcused'] == true ||
        excuseStatus.toLowerCase() == 'excused' ||
        (j['excuseStatusId'] != null && (j['excuseStatusId'] as num) > 0);

    int parseHours() {
      final h = j['hours'] ?? j['lessonCount'] ?? j['periods'];
      if (h is int) return h;
      if (h is double) return h.toInt();
      if (h is String) return int.tryParse(h) ?? 1;
      final st = j['startTime'] as int? ?? 0;
      final et = j['endTime'] as int? ?? 0;
      if (st > 0 && et > st) {
        final stH = st ~/ 100, stM = st % 100;
        final etH = et ~/ 100, etM = et % 100;
        final minutes = (etH * 60 + etM) - (stH * 60 + stM);
        return (minutes / 45).ceil().clamp(1, 20);
      }
      return 1;
    }

    String? clean(dynamic v) {
      final s = v?.toString().trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final excuse = j['excuse'] is Map ? j['excuse'] as Map : null;

    return AbsenceEntry(
      id: (j['id'] ?? 0) as int,
      startDate: (j['startDate'] ?? j['date'] ?? 0) as int,
      endDate: (j['endDate'] ?? j['startDate'] ?? j['date'] ?? 0) as int,
      startTime: (j['startTime'] ?? 0) as int,
      endTime: (j['endTime'] ?? 0) as int,
      isExcused: isExcused,
      reasonName: clean(j['reasonName'] ?? j['reason']),
      absenceType: clean(
        j['absenceType'] ?? j['type'] ?? j['absenceTypeName'] ?? j['typeName'],
      ),
      subjectName: clean(j['subject'] ?? j['subjectName']),
      teacherName: clean(j['teacherName'] ?? j['teacher']),
      note: clean(
        j['text'] ??
            j['studentText'] ??
            j['comment'] ??
            j['note'] ??
            j['bemerkung'],
      ),
      excuseNote: clean(
        excuse?['text'] ??
            excuse?['comment'] ??
            j['excuseText'] ??
            j['excuseComment'],
      ),
      hours: parseHours(),
    );
  }

  String get dateFormatted {
    final s = startDate.toString();
    if (s.length != 8) return s;
    return '${s.substring(6)}.${s.substring(4, 6)}.${s.substring(0, 4)}';
  }

  String get timeFormatted {
    if (startTime == 0 && endTime == 0) return '';
    final sh = (startTime ~/ 100).toString().padLeft(2, '0');
    final sm = (startTime % 100).toString().padLeft(2, '0');
    final eh = (endTime ~/ 100).toString().padLeft(2, '0');
    final em = (endTime % 100).toString().padLeft(2, '0');
    return '$sh:$sm – $eh:$em';
  }

  DateTime get startDateTime {
    final s = startDate.toString();
    if (s.length != 8) return DateTime.now();
    return DateTime(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
    );
  }
}
