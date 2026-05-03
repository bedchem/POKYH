import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'webuntis_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _localNotifs = FlutterLocalNotificationsPlugin();
  bool _localNotifsReady = false;
  Timer? _pollTimer;
  WebUntisService? _service;
  Set<int> _knownMessageIds = {};
  bool _skipNextPollNotification = false;

  Future<void> initialize() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifs.initialize(
      const InitializationSettings(android: androidInit, iOS: darwinInit),
    );
    _localNotifsReady = true;

    final androidPlugin = _localNotifs
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        'pokyh_fcm',
        'Mitteilungen',
        description: 'Push-Benachrichtigungen für neue Nachrichten',
        importance: Importance.high,
      ),
    );

    await androidPlugin?.requestNotificationsPermission();
    await _localNotifs
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> saveFcmTokenForUser(String stableUid) async {
    // FCM removed — local notifications only.
  }

  void startPolling(WebUntisService service) {
    _service = service;
    _pollTimer?.cancel();
    _pollTimer = null;

    _loadKnownIds(service).then((_) {
      if (!identical(_service, service)) return;

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(
        AppConfig.messagesCheckInterval,
        (_) => _checkForNewMessages(),
      );
      _checkForNewMessages();
    });
  }

  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _service = null;
    _knownMessageIds = {};
    onNewMessages = null;
  }

  void Function(int newCount, String? firstSubject)? onNewMessages;

  Future<void> _checkForNewMessages() async {
    final service = _service;
    if (service == null || !service.isLoggedIn) return;

    try {
      final messages = await service.getMessages(forceRefresh: true);
      final currentIds = messages.map((m) => m.id).toSet();
      debugPrint('[Notifications] Poll: ${currentIds.length} messages, known: ${_knownMessageIds.length}');

      final newIds = currentIds.difference(_knownMessageIds);
      if (newIds.isNotEmpty && _knownMessageIds.isNotEmpty) {
        final newMessages =
            messages.where((m) => newIds.contains(m.id)).toList();
        final unreadNew = newMessages.where((m) => !m.isRead).toList();

        if (unreadNew.isNotEmpty) {
          final count = unreadNew.length;
          final subject = unreadNew.first.subject;
          final suppress = _skipNextPollNotification;
          _skipNextPollNotification = false;
          if (!suppress) {
            await _showLocalNotification(
              count == 1 ? 'Neue Mitteilung' : '$count neue Mitteilungen',
              subject,
            );
          }
          onNewMessages?.call(count, subject);
        }
      }

      _knownMessageIds = currentIds;
      await _saveKnownIds(service);
    } catch (_) {}
  }

  Future<void> _showLocalNotification(String title, String body) async {
    if (!_localNotifsReady) return;
    try {
      const android = AndroidNotificationDetails(
        'pokyh_fcm',
        'Mitteilungen',
        channelDescription: 'Push-Benachrichtigungen für neue Nachrichten',
        importance: Importance.high,
        priority: Priority.high,
      );
      const darwin = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      await _localNotifs.show(
        1,
        title,
        body,
        const NotificationDetails(android: android, iOS: darwin),
      );
    } catch (e) {
      debugPrint('Local notification failed: $e');
    }
  }

  String _knownIdsKey(WebUntisService service) =>
      'notification_known_message_ids_v1_${service.persistenceScopeKey}';

  Future<void> _loadKnownIds(WebUntisService service) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_knownIdsKey(service));
      if (saved != null) {
        _knownMessageIds = saved.map((s) => int.tryParse(s) ?? 0).toSet();
        _knownMessageIds.remove(0);
      } else {
        _knownMessageIds = {};
      }
    } catch (_) {
      _knownMessageIds = {};
    }
  }

  Future<void> _saveKnownIds(WebUntisService service) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _knownIdsKey(service),
        _knownMessageIds.map((id) => id.toString()).toList(),
      );
    } catch (_) {}
  }
}
