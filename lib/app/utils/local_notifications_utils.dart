import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:karing/app/utils/log.dart';

/// Local notifications on top of flutter_local_notifications.
class LocalNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) {
      return;
    }
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings();
      const settings = InitializationSettings(android: android, macOS: darwin);
      await _plugin.initialize(settings: settings);
      _inited = true;
    } catch (err) {
      Log.w("LocalNotifications.init exception ${err.toString()}");
    }
  }

  static Future<void> notifiy(String title, String body,
      {String? channel, int id = 0}) async {
    if (!_inited) {
      return;
    }
    try {
      const android = AndroidNotificationDetails(
        'karing_general',
        'Karing',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      const darwin = DarwinNotificationDetails();
      const details = NotificationDetails(android: android, macOS: darwin);
      await _plugin.show(
          id: id,
          title: title,
          body: body,
          notificationDetails: details);
    } catch (err) {
      Log.w("LocalNotifications.notifiy exception ${err.toString()}");
    }
  }

  static Future<void> remove(int id) async {
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }
}

class LocalNotificationsUtils {
  static const String channelVPN = "karing_vpn";
  static const String channelSubscription = "karing_subscription";

  static String subscriptionExpiredTitle(String name) {
    return "Subscription expired: $name";
  }

  static String subscriptionUpdateTitle(String name) {
    return "Subscription updated: $name";
  }
}
