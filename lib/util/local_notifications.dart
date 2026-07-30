import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../prefs/app_preferences.dart';

class LocalNotifications {
  LocalNotifications._();
  static final LocalNotifications instance = LocalNotifications._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final _prefs = AppPreferences();
  var _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(settings);
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  Future<void> showIncomingMessage({
    required String conversationId,
    required String title,
    required String body,
  }) async {
    final globalEnabled = await _prefs.notificationsEnabled();
    if (!globalEnabled) return;
    final perChatEnabled = await _prefs.notificationsEnabledForConversation(conversationId);
    if (!perChatEnabled) return;
    if (!_initialized) {
      await initialize();
    }
    const androidDetails = AndroidNotificationDetails(
      'messages',
      'Messages',
      channelDescription: 'Incoming secure message notifications',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
    );
    const details = NotificationDetails(android: androidDetails);
    final id = DateTime.now().millisecondsSinceEpoch.remainder(1 << 31);
    final safeBody = body.trim().isEmpty ? 'Новое сообщение' : body;
    await _plugin.show(id, title, safeBody, details, payload: conversationId);
  }
}
