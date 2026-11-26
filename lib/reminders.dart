// Reminder alerts scheduled on the phone itself (no server needed).
// Only active on iPhone; on the Windows test build these calls do nothing.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

typedef PlannedReminder = ({int id, String title, String body, DateTime when});

class Reminders {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static bool get supported => !kIsWeb && Platform.isIOS;

  static Future<void> init() async {
    if (!supported || _ready) return;
    try {
      tzdata.initializeTimeZones();
      const ios = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: false,
        requestSoundPermission: true,
      );
      await _plugin.initialize(const InitializationSettings(iOS: ios));
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Replaces every scheduled alert with [list]. iOS keeps at most 64, so we send the soonest 60.
  static Future<void> replaceAll(List<PlannedReminder> list) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      for (final r in list.take(60)) {
        await _plugin.zonedSchedule(
          r.id,
          r.title,
          r.body,
          tz.TZDateTime.from(r.when.toUtc(), tz.UTC),
          const NotificationDetails(iOS: DarwinNotificationDetails()),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    } catch (_) {
      // A failed alert should never break the app.
    }
  }
}
