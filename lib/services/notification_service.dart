import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'webuntis_service.dart';

/// Handles FCM push notifications and foreground message polling.
///
/// Push notifications require a backend that sends FCM messages when
/// new WebUntis messages arrive. This service sets up the FCM
/// infrastructure and polls for new messages while the app is in
/// the foreground.
class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  Timer? _pollTimer;
  WebUntisService? _service;
  Set<int> _knownMessageIds = {};

  /// Called once on app startup.
  Future<void> initialize() async {
    await _requestPermissions();
    _setupFcmListeners();
    _logFcmToken();
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
      // Immediate check on start
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

  /// Callback to display in-app notification banners.
  /// Set this from the widget layer.
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
      debugPrint(
        'FCM permission: ${settings.authorizationStatus}',
      );
    } catch (e) {
      debugPrint('FCM permission error: $e');
    }
  }

  // ── FCM token ────────────────────────────────────────────────────────────

  Future<void> _logFcmToken() async {
    try {
      final token = await _messaging.getToken();
      if (token != null) {
        debugPrint('FCM Token: $token');
        // Store token for potential backend registration
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', token);
      }
    } catch (e) {
      debugPrint('FCM token error: $e');
    }

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((token) async {
      debugPrint('FCM Token refreshed: $token');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcm_token', token);
    });
  }

  // ── FCM message listeners ────────────────────────────────────────────────

  void _setupFcmListeners() {
    // Foreground messages from FCM (if backend sends them)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('FCM foreground message: ${message.notification?.title}');
      // Trigger a message check to refresh the messages list
      _checkForNewMessages();
    });

    // When user taps a notification that opened the app
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('FCM notification tapped: ${message.notification?.title}');
      _checkForNewMessages();
    });
  }

  // ── Polling ──────────────────────────────────────────────────────────────

  Future<void> _checkForNewMessages() async {
    final service = _service;
    if (service == null || !service.isLoggedIn) return;

    try {
      final messages = await service.getMessages(forceRefresh: true);
      final currentIds = messages.map((m) => m.id).toSet();

      // Find truly new messages (IDs we haven't seen before)
      final newIds = currentIds.difference(_knownMessageIds);
      if (newIds.isNotEmpty && _knownMessageIds.isNotEmpty) {
        // Only notify if we had previous data (skip first load)
        final newMessages = messages.where((m) => newIds.contains(m.id)).toList();
        final unreadNew = newMessages.where((m) => !m.isRead).toList();

        if (unreadNew.isNotEmpty) {
          onNewMessages?.call(
            unreadNew.length,
            unreadNew.first.subject,
          );
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
