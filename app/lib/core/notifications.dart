import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'navigation.dart';
import '../features/reminders/reminder_page.dart';

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _channelId = 'mypet_reminders';
  static const _channelName = '照护提醒';

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Fall back to the timezone package default when the platform channel
      // is unavailable; scheduling still works relative to that location.
    }
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (response) {
        appNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => const ReminderPage()),
        );
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    _ready = true;
  }

  /// Replaces every scheduled notification with the current pending set of
  /// periodic reminders and one-off appointments.
  static Future<void> syncTasks({
    List<Reminder> reminders = const [],
    List<Appointment> appointments = const [],
  }) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: '疫苗、驱虫、体检、预约与生日提醒',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );
    final now = DateTime.now();
    var scheduled = 0;
    for (final reminder in reminders) {
      if (reminder.status != 'pending' && reminder.status != 'snoozed') {
        continue;
      }
      final due = DateTime.tryParse(reminder.dueAt);
      if (due == null) continue;
      final offsets =
          reminder.advanceOffsets.isEmpty ? const [0] : reminder.advanceOffsets;
      for (final offset in offsets) {
        if (scheduled >= 64) return;
        final day = due.subtract(Duration(days: offset));
        var when = DateTime(day.year, day.month, day.day, 9);
        if (when.isBefore(now)) {
          if (offset != 0) continue;
          when = now.add(const Duration(seconds: 15));
        }
        final id = _idFor('${reminder.occurrenceKey}:$offset');
        if (await _schedule(
          id: id,
          title: '${reminder.petName} · ${reminder.typeLabel}提醒',
          body: offset == 0 ? '今天到期，记得完成照护' : '还有 $offset 天到期',
          when: when,
          payload: reminder.id,
          details: details,
        )) {
          scheduled++;
        }
      }
    }
    for (final appointment in appointments) {
      if (appointment.status != 'pending' && appointment.status != 'snoozed') {
        continue;
      }
      if (scheduled >= 64) return;
      final due = DateTime.tryParse(appointment.scheduledAt);
      if (due == null) continue;
      if (appointment.status == 'snoozed') {
        final until = DateTime.tryParse(appointment.snoozedUntil)?.toLocal();
        if (until == null) continue;
        var when = until;
        if (when.isBefore(now)) when = now.add(const Duration(seconds: 15));
        final id = _idFor('appointment:${appointment.id}:snooze');
        if (await _schedule(
          id: id,
          title: '${appointment.petName} · ${appointment.typeLabel}预约',
          body: '稍后提醒：${appointment.title}',
          when: when,
          payload: appointment.id,
          details: details,
        )) {
          scheduled++;
        }
        continue;
      }
      final offsets = appointment.advanceOffsets.isEmpty
          ? const [0]
          : appointment.advanceOffsets;
      for (final offset in offsets) {
        if (scheduled >= 64) return;
        final day = due.subtract(Duration(days: offset));
        var when = DateTime(day.year, day.month, day.day, 9);
        if (when.isBefore(now)) {
          if (offset != 0) continue;
          when = now.add(const Duration(seconds: 15));
        }
        final id = _idFor('appointment:${appointment.id}:$offset');
        if (await _schedule(
          id: id,
          title: '${appointment.petName} · ${appointment.typeLabel}预约',
          body: offset == 0
              ? '今天有一项预约，完成后会自动生成健康记录'
              : '还有 $offset 天，预约：${appointment.title}',
          when: when,
          payload: appointment.id,
          details: details,
        )) {
          scheduled++;
        }
      }
    }
  }

  /// Schedules one notification, falling back to inexact alarms when the
  /// platform denies exact scheduling.
  static Future<bool> _schedule({
    required int id,
    required String title,
    required String body,
    required DateTime when,
    required String payload,
    required NotificationDetails details,
  }) async {
    for (final mode in const [
      AndroidScheduleMode.exactAllowWhileIdle,
      AndroidScheduleMode.inexactAllowWhileIdle,
    ]) {
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          tz.TZDateTime.from(when, tz.local),
          details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: payload,
        );
        return true;
      } catch (_) {
        // Try the less strict mode before giving up.
      }
    }
    return false;
  }

  static Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll().timeout(const Duration(seconds: 3));
    } catch (_) {
      // Notification cleanup must never block logout.
    }
  }

  /// Stable 31-bit id derived from the occurrence key and lead offset.
  static int _idFor(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
