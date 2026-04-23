import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;
import 'firebase_auth_service.dart';

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

  factory ClassRoom.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawNames = data['memberNames'];
    final memberNames = rawNames is Map
        ? Map<String, String>.fromEntries(
            rawNames.entries.map((e) => MapEntry(e.key as String, e.value?.toString() ?? e.key)),
          )
        : <String, String>{};
    return ClassRoom(
      id: doc.id,
      name: data['name'] as String? ?? '',
      code: data['code'] as String? ?? '',
      members: List<String>.from(data['members'] as List? ?? []),
      memberNames: memberNames,
      createdByUid: data['createdBy'] as String?,
      createdByName: data['createdByName'] as String?,
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

  factory Reminder.fromDoc(DocumentSnapshot doc, String classId) {
    final data = doc.data() as Map<String, dynamic>;
    return Reminder(
      id: doc.id,
      classId: classId,
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      createdByUid: data['createdBy'] as String? ?? '',
      createdByName: data['createdByName'] as String? ?? 'Unbekannt',
      createdByUsername: data['createdByUsername'] as String? ?? '',
      remindAt: (data['remindAt'] as Timestamp).toDate(),
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : null,
    );
  }
}

class ReminderService {
  static final ReminderService _instance = ReminderService._();
  factory ReminderService() => _instance;
  ReminderService._();

  final _db = FirebaseFirestore.instance;
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
    // Android 13+ requires runtime permission for notifications
    await androidImpl?.requestNotificationsPermission();
    // Android 12+ requires exact alarm permission
    await androidImpl?.requestExactAlarmsPermission();

