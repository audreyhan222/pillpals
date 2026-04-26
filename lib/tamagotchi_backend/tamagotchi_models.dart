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
    required this.happiness,
    required this.happinessOffset,
    required this.penalized5m,
    required this.penalized10m,
    this.sadUntil,
  });

  final DateTime dayKey;
  final int expectedDoseCount;
  final Map<String, DoseEvent> events;
  final PalExpression expression;
  /// 0..1 current happiness value.
  final double happiness;
  /// Manual +/- adjustments that persist through the day (missed reminders, etc).
  final double happinessOffset;
  /// Tracks which doseIds already applied the +5m penalty.
  final Set<String> penalized5m;
  /// Tracks which doseIds already applied the +10m penalty.
  final Set<String> penalized10m;
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
      // Aligned with [_baseHappiness01] at local midnight + engine thresholds (neutral band).
      happiness: 0.55,
      happinessOffset: 0.0,
      penalized5m: const <String>{},
      penalized10m: const <String>{},
    );
  }

  TamagotchiDailyState copyWith({
    DateTime? dayKey,
    int? expectedDoseCount,
    Map<String, DoseEvent>? events,
    PalExpression? expression,
    double? happiness,
    double? happinessOffset,
    Set<String>? penalized5m,
    Set<String>? penalized10m,
    DateTime? sadUntil,
    bool clearSadUntil = false,
  }) {
    return TamagotchiDailyState(
      dayKey: dayKey ?? this.dayKey,
      expectedDoseCount: expectedDoseCount ?? this.expectedDoseCount,
      events: events ?? this.events,
      expression: expression ?? this.expression,
      happiness: happiness ?? this.happiness,
      happinessOffset: happinessOffset ?? this.happinessOffset,
      penalized5m: penalized5m ?? this.penalized5m,
      penalized10m: penalized10m ?? this.penalized10m,
      sadUntil: clearSadUntil ? null : (sadUntil ?? this.sadUntil),
    );
  }
}
