import 'dart:convert';
import 'package:http/http.dart' as http;

class WebUntisService {
  static const String _baseUrl = 'https://noten-tschuggmall.eu/api/WebUntis';
  static const String _tokenUrl = 'https://lbs-brixen.webuntis.com/WebUntis/api/token/new';
  static const String _school = 'lbs-brixen';
  static const String _tenantId = '1243800';
  static const String _schoolNameCookie = '_bGJzLWJyaXhlbg==';

  String? _sessionId;
  String? _bearerToken;
  int? _studentId;

  bool get isLoggedIn => _sessionId != null;

  Map<String, String> get _cookies => {
        'JSESSIONID': _sessionId ?? '',
        'schoolname': '"$_schoolNameCookie"',
        'Tenant-Id': '"$_tenantId"',
      };

  String get _cookieHeader =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  // ── AUTH ──────────────────────────────────────────────────────────────────

  Future<bool> login(String username, String password) async {
    final response = await http.post(
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
    );

    if (response.statusCode != 200) return false;

    final data = jsonDecode(response.body);
    if (data['result'] == null || data['result']['sessionId'] == null) return false;

    _sessionId = data['result']['sessionId'];
    _studentId = data['result']['personId'];

    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      final match = RegExp(r'JSESSIONID=([^;]+)').firstMatch(setCookie);
      if (match != null) _sessionId = match.group(1);
    }

    print('Session ID: $_sessionId');
    print('Student ID: $_studentId');

    await _fetchBearerToken();
    return true;
  }

  Future<void> _fetchBearerToken() async {
    final response = await http.get(
      Uri.parse(_tokenUrl),
      headers: {'Cookie': _cookieHeader},
    );

    if (response.statusCode == 200) {
      _bearerToken = response.body.trim().replaceAll('"', '');
      print('Bearer Token OK: ${_bearerToken?.substring(0, 20)}...');
    } else {
      print('Bearer token failed: ${response.statusCode} - ${response.body}');
    }
  }

  Future<void> logout() async {
    if (_sessionId == null) return;
    await http.post(
      Uri.parse('$_baseUrl/jsonrpc.do?school=$_school'),
      headers: {'Content-Type': 'application/json', 'Cookie': _cookieHeader},
      body: jsonEncode({'jsonrpc': '2.0', 'id': '1', 'method': 'logout', 'params': {}}),
    );
    _sessionId = null;
    _studentId = null;
    _bearerToken = null;
  }

  // ── TIMETABLE ─────────────────────────────────────────────────────────────

  Future<List<TimetableEntry>> getTimetable({DateTime? date}) async {
    final target = date ?? DateTime.now();
    final result = await _rpc('getTimetable', {
      'id': _studentId,
      'type': 1,
      'startDate': _dateToInt(target),
      'endDate': _dateToInt(target),
      'showSubstText': true,
      'showInfo': true,
    });

    if (result == null) return [];
    return result.map<TimetableEntry>((e) => TimetableEntry.fromJson(e)).toList()
      ..sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<List<TimetableEntry>> getWeekTimetable({DateTime? weekStart}) async {
    final start = weekStart ?? _getMonday(DateTime.now());
    final end = start.add(const Duration(days: 4));

    final result = await _rpc('getTimetable', {
      'id': _studentId,
      'type': 1,
      'startDate': _dateToInt(start),
      'endDate': _dateToInt(end),
      'showSubstText': true,
      'showInfo': true,
    });

    if (result == null) return [];
    return result.map<TimetableEntry>((e) => TimetableEntry.fromJson(e)).toList()
      ..sort((a, b) {
        final dateComp = a.date.compareTo(b.date);
        return dateComp != 0 ? dateComp : a.startTime.compareTo(b.startTime);
      });
  }

  // ── GRADES ────────────────────────────────────────────────────────────────

  Future<LessonGrades?> getLessonGrades(int lessonId) async {
    if (_studentId == null || _bearerToken == null) return null;

    final response = await http.get(
      Uri.parse('$_baseUrl/api/classreg/grade/grading/lesson?studentId=$_studentId&lessonId=$lessonId'),
      headers: {
        'Authorization': 'Bearer $_bearerToken',
        'Accept': 'application/json, text/plain, */*',
      },
    );

    if (response.statusCode == 200) {
      try {
        final data = jsonDecode(response.body);
        if (data is Map && data['data'] != null) {
          return LessonGrades.fromJson(data['data']);
        }
      } catch (e) {
        print('Grade parse error: $e');
      }
    }
    return null;
  }

  Future<List<LessonGrades>> getAllGrades() async {
    if (_studentId == null || _bearerToken == null) return [];

    // Get lessons from last 6 months
    final start = DateTime.now().subtract(const Duration(days: 180));
    final end = DateTime.now();

    final allEntries = await _rpc('getTimetable', {
      'id': _studentId,
      'type': 1,
      'startDate': _dateToInt(start),
      'endDate': _dateToInt(end),
    });

    if (allEntries == null) return [];

    final lessonIds = allEntries.map((e) => e['id'] as int? ?? 0).toSet().where((id) => id > 0).toList();

    final results = <LessonGrades>[];
    for (final lessonId in lessonIds) {
      final grades = await getLessonGrades(lessonId);
      if (grades != null && grades.grades.isNotEmpty) {
        results.add(grades);
      }
    }

    return results;
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Future<List<dynamic>?> _rpc(String method, Map<String, dynamic> params) async {
    if (_sessionId == null) return null;

    final response = await http.post(
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
    );

    print('RPC $method: ${response.statusCode} - ${response.body.substring(0, response.body.length.clamp(0, 200))}');

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['result'] != null) return data['result'] as List<dynamic>;
    }
    return null;
  }

  int _dateToInt(DateTime d) => int.parse(
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}');

  DateTime _getMonday(DateTime date) =>
      date.subtract(Duration(days: date.weekday - 1));
}

