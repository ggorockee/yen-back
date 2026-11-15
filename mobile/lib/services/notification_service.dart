import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Departure reminders, scheduled on the device. The departure date never
/// leaves the phone.
class NotificationService {
  NotificationService(this._plugin);

  final FlutterLocalNotificationsPlugin _plugin;

  static const _dayBeforeId = 1;
  static const _airportId = 2;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'departure',
      '출국 알림',
      channelDescription: '출국 전 면세 세관 확인을 잊지 않도록 알려드려요',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
  );

  static Future<NotificationService> init() async {
    tzdata.initializeTimeZones();
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Ask only when the user sets a departure date, not at launch.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    return NotificationService(plugin);
  }

  /// Returns whether notifications are allowed.
  Future<bool> requestPermission() async {
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  /// Reminders for a departure, as instants relative to [departureAt]:
  /// the evening before at 20:00 and three hours before the flight.
  static List<({int id, DateTime at, String title, String body})> remindersFor(DateTime departureAt) {
    final dayBefore = DateTime(departureAt.year, departureAt.month, departureAt.day - 1, 20);
    return [
      (
        id: _dayBeforeId,
        at: dayBefore,
        title: '내일 출국이에요 ✈️',
        body: '면세 환급을 받으려면 짐을 부치기 전에 공항 세관 확인을 받아야 해요. 체크리스트를 확인해 보세요.',
      ),
      (
        id: _airportId,
        at: departureAt.subtract(const Duration(hours: 3)),
        title: '짐 부치기 전에 세관 확인!',
        body: '출국장 면세 키오스크에서 여권과 구매한 물건으로 세관 확인을 먼저 받으세요.',
      ),
    ];
  }

  /// Replaces any scheduled reminders. Reminders in the past are skipped.
  Future<void> scheduleDeparture(DateTime? departureAt) async {
    await _plugin.cancel(id: _dayBeforeId);
    await _plugin.cancel(id: _airportId);
    if (departureAt == null) return;

    final now = DateTime.now();
    for (final r in remindersFor(departureAt)) {
      if (!r.at.isAfter(now)) continue;
      await _plugin.zonedSchedule(
        id: r.id,
        // TZDateTime.from keeps the same instant, so UTC is safe regardless of
        // the device's zone.
        scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
        notificationDetails: _details,
        // Inexact alarms avoid the SCHEDULE_EXACT_ALARM permission; a few
        // minutes of drift is fine for these reminders.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: r.title,
        body: r.body,
      );
    }
  }
}
