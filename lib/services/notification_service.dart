import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'webuntis_service.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('FCM background message: ${message.notification?.title}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final _localNotifs = FlutterLocalNotificationsPlugin();
  bool _localNotifsReady = false;
  Timer? _pollTimer;
  WebUntisService? _service;
  Set<int> _knownMessageIds = {};
  bool _skipNextPollNotification = false;
  // Guard against duplicate FCM token-refresh / message listeners
  bool _tokenRefreshListenerRegistered = false;
  bool _fcmListenersRegistered = false;

  /// Called once on app startup.
  Future<void> initialize() async {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    await _requestPermissions();

    // iOS: show banners/badges/sound while the app is in the foreground.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Initialize local notifications for both platforms.
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

    await _createAndroidChannel();
    _setupFcmListeners();
    _logFcmToken();
  }

  Future<void> _createAndroidChannel() async {
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
  }

  /// Call this after the user is authenticated to persist the FCM token to
  /// Firestore so the backend can send targeted push notifications.
  Future<void> saveFcmTokenForUser(String stableUid) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        bool apnsReady = false;
        for (int i = 0; i < 5; i++) {
          try {
            final apns = await _messaging.getAPNSToken();
            if (apns != null) {
              apnsReady = true;
              break;
            }
          } catch (_) {}
          await Future.delayed(const Duration(seconds: 3));
        }
        if (!apnsReady) {
          // APNS not ready yet — retry after 60 s when it is likely available.
          Future.delayed(
            const Duration(seconds: 60),
            () => saveFcmTokenForUser(stableUid),
          );
          debugPrint('FCM: APNS not ready, retry in 60 s');
          return;
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final token =
          prefs.getString('fcm_token') ?? await _messaging.getToken();
      if (token == null) return;

      await prefs.setString('fcm_token', token);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(stableUid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      debugPrint('FCM token saved to Firestore for $stableUid');

      // Keep Firestore in sync when the token rotates (only register once).
      if (!_tokenRefreshListenerRegistered) {
        _tokenRefreshListenerRegistered = true;
        _messaging.onTokenRefresh.listen((newToken) async {
          await prefs.setString('fcm_token', newToken);
          try {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(stableUid)
                .set({'fcmToken': newToken}, SetOptions(merge: true));
            debugPrint('FCM token refreshed for $stableUid');
          } catch (_) {}
        });
      }
    } catch (e) {
      debugPrint('FCM token save failed: $e');
    }
  }

  /// Start periodic message checks for the given service.
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

  /// Stop periodic message checks.
  void stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _service = null;
    _knownMessageIds = {};
    onNewMessages = null;
  }

  /// In-app banner callback — set from the widget layer.
  void Function(int newCount, String? firstSubject)? onNewMessages;

  // ── Permissions ──────────────────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint('FCM permission: ${settings.authorizationStatus}');
    } catch (e) {
      debugPrint('FCM permission error: $e');
    }
  }

  // ── FCM token ────────────────────────────────────────────────────────────

  Future<void> _logFcmToken() async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      bool apnsReady = false;
      for (int i = 0; i < 6; i++) {
        try {
          final apns = await _messaging.getAPNSToken();
          if (apns != null) {
            apnsReady = true;
            break;
          }
        } catch (_) {}
        await Future.delayed(const Duration(seconds: 3));
      }
      if (!apnsReady) return;
    }

    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('FCM Token: $token');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', token);
      }
    } catch (e) {
      debugPrint('FCM token error: $e');
    }

    if (!_tokenRefreshListenerRegistered) {
      _tokenRefreshListenerRegistered = true;
      _messaging.onTokenRefresh.listen((token) async {
        debugPrint('FCM Token refreshed: $token');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', token);
      });
    }
  }

  // ── FCM message listeners ────────────────────────────────────────────────

  void _setupFcmListeners() {
    if (_fcmListenersRegistered) return;
    _fcmListenersRegistered = true;
    // Foreground FCM message: show OS notification + refresh messages list.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      debugPrint('FCM foreground message: ${message.notification?.title}');
      final notif = message.notification;
      if (notif != null) {
        // FCM already shows the notification — suppress the polling duplicate.
        _skipNextPollNotification = true;
        await _showLocalNotification(
          notif.title ?? 'POKYH',
          notif.body ?? '',
        );
      }
      _checkForNewMessages();
    });

    // Notification tapped while app was in background.
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('FCM notification tapped: ${message.notification?.title}');
      _checkForNewMessages();
    });
  }

  // ── Local notification display ────────────────────────────────────────────

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

  // ── Polling ──────────────────────────────────────────────────────────────

  Future<void> _checkForNewMessages() async {
    final service = _service;
    if (service == null || !service.isLoggedIn) return;

    try {
      final messages = await service.getMessages(forceRefresh: true);
      final currentIds = messages.map((m) => m.id).toSet();
      debugPrint('[Notifications] Poll: ${currentIds.length} messages, known: ${_knownMessageIds.length}');

      final newIds = currentIds.difference(_knownMessageIds);
      if (newIds.isNotEmpty && _knownMessageIds.isNotEmpty) {
        debugPrint('[Notifications] New message IDs: $newIds');
        final newMessages =
            messages.where((m) => newIds.contains(m.id)).toList();
        final unreadNew = newMessages.where((m) => !m.isRead).toList();

        if (unreadNew.isNotEmpty) {
          final count = unreadNew.length;
          final subject = unreadNew.first.subject;
          final suppress = _skipNextPollNotification;
          _skipNextPollNotification = false;
          if (!suppress) {
            debugPrint('[Notifications] Showing poll notification: $count neue');
            await _showLocalNotification(
              count == 1 ? 'Neue Mitteilung' : '$count neue Mitteilungen',
              subject,
            );
          } else {
            debugPrint('[Notifications] Suppressed duplicate poll notification');
          }
          onNewMessages?.call(count, subject);
        }
      }

      _knownMessageIds = currentIds;
      await _saveKnownIds(service);
    } catch (_) {
      // Silent failure — will retry on next poll
    }
  }

  // ── Known message ID persistence ─────────────────────────────────────────

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