// ── MODELS ────────────────────────────────────────────────────────────────────

class TimetableEntry {
  final int id;
  final int date;
  final int startTime;
  final int endTime;
  final String subjectName;
  final String subjectLong;
  final String teacherName;
  final String roomName;
  final String code;

  TimetableEntry({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.subjectName,
    required this.subjectLong,
    required this.teacherName,
    required this.roomName,
    required this.code,
  });

  factory TimetableEntry.fromJson(Map<String, dynamic> j) {
    final subjects = j['su'] as List? ?? [];
    final teachers = j['te'] as List? ?? [];
    final rooms = j['ro'] as List? ?? [];

    return TimetableEntry(
      id: j['id'] ?? 0,
      date: j['date'] ?? 0,
      startTime: j['startTime'] ?? 0,
      endTime: j['endTime'] ?? 0,
      subjectName: subjects.isNotEmpty ? (subjects[0]['name'] ?? '') : '',
      subjectLong: subjects.isNotEmpty ? (subjects[0]['longName'] ?? '') : '',
      teacherName: teachers.isNotEmpty ? (teachers[0]['name'] ?? '') : '',
      roomName: rooms.isNotEmpty ? (rooms[0]['name'] ?? '') : '',
      code: j['code']?.toString() ?? '',
    );
  }

  bool get isCancelled => code == 'cancelled';

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

class LessonGrades {
  final int lessonId;
  final String subjectName;
  final String teacherName;
  final List<GradeEntry> grades;

  LessonGrades({
    required this.lessonId,
    required this.subjectName,
    required this.teacherName,
    required this.grades,
  });

  factory LessonGrades.fromJson(Map<String, dynamic> j) {
    final lesson = j['lesson'] as Map<String, dynamic>? ?? {};
    final gradeList = (j['grades'] as List? ?? [])
        .map((e) => GradeEntry.fromJson(e))
        .toList();

    return LessonGrades(
      lessonId: lesson['id'] ?? 0,
      subjectName: lesson['subjects'] ?? '',
      teacherName: lesson['teachers'] ?? '',
      grades: gradeList,
    );
  }

  double? get average {
    final nums = grades.map((g) => g.markDisplayValue).whereType<double>().toList();
    if (nums.isEmpty) return null;
    return nums.reduce((a, b) => a + b) / nums.length;
  }
}

class GradeEntry {
  final int id;
  final String text;
  final int date;
  final String markName;
  final double? markDisplayValue;
  final String examType;

  GradeEntry({
    required this.id,
    required this.text,
    required this.date,
    required this.markName,
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
      markDisplayValue: (mark['markDisplayValue'] as num?)?.toDouble(),
      examType: examType['longname']?.toString() ?? '',
    );
  }

  String get dateFormatted {
    final s = date.toString();
    if (s.length != 8) return s;
    return '${s.substring(6)}.${s.substring(4, 6)}.${s.substring(0, 4)}';
  }
}

class Subject {
  final int id;
  final String name;
  final String longName;

  Subject({required this.id, required this.name, required this.longName});

  factory Subject.fromJson(Map<String, dynamic> j) => Subject(
        id: j['id'] ?? 0,
        name: j['name'] ?? '',
        longName: j['longName'] ?? '',
      );
}