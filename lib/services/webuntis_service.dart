import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class WebUntisException implements Exception {
  final String message;
  final bool isAuthError;
  WebUntisException(this.message, {this.isAuthError = false});
  @override
  String toString() => message;
}

class WebUntisService {
  static const String _baseUrl = 'https://lbs-brixen.webuntis.com/WebUntis';
  static const String _school = 'lbs-brixen';
  static const String _schoolNameCookie = '_bGJzLWJyaXhlbg==';
  static const Duration _timeout = Duration(seconds: 15);
  static const Duration _timetableTTL = Duration(minutes: 10);
  static const Duration _gradesTTL = Duration(minutes: 5);

  // Persistent HTTP client — reuses TCP/TLS connections across requests.
  final http.Client _client = http.Client();

  String? _sessionId;
  String? _bearerToken;
  int? _studentId;
  int? _klasseId;
  int? _schoolYearId;
  List<TimeGridUnit>? _timeGrid;
  String? _username;

  bool get isLoggedIn => _sessionId != null && _studentId != null;
  String? get username => _username;
  int? get studentId => _studentId;

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

  void _clearCaches() {
    _timetableCache.clear();
    _gradesCache = null;
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

      final data = jsonDecode(response.body);
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

      // Run all three init calls in parallel — was sequential before.
      await Future.wait([
        _fetchBearerToken(),
        _fetchSchoolYear(),
        _fetchTimeGrid(),
      ]);

      await saveSession();

      return true;
    } on TimeoutException {
      throw WebUntisException(
        'Verbindung abgelaufen. Bitte versuche es erneut.',
      );
    } catch (e) {
      if (e is WebUntisException) rethrow;
      throw WebUntisException('Netzwerkfehler: $e');
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
        _bearerToken = response.body.trim().replaceAll('"', '');
      }
    } catch (_) {}
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
    _schoolYearId = null;
    _profileImageBytes = null;
    _profileImageFetched = false;
    _clearCaches();
    await clearSession();
  }

  // ── SESSION PERSISTENCE ───────────────────────────────────────────────────

  Future<void> saveSession() async {
    final prefs = await SharedPreferences.getInstance();
    if (_sessionId != null) await prefs.setString('sessionId', _sessionId!);
    if (_studentId != null) await prefs.setInt('studentId', _studentId!);
    if (_bearerToken != null)
      await prefs.setString('bearerToken', _bearerToken!);
    if (_klasseId != null) await prefs.setInt('klasseId', _klasseId!);
    if (_schoolYearId != null)
      await prefs.setInt('schoolYearId', _schoolYearId!);
    if (_username != null) await prefs.setString('username', _username!);
  }

  Future<bool> restoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _sessionId = prefs.getString('sessionId');
      _studentId = prefs.getInt('studentId');
      _bearerToken = prefs.getString('bearerToken');
      _klasseId = prefs.getInt('klasseId');
      _schoolYearId = prefs.getInt('schoolYearId');
      _username = prefs.getString('username');

      if (_sessionId == null || _studentId == null) return false;

      // Validate session and refresh bearer in parallel.
      final sessionFuture = _rpc('getLatestImportTime', {});
      final bearerFuture = _fetchBearerToken();
      final sessionResult = await sessionFuture;
      await bearerFuture;

      if (sessionResult == null) {
        await clearSession();
        return false;
      }

      await saveSession();

      // Pre-warm grades cache from disk.
      _loadGradesDiskCache(prefs);

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
    _schoolYearId = null;
    _username = null;
    _clearCaches();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
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

      final data = jsonDecode(response.body);
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
      throw WebUntisException('Netzwerkfehler: $e');
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
      throw WebUntisException('Fehler beim Laden der Noten: $e');
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

      final gradeData = jsonDecode(response.body);
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

  // ── GRADES DISK CACHE ─────────────────────────────────────────────────────

  static const _kGradesCacheKey = 'grades_cache_v1';
  static const _kGradesCacheTimeKey = 'grades_cache_time_v1';

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

  // ── HELPERS ───────────────────────────────────────────────────────────────

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

    final data = jsonDecode(response.body);
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

    for (final el in elements) {
      final type = el['type'];
      final id = el['id'];
      final lookup = elementMap['$type-$id'];
      if (lookup == null) continue;

      switch (type) {
        case 3: // SUBJECT
          subjectName = lookup['name'] ?? '';
          subjectLong = lookup['longName'] ?? lookup['displayname'] ?? '';
          break;
        case 2: // TEACHER
          if (teacherName.isNotEmpty) {
            teacherName += ', ${lookup['name'] ?? ''}';
          } else {
            teacherName = lookup['name'] ?? '';
          }
          break;
        case 4: // ROOM
          roomName = lookup['name'] ?? '';
          break;
      }
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
