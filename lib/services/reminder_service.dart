import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'auth_service.dart';
import 'api_client.dart';

class ClassRoom {
  final String id;
  final String name;
  final String code;
  final List<String> members;
  final Map<String, String> memberNames;
  final String? createdByUid;
  final String? createdByName;

  const ClassRoom({
    required this.id,
    required this.name,
    required this.code,
    required this.members,
    this.memberNames = const {},
    this.createdByUid,
    this.createdByName,
  });

  factory ClassRoom.fromJson(Map<String, dynamic> d) {
    final rawMembers = d['members'] as List<dynamic>? ?? [];
    final members = rawMembers
        .cast<Map<String, dynamic>>()
        .map((m) => m['stableUid'] as String)
        .toList();
    final memberNames = <String, String>{
      for (final m in rawMembers.cast<Map<String, dynamic>>())
        m['stableUid'] as String: m['username'] as String? ?? m['stableUid'] as String,
    };
    return ClassRoom(
      id: d['id'] as String,
      name: d['name'] as String? ?? '',
      code: d['code'] as String? ?? '',
      members: members,
      memberNames: memberNames,
      createdByUid: d['createdBy'] as String?,
      createdByName: d['createdByName'] as String?,
    );
  }
}

class Reminder {
  final String id;
  final String classId;
  final String title;
  final String body;
  final String createdByUid;
  final String createdByName;
  final String createdByUsername;
  final DateTime remindAt;
  final DateTime? createdAt;

  const Reminder({
    required this.id,
    required this.classId,
    required this.title,
    required this.body,
    required this.createdByUid,
    required this.createdByName,
    required this.createdByUsername,
    required this.remindAt,
    this.createdAt,
  });

  bool get isDue => DateTime.now().isAfter(remindAt);
  bool get isExpired =>
      DateTime.now().isAfter(remindAt.add(const Duration(hours: 25)));

  factory Reminder.fromJson(Map<String, dynamic> d, String classId) {
    return Reminder(
      id: d['id'] as String,
      classId: classId,
      title: d['title'] as String? ?? '',
      body: d['body'] as String? ?? '',
      createdByUid: d['createdBy'] as String? ?? '',
      createdByName: d['createdByName'] as String? ?? 'Unbekannt',
      createdByUsername: d['createdByUsername'] as String? ?? '',
      remindAt: DateTime.parse(d['remindAt'] as String),
      createdAt: d['createdAt'] != null
          ? DateTime.tryParse(d['createdAt'] as String)
          : null,
    );
  }
}

class ReminderService {
  static final ReminderService _instance = ReminderService._();
  factory ReminderService() => _instance;
  ReminderService._();

