import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';

@immutable
class NotificationEvent {
  const NotificationEvent({required this.payload, required this.actionId});

  final String? payload;
  final String? actionId;
}

@immutable
class DoseReminderPayload {
  const DoseReminderPayload({
    required this.doseId,
    required this.medicationName,
    required this.scheduledEpochMs,
    required this.stage,
  });

  final String doseId;
  final String medicationName;
  final int scheduledEpochMs;
  final int stage;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'doseId': doseId,
        'medicationName': medicationName,
        'scheduledEpochMs': scheduledEpochMs,
        'stage': stage,
      };

  String encode() => jsonEncode(toJson());

  static DoseReminderPayload? tryDecode(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map) return null;
      final doseId = decoded['doseId'];
      final medicationName = decoded['medicationName'];
      final scheduledEpochMs = decoded['scheduledEpochMs'];
      final stage = decoded['stage'];
      if (doseId is! String ||
          medicationName is! String ||
          scheduledEpochMs is! int ||
          stage is! int) {
        return null;
      }
      return DoseReminderPayload(
        doseId: doseId,
        medicationName: medicationName,
        scheduledEpochMs: scheduledEpochMs,
        stage: stage,
      );
    } catch (_) {
      return null;
    }
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static const String actionTaken = 'TAKEN';
  static const String actionSnooze10 = 'SNOOZE_10';

  final StreamController<NotificationEvent> _eventStream =
      StreamController<NotificationEvent>.broadcast();
  Stream<NotificationEvent> get eventStream => _eventStream.stream;

  Future<void> init() async {
    tz.initializeTimeZones();
    await _configureLocalTimeZone();

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    final iosInit = DarwinInitializationSettings(
      notificationCategories: [
        DarwinNotificationCategory(
          'dose_reminders',
          actions: [
            DarwinNotificationAction.plain(
              actionTaken,
              'I took it',
              options: {DarwinNotificationActionOption.authenticationRequired},
            ),
            DarwinNotificationAction.plain(
              actionSnooze10,
              'Snooze 10 min',
            ),
          ],
        ),
      ],
    );

    final settings = InitializationSettings(android: androidInit, iOS: iosInit);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (resp) {
        _eventStream.add(NotificationEvent(payload: resp.payload, actionId: resp.actionId));
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

  Future<void> requestPermissions() => _requestPermissions();

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
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
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
      _detailsForStage(stage: 0),
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
      _detailsForStage(stage: 0),
      payload: payload,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  NotificationDetails _detailsForStage({required int stage}) {
    // Stage 0: normal reminder
    // Stage 1: time-sensitive + louder intent
    // Stage 2: full-screen (Android) + critical-style interruption (iOS best-effort)
    final isEscalated = stage >= 1;
    final isFullScreen = stage >= 2;

    return NotificationDetails(
      android: AndroidNotificationDetails(
        'dose_reminders',
        'Dose reminders',
        importance: Importance.max,
        priority: Priority.high,
        fullScreenIntent: isFullScreen,
        category: AndroidNotificationCategory.alarm,
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(actionTaken, 'I took it'),
          AndroidNotificationAction(actionSnooze10, 'Snooze 10 min'),
        ],
      ),
      iOS: DarwinNotificationDetails(
        categoryIdentifier: 'dose_reminders',
        interruptionLevel: isEscalated
            ? InterruptionLevel.timeSensitive
            : InterruptionLevel.active,
        presentSound: true,
        presentAlert: true,
        presentBadge: true,
      ),
    );
  }

  int _doseNotificationId({
    required String doseId,
    required int stage,
  }) {
    // Stable 31-bit positive int id.
    final raw = doseId.hashCode ^ (stage * 9973);
    return raw.abs() % 2147483647;
  }

  /// Escalation protocol (local/on-device):
  /// - stage 0 at scheduled time
  /// - stage 1 at +5 minutes
  /// - stage 2 at +15 minutes
  ///
  /// These are one-shot notifications for the next occurrence of [time] (today or tomorrow).
  Future<void> scheduleEscalatingDoseReminder({
    required String doseId,
    required String medicationName,
    required String dosageText,
    required TimeOfDay time,
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

    const offsets = <Duration>[
      Duration(minutes: 0),
      Duration(minutes: 5),
      Duration(minutes: 15),
    ];

    for (int stage = 0; stage < offsets.length; stage++) {
      final when = scheduled.add(offsets[stage]);
      final payload = DoseReminderPayload(
        doseId: doseId,
        medicationName: medicationName,
        scheduledEpochMs: scheduled.millisecondsSinceEpoch,
        stage: stage,
      ).encode();

      await _plugin.zonedSchedule(
        _doseNotificationId(doseId: doseId, stage: stage),
        stage == 0 ? medicationName : 'Missed dose: $medicationName',
        dosageText.isEmpty
            ? 'Time to take your dose. Tap “I took it” when done.'
            : 'Time to take $dosageText. Tap “I took it” when done.',
        when,
        _detailsForStage(stage: stage),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: payload,
      );
    }
  }

  Future<void> showCaregiverEscalationNow({
    required String elderlyUsername,
    required String medicationName,
    required String dosageText,
    required String doseId,
    required int stage,
  }) async {
    final title = 'Escalation: $medicationName';
    final body = dosageText.isEmpty
        ? 'Dose missed by $elderlyUsername. Tap to view.'
        : 'Dose missed by $elderlyUsername: $dosageText';
    final payload = DoseReminderPayload(
      doseId: doseId,
      medicationName: '$medicationName ($elderlyUsername)',
      scheduledEpochMs: DateTime.now().millisecondsSinceEpoch,
      stage: stage,
    ).encode();

    await _plugin.show(
      _doseNotificationId(doseId: doseId, stage: 10 + stage),
      title,
      body,
      _detailsForStage(stage: stage),
      payload: payload,
    );
  }

  Future<void> writeDoseAcknowledgementToFirestore({
    required String elderlyUsername,
    required String doseId,
    required int scheduledEpochMs,
  }) async {
    final u = elderlyUsername.trim();
    if (u.isEmpty) return;
    await FirebaseFirestore.instance
        .collection('elderly')
        .doc(u)
        .collection('doseAcks')
        .doc(doseId)
        .set(<String, dynamic>{
      'doseId': doseId,
      'scheduledEpochMs': scheduledEpochMs,
      'ackAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> cancelEscalationSeries({required String doseId}) async {
    for (int stage = 0; stage < 3; stage++) {
      await _plugin.cancel(_doseNotificationId(doseId: doseId, stage: stage));
    }
  }

  Future<void> cancelReminder(int id) => _plugin.cancel(id);

  Future<List<PendingNotificationRequest>> pendingReminders() =>
      _plugin.pendingNotificationRequests();
}

