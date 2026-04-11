import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../l10n/app_localizations.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const initSettings = InitializationSettings(
      iOS: darwinSettings,
      macOS: darwinSettings,
      android: androidSettings,
    );

    await _plugin.initialize(settings: initSettings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await init();
    final iOS = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iOS != null) {
      final granted = await iOS.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return true;
  }

  /// Tägliche Erinnerung um 11:30 Uhr planen
  Future<void> scheduleDailyReminder(AppLanguage language) async {
    await init();
    await _cancelAll();

    final l = AppLocalizations(language);
    final title = l.get('app_name');
    final body = l.get('daily_reminder_desc');

    await _plugin.periodicallyShow(
      id: 0,
      title: title,
      body: body,
      repeatInterval: RepeatInterval.daily,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        android: const AndroidNotificationDetails(
          'daily_reminder',
          'Daily Reminder',
          channelDescription: 'Daily lunch reminder',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  /// Benachrichtigung sofort senden (z.B. neue Gerichte)
  Future<void> showNewDishNotification(
    String dishName,
    AppLanguage language,
  ) async {
    await init();
    final l = AppLocalizations(language);
    final title = l.get('new_dish_alert');

    await _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title: title,
      body: dishName,
      notificationDetails: NotificationDetails(
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
        android: const AndroidNotificationDetails(
          'new_dishes',
          'New Dishes',
          channelDescription: 'Notifications about new dishes',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  Future<void> _cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  Future<void> cancelDailyReminder() async {
    await init();
    await _plugin.cancel(id: 0);
  }
}
