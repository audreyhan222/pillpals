import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  final StreamController<String?> _payloadStream = StreamController<String?>.broadcast();
  Stream<String?> get payloadStream => _payloadStream.stream;

  Future<void> init() async {
    tz.initializeTimeZones();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();

    const settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        _payloadStream.add(resp.payload);
      },
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );

    if (!kIsWeb) {
      await _requestPermissions();
      await _ensureAndroidChannel();
    }
  }

  static void _onBackgroundResponse(NotificationResponse resp) {
    // Background callback cannot access instance state reliably.
  }

  Future<void> _requestPermissions() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    await ios?.requestPermissions(alert: true, badge: true, sound: true);

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
  }

  Future<void> _ensureAndroidChannel() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        'dose_reminders',
        'Dose reminders',
        description: 'Medication dose reminders and escalations.',
        importance: Importance.max,
        playSound: true,
      ),
    );
  }

  Future<void> scheduleTestReminder({required Duration fromNow}) async {
    final now = tz.TZDateTime.now(tz.local);
    final when = now.add(fromNow);

    await _plugin.zonedSchedule(
      1001,
      'Medication reminder',
      'Time to take your dose. Tap to confirm.',
      when,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'dose_reminders',
          'Dose reminders',
          importance: Importance.max,
          priority: Priority.high,
          fullScreenIntent: true,
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'test',
    );
  }
}