    // iOS: request permission via flutter_local_notifications
    await _notifs
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    _initialized = true;
  }

  String? get _uid => FirebaseAuthService.instance.userId;
  String? get _stableUid => FirebaseAuthService.instance.stableUid;

  // ── Admin check ────────────────────────────────────────────────────────────

  bool? _adminCache;

  Future<bool> isAdmin() async {
    if (_adminCache == true) return true;
    final username = FirebaseAuthService.instance.username;
    final stableUid = _stableUid;
    final firebaseUid = _uid;
    if (username == null && stableUid == null && firebaseUid == null) {
      return false;
    }
    try {
      bool result = false;

      // Primary: users/{username}.isAdmin  → set in Firebase Console
      if (username != null) {
        final doc = await _db.collection('users').doc(username).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          if (data?['isAdmin'] == true) result = true;
        }
      }

      // Fallback: legacy admins collection
      if (!result) {
        final checks = <Future<DocumentSnapshot>>[];
        if (stableUid != null) {
          checks.add(_db.collection('admins').doc(stableUid).get());
        }
        if (firebaseUid != null && firebaseUid != stableUid) {
          checks.add(_db.collection('admins').doc(firebaseUid).get());
        }
        if (checks.isNotEmpty) {
          final docs = await Future.wait(checks);
          result = docs.any((doc) {
            if (!doc.exists) return false;
            final data = doc.data() as Map<String, dynamic>?;
            return data?['canCreateClass'] == true;
          });
        }
      }

      if (result) _adminCache = true;
      debugPrint('[ReminderService] isAdmin username=$username result=$result');
      return result;
    } catch (e) {
      debugPrint('[ReminderService] isAdmin error: $e');
      return false;
    }
  }

  void clearAdminCache() => _adminCache = null;

  // ── Classes ────────────────────────────────────────────────────────────────

  Stream<List<ClassRoom>> classesStream() {
    final stableUid = _stableUid;
    if (stableUid == null || stableUid.isEmpty) return Stream.value([]);
    return _db
        .collection('classes')
        .where('members', arrayContains: stableUid)
        .snapshots()
        .map((snap) => snap.docs.map(ClassRoom.fromDoc).toList());
  }

  Future<ClassRoom?> findClassByCode(String code) async {
    final snap = await _db
        .collection('classes')
        .where('code', isEqualTo: code.trim().toUpperCase())
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return ClassRoom.fromDoc(snap.docs.first);
  }

  Future<ClassRoom> createClass(String name) async {
    final stableUid = _stableUid;
    if (stableUid == null || stableUid.isEmpty) throw Exception('Kein Benutzername gesetzt');
    final displayName = FirebaseAuthService.instance.username ?? stableUid;
    final trimmedName = name.trim();
    final code = _generateCode();
    final ref = await _db.collection('classes').add({
      'name': trimmedName,
      'code': code,
      'members': [stableUid],
      'memberNames': {stableUid: displayName},
      'createdBy': stableUid,
      'createdByName': displayName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ClassRoom(
      id: ref.id,
      name: trimmedName,
      code: code,
      members: [stableUid],
      createdByUid: stableUid,
      createdByName: displayName,
    );
  }

  Future<ClassRoom> joinClass(String code, {bool isAdminUser = false}) async {
    final stableUid = _stableUid;
    if (stableUid == null || stableUid.isEmpty) throw Exception('Kein Benutzername gesetzt');
    final displayName = FirebaseAuthService.instance.username ?? stableUid;

    // Non-admins can only be in one class
    if (!isAdminUser) {
      final existing = await _db
          .collection('classes')
          .where('members', arrayContains: stableUid)
          .limit(1)
          .get();
      if (existing.docs.isNotEmpty) {
        throw Exception('Du bist bereits in einer Klasse.\nVerlasse sie zuerst, um beizutreten.');
      }
    }

    final cls = await findClassByCode(code);
    if (cls == null) throw Exception('Klasse nicht gefunden.\nBitte Code prüfen.');
    if (cls.members.contains(stableUid)) return cls;
    await _db.collection('classes').doc(cls.id).update({
      'members': FieldValue.arrayUnion([stableUid]),
      'memberNames.$stableUid': displayName,
    });
    return cls;
  }

  Future<void> leaveClass(String classId) async {
    final stableUid = _stableUid;
    if (stableUid == null || stableUid.isEmpty) return;
    final ref = _db.collection('classes').doc(classId);
    await ref.update({
      'members': FieldValue.arrayRemove([stableUid]),
      'memberNames.$stableUid': FieldValue.delete(),
    });
    // Delete class if no members remain
    final doc = await ref.get();
    if (doc.exists) {
      final members = List<String>.from(doc.data()?['members'] ?? []);
      if (members.isEmpty) {
        await ref.delete();
      }
    }
  }

  // ── WebUntis Auto-Klasse ───────────────────────────────────────────────────

  /// Vollautomatische Klassenzuweisung via WebUntis:
  /// - Bereits in korrekter Klasse → nichts tun
  /// - In falscher WebUntis-Klasse (Klassenwechsel) → verlassen + neue beitreten
  /// - Klasse mit dieser webuntisKlasseId existiert → beitreten
  /// - Noch keine Klasse → neu anlegen
  Future<void> autoJoinOrCreateWebuntisClass(
    String klasseName,
    int webuntisKlasseId,
  ) async {
    final stableUid = _stableUid;
    if (stableUid == null || stableUid.isEmpty) {
      debugPrint('[ReminderService] autoJoin: kein stableUid – Firebase Auth aktiv?');
      throw Exception('Nicht angemeldet. Bitte Firebase Anonymous Auth aktivieren.');
    }
    final displayName = FirebaseAuthService.instance.username ?? stableUid;

    // 1. Bereits in der korrekten WebUntis-Klasse?
    final alreadyCorrect = await _db
        .collection('classes')
        .where('members', arrayContains: stableUid)
        .where('webuntisKlasseId', isEqualTo: webuntisKlasseId)
        .limit(1)
        .get();
    if (alreadyCorrect.docs.isNotEmpty) {
      debugPrint('[ReminderService] Bereits in korrekter Klasse "$klasseName"');
      return;
    }

    // 2. Klassenwechsel: in einer anderen WebUntis-Klasse? → verlassen
    final wrongClasses = await _db
        .collection('classes')
        .where('members', arrayContains: stableUid)
        .get();
    for (final doc in wrongClasses.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final existingKlasseId = data['webuntisKlasseId'];
      // Nur automatisch erstellte Klassen verlassen (nicht manuell beigetretene)
      if (existingKlasseId != null && existingKlasseId != webuntisKlasseId) {
        debugPrint('[ReminderService] Klassenwechsel: verlasse "${data['name']}" (id=$existingKlasseId)');
        await doc.reference.update({
          'members': FieldValue.arrayRemove([stableUid]),
          'memberNames.$stableUid': FieldValue.delete(),
        });
        // Leere Klasse löschen
        final updated = await doc.reference.get();
        final updatedData = updated.data() as Map<String, dynamic>?;
        final members = List.from(updatedData?['members'] ?? []);
        if (members.isEmpty) await doc.reference.delete();
      }
    }

    // 3. Ziel-Klasse suchen
    final classSnap = await _db
        .collection('classes')
        .where('webuntisKlasseId', isEqualTo: webuntisKlasseId)
        .limit(1)
        .get();

    if (classSnap.docs.isNotEmpty) {
      await classSnap.docs.first.reference.update({
        'members': FieldValue.arrayUnion([stableUid]),
        'memberNames.$stableUid': displayName,
      });
      debugPrint('[ReminderService] Auto-beigetreten: "$klasseName" (id=$webuntisKlasseId)');
    } else {
      final code = _generateCode();
      await _db.collection('classes').add({
        'name': klasseName,
        'code': code,
        'members': [stableUid],
        'memberNames': {stableUid: displayName},
        'createdBy': stableUid,
        'createdByName': displayName,
        'webuntisKlasseId': webuntisKlasseId,
        'createdAt': FieldValue.serverTimestamp(),
      });
      debugPrint('[ReminderService] Auto-erstellt: "$klasseName" (id=$webuntisKlasseId)');
    }
  }

  // ── Reminders ──────────────────────────────────────────────────────────────

  Stream<List<Reminder>> remindersStream(String classId) {
    return _db
        .collection('classes')
        .doc(classId)
        .collection('reminders')
        .orderBy('remindAt')
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => Reminder.fromDoc(doc, classId)).toList());
  }

  Future<void> createReminder({
    required String classId,
    required String title,
    required String body,
    required DateTime remindAt,
  }) async {
    // stableUid ist geräteübergreifend – damit können alle Geräte des Nutzers löschen
    final creatorId = _stableUid ?? _uid;
    if (creatorId == null) throw Exception('Nicht angemeldet');
    final name = FirebaseAuthService.instance.username ?? creatorId;

    final username = FirebaseAuthService.instance.username ?? '';
    final ref = await _db
        .collection('classes')
        .doc(classId)
        .collection('reminders')
        .add({
      'title': title.trim(),
      'body': body.trim(),
      'createdBy': creatorId,
      'createdByName': name,
      'createdByUsername': username,
      'remindAt': Timestamp.fromDate(remindAt),
      'createdAt': FieldValue.serverTimestamp(),
    });

    await _scheduleNotification(ref.id, title.trim(), body.trim(), remindAt);
  }

  Future<void> deleteReminder(String classId, String reminderId) async {
    await _db
        .collection('classes')
        .doc(classId)
        .collection('reminders')
        .doc(reminderId)
        .delete();
    await _cancelNotification(reminderId);
  }

  Future<void> cleanupExpired(String classId) async {
    if (_uid == null && (_stableUid == null || _stableUid!.isEmpty)) return;
    try {
      final snap = await _db
          .collection('classes')
          .doc(classId)
          .collection('reminders')
          .get();
      final cutoff = DateTime.now().subtract(const Duration(hours: 25));
      for (final doc in snap.docs) {
        final ts = doc.data()['remindAt'] as Timestamp?;
        if (ts != null && ts.toDate().isBefore(cutoff)) {
          await doc.reference.delete();
        }
      }
    } catch (_) {
      // Silently ignore – cleanup is best-effort
    }
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

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = math.Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }
}
