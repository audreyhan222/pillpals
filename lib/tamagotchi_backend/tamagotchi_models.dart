import 'package:flutter/foundation.dart';

import '../pals/pill_pal.dart';

@immutable
class DoseEvent {
  const DoseEvent({
    required this.doseId,
    required this.notificationAt,
    this.takenAt,
    this.missed = false,
  });

  final String doseId;
  final DateTime notificationAt;
  final DateTime? takenAt;
  final bool missed;

  Duration? get delayAfterNotification {
    if (takenAt == null) return null;
    return takenAt!.difference(notificationAt);
  }

  DoseEvent copyWith({
    DateTime? takenAt,
    bool? missed,
  }) {
    return DoseEvent(
      doseId: doseId,
      notificationAt: notificationAt,
      takenAt: takenAt ?? this.takenAt,
      missed: missed ?? this.missed,
    );
  }
}

@immutable
class TamagotchiDailyState {
  const TamagotchiDailyState({
    required this.dayKey,
    required this.expectedDoseCount,
    required this.events,
    required this.expression,
    this.sadUntil,
  });

  final DateTime dayKey;
  final int expectedDoseCount;
  final Map<String, DoseEvent> events;
  final PalExpression expression;
  final DateTime? sadUntil;

  factory TamagotchiDailyState.initial({
    required DateTime dayKey,
    required int expectedDoseCount,
  }) {
    return TamagotchiDailyState(
      dayKey: DateTime(dayKey.year, dayKey.month, dayKey.day),
      expectedDoseCount: expectedDoseCount,
      events: const {},
      expression: PalExpression.neutral,
    );
  }

  TamagotchiDailyState copyWith({
    DateTime? dayKey,
    int? expectedDoseCount,
    Map<String, DoseEvent>? events,
    PalExpression? expression,
    DateTime? sadUntil,
    bool clearSadUntil = false,
  }) {
    return TamagotchiDailyState(
      dayKey: dayKey ?? this.dayKey,
      expectedDoseCount: expectedDoseCount ?? this.expectedDoseCount,
      events: events ?? this.events,
      expression: expression ?? this.expression,
      sadUntil: clearSadUntil ? null : (sadUntil ?? this.sadUntil),
    );
  }
}