  final _api = ApiClient.instance;
  final _notifs = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    final tzInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(tzInfo.identifier));
    debugPrint('[ReminderService] Timezone set to ${tzInfo.identifier}');

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifs.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    final androidImpl = _notifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.createNotificationChannel(
      const AndroidNotificationChannel(
        'reminders',
        'Erinnerungen',
        description: 'Klassen-Erinnerungen und Hausaufgaben',
        importance: Importance.high,
      ),
    );
    await androidImpl?.requestNotificationsPermission();
    await androidImpl?.requestExactAlarmsPermission();

    await _notifs
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  String? get _stableUid => AuthService.instance.stableUid;

  // ── Admin check ────────────────────────────────────────────────────────────

  bool? _adminCache;

  Future<bool> isAdmin() async {
    if (_adminCache == true) return true;
    final result = AuthService.instance.isAdmin;
    if (result) _adminCache = true;
    return result;
  }

  void clearAdminCache() => _adminCache = null;

  // ── Classes stream ─────────────────────────────────────────────────────────

  Stream<List<ClassRoom>> classesStream() {
    final classId = AuthService.instance.classId;
    if (classId == null) return Stream.value([]);

    final controller = StreamController<List<ClassRoom>>();
    bool active = true;

    Future<void> fetch() async {
      if (!active || controller.isClosed) return;
      try {
        final data = await _api.get('/classes/$classId') as Map<String, dynamic>?;
        if (!controller.isClosed) {
          controller.add(data != null ? [ClassRoom.fromJson(data)] : []);
        }
      } catch (_) {
        if (!controller.isClosed) controller.add([]);
      }
    }

    fetch();
    final timer = Timer.periodic(const Duration(seconds: 60), (_) => fetch());

    controller.onCancel = () {
      active = false;
      timer.cancel();
    };

    return controller.stream;
  }

  Future<ClassRoom?> findClassByCode(String code) async => null;

  Future<ClassRoom> createClass(String name, {int? webuntisKlasseId}) async {
    final stableUid = _stableUid;
    if (stableUid == null || stableUid.isEmpty) {
      throw Exception('Kein Benutzername gesetzt');
    }
    final klasseId = webuntisKlasseId ?? AuthService.instance.webuntisKlasseId ?? 0;
    final data = await _api.post('/classes', {
      'name': name.trim(),
      'webuntisKlasseId': klasseId,
    }) as Map<String, dynamic>;
    return ClassRoom.fromJson(data);
  }

  Future<ClassRoom> joinClass(String code, {bool isAdminUser = false}) async {
    final stableUid = _stableUid;
    if (stableUid == null || stableUid.isEmpty) {
      throw Exception('Kein Benutzername gesetzt');
    }
    final data = await _api.post('/classes/join', {
      'code': code.trim().toUpperCase(),
    }) as Map<String, dynamic>;
    final classId = data['classId'] as String;
    final classData = await _api.get('/classes/$classId') as Map<String, dynamic>;
    return ClassRoom.fromJson(classData);
  }

  Future<void> leaveClass(String classId) async {
    await _api.post('/classes/$classId/leave');
  }

  Future<void> autoJoinOrCreateWebuntisClass(
    String klasseName,
    int webuntisKlasseId,
  ) async {
    debugPrint('[ReminderService] autoJoin: handled by backend on login');
  }

  // ── Reminders stream ───────────────────────────────────────────────────────

  final Map<String, StreamController<List<Reminder>>> _reminderCtrl = {};
  final Map<String, Timer> _reminderTimers = {};
  final Map<String, List<Reminder>> _reminderCache = {};

  Stream<List<Reminder>> remindersStream(String classId) {
    _ensureReminderStream(classId);
    return _reminderCtrl[classId]!.stream;
  }

  void _ensureReminderStream(String classId) {
    final existing = _reminderCtrl[classId];
    if (existing != null && !existing.isClosed) return;

    final ctrl = StreamController<List<Reminder>>.broadcast();
    _reminderCtrl[classId] = ctrl;
    _reminderTimers[classId]?.cancel();
    _reminderTimers[classId] = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshReminders(classId),
    );

    // Emit cached list instantly before first network fetch.
    final cached = _reminderCache[classId];
    if (cached != null) {
      Future.microtask(() {
        if (!ctrl.isClosed) ctrl.add(cached);
      });
    }
    _refreshReminders(classId);
  }

  Future<void> _refreshReminders(String classId) async {
    final ctrl = _reminderCtrl[classId];
    if (ctrl == null || ctrl.isClosed) return;
    try {
      final data = await _api.get('/classes/$classId/reminders') as List<dynamic>?;
      final reminders = (data ?? [])
          .cast<Map<String, dynamic>>()
          .map((d) => Reminder.fromJson(d, classId))
          .toList();
      _reminderCache[classId] = reminders;
      if (!ctrl.isClosed) ctrl.add(reminders);
    } catch (_) {
      if (!ctrl.isClosed) ctrl.add(_reminderCache[classId] ?? []);
    }
  }

  void _pushOptimisticReminders(String classId, List<Reminder> reminders) {
    _reminderCache[classId] = reminders;
    final ctrl = _reminderCtrl[classId];
    if (ctrl != null && !ctrl.isClosed) ctrl.add(reminders);
  }

  Future<void> createReminder({
    required String classId,
    required String title,
    required String body,
    required DateTime remindAt,
  }) async {
    final data = await _api.post('/classes/$classId/reminders', {
      'title': title.trim(),
      'body': body.trim(),
      'remindAt': remindAt.toUtc().toIso8601String(),
    }) as Map<String, dynamic>;

    // Optimistic: add new reminder to cached list immediately.
    final newReminder = Reminder.fromJson(data, classId);
    final updated = <Reminder>[newReminder, ...(_reminderCache[classId] ?? <Reminder>[])];
    _pushOptimisticReminders(classId, updated);

    await _scheduleNotification(
      data['id'] as String,
      title.trim(),
      body.trim(),
      remindAt,
    );
    _refreshReminders(classId);
  }

  Future<void> deleteReminder(String classId, String reminderId) async {
    // Optimistic: remove immediately.
    final cached = _reminderCache[classId];
    if (cached != null) {
      _pushOptimisticReminders(
        classId,
        cached.where((r) => r.id != reminderId).toList(),
      );
    }

    await _api.delete('/classes/$classId/reminders/$reminderId');
    await _cancelNotification(reminderId);
    _refreshReminders(classId);
  }

  Future<void> cleanupExpired(String classId) async {
    // Server-side cleanup — nothing to do in the client.
  }

  // ── Local notifications ────────────────────────────────────────────────────

  Future<void> _scheduleNotification(
    String id,
    String title,
    String body,
    DateTime at,
  ) async {
    if (!_initialized) return;
    if (at.isBefore(DateTime.now())) return;

    final notifId = id.hashCode.abs() % 2147483647;
    try {
      await _notifs.zonedSchedule(
        notifId,
        title,
        body.isNotEmpty ? body : null,
        tz.TZDateTime.from(at, tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'reminders',
            'Erinnerungen',
            channelDescription: 'Klassen-Erinnerungen',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (e) {
      debugPrint('[Reminders] schedule notification error: $e');
    }
  }

  Future<void> _cancelNotification(String id) async {
    if (!_initialized) return;
    final notifId = id.hashCode.abs() % 2147483647;
    await _notifs.cancel(notifId);
  }

  Future<void> scheduleTodoNotification(
    String id,
    String title,
    String? body,
    DateTime at,
  ) async {
    await _scheduleNotification('todo:$id', title, body ?? '', at);
  }

  Future<void> cancelTodoNotification(String id) async {
    await _cancelNotification('todo:$id');
  }
}
