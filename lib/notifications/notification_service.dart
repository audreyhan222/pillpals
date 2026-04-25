import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/material.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  final StreamController<String?> _payloadStream = StreamController<String?>.broadcast();
  Stream<String?> get payloadStream => _payloadStream.stream;

  Future<void> init() async {
    tz.initializeTimeZones();
    await _configureLocalTimeZone();

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

  @pragma('vm:entry-point')
  static void _onBackgroundResponse(NotificationResponse resp) {
    // Background callback cannot access instance state reliably.
  }

  Future<void> _configureLocalTimeZone() async {
    if (kIsWeb) return;
    try {
      final name = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      // Fallback: timezone package will default to UTC if we can't detect local tz.
    }
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

  Future<void> showTestNow({String? payload}) async {
    await _plugin.show(
      1002,
      'Test notification',
      'This is a dev-triggered reminder.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'dose_reminders',
          'Dose reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
          presentSound: true,
        ),
      ),
      payload: payload ?? 'dev-test',
    );
  }

  /// Tries to send a REAL push notification by calling your backend.
  ///
  /// Notes:
  /// - A real push requires server credentials (FCM/APNs). The app itself
  ///   cannot safely send push directly.
  /// - If the backend endpoint is not implemented/reachable, we fall back to a
  ///   local notification so the button still provides feedback.
  Future<void> triggerDevPush({String? message, String? authToken}) async {
    if (kIsWeb) {
      // Local notifications are not supported in the same way on web.
      return;
    }

    try {
      final api = ApiClient(baseUrl: AppConfig.apiBaseUrl, token: authToken);
      await api.dio.post(
        ApiEndpoints.devPush,
        data: <String, dynamic>{
          'title': 'PillPal (Dev)',
          'body': message ?? 'This is a dev-triggered push notification.',
          // Add targeting fields on the server side (token/userId/topic).
        },
      );
    } catch (e) {
      // Fallback so the UI always "does something" during development.
      await showTestNow(payload: 'dev_push_fallback');
    }
  }

  /// Registers this device's current FCM token with the backend.
  ///
  /// Backend requires auth; if [authToken] is null/empty we skip quietly.
  Future<void> registerFcmTokenWithBackend({
    required String? authToken,
    String? baseUrl,
  }) async {
    if (kIsWeb) return;
    if (authToken == null || authToken.isEmpty) return;

    // Request iOS notification permission (FCM/APNs).
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;

    final api = ApiClient(
      baseUrl: (baseUrl == null || baseUrl.trim().isEmpty)
          ? AppConfig.apiBaseUrl
          : baseUrl.trim(),
      token: authToken,
    );
    await api.dio.post(
      ApiEndpoints.registerPushToken,
      data: <String, dynamic>{
        'token': token,
        'platform': 'ios',
      },
    );
  }

  /// Schedule a daily dose reminder at the given local [time].
  /// This fires even when the app is closed (local iOS scheduled notification).
  Future<void> scheduleDailyDoseReminder({
    required int id,
    required TimeOfDay time,
    required String title,
    required String body,
    String? payload,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      time.hour,
      time.minute,
    );
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'dose_reminders',
          'Dose reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.active,
          presentSound: true,
        ),
      ),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelReminder(int id) => _plugin.cancel(id);

  Future<List<PendingNotificationRequest>> pendingReminders() =>
      _plugin.pendingNotificationRequests();
}

