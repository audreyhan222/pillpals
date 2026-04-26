import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/material.dart';

class DeviceCalendarService {
  DeviceCalendarService._();

  static final DeviceCalendarService instance = DeviceCalendarService._();

  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();

  Future<bool> ensurePermissions() async {
    final granted = await _plugin.requestPermissions();
    return granted.isSuccess && (granted.data ?? false);
  }

  Future<String?> _defaultWritableCalendarId() async {
    final res = await _plugin.retrieveCalendars();
    if (!res.isSuccess || res.data == null) return null;
    final calendars = res.data!;
    for (final c in calendars) {
      if (c.isReadOnly == true) continue;
      final id = c.id;
      if (id != null && id.trim().isNotEmpty) return id;
    }
    return null;
  }

  DateTime _nextOccurrence(TimeOfDay time, DateTime now) {
    final today = DateTime(now.year, now.month, now.day, time.hour, time.minute);
    if (today.isAfter(now)) return today;
    return today.add(const Duration(days: 1));
  }

  Future<void> addDailyMedicationEvents({
    required String name,
    required String dosage,
    required String instructions,
    required List<TimeOfDay> times,
  }) async {
    final calendarId = await _defaultWritableCalendarId();
    if (calendarId == null) {
      throw Exception('No writable calendar found.');
    }

    final now = DateTime.now();
    final until = now.add(const Duration(days: 365));

    final cleanName = name.trim().isEmpty ? 'Medication' : name.trim();
    final cleanDosage = dosage.trim();
    final cleanInstructions = instructions.trim();
    final descriptionParts = <String>[
      if (cleanDosage.isNotEmpty) 'Dosage: $cleanDosage',
      if (cleanInstructions.isNotEmpty) 'Instructions: $cleanInstructions',
    ];
    final description =
        descriptionParts.isEmpty ? null : descriptionParts.join('\n');

    for (final t in times) {
      final start = _nextOccurrence(t, now);
      final end = start.add(const Duration(minutes: 10));
      final event = Event(
        calendarId,
        title: cleanName,
        description: description,
        start: start,
        end: end,
        recurrenceRule: RecurrenceRule(
          RecurrenceFrequency.Daily,
          interval: 1,
          endDate: until,
        ),
      );

      final create = await _plugin.createOrUpdateEvent(event);
      if (create == null || !create.isSuccess) {
        throw Exception('Unable to create calendar event.');
      }
    }
  }
}

