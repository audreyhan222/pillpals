import '../pals/pill_pal.dart';
import 'tamagotchi_models.dart';

class TamagotchiExpressionEngine {
  TamagotchiExpressionEngine({
    required int expectedDoseCount,
    DateTime Function()? now,
  })  : _now = now ?? DateTime.now,
        _state = TamagotchiDailyState.initial(
          dayKey: (now ?? DateTime.now)(),
          expectedDoseCount: expectedDoseCount,
        );

  final DateTime Function() _now;
  TamagotchiDailyState _state;

  TamagotchiDailyState get state => _state;
  PalExpression get expression => _state.expression;

  void setExpectedDoseCount(int count) {
    _ensureToday();
    _state = _state.copyWith(expectedDoseCount: count);
    _recomputeExpression();
  }

  void startNewDay({DateTime? date}) {
    final day = date ?? _now();
    _state = TamagotchiDailyState.initial(
      dayKey: DateTime(day.year, day.month, day.day),
      expectedDoseCount: _state.expectedDoseCount,
    );
  }

  void registerDoseNotification({
    required String doseId,
    DateTime? at,
  }) {
    _ensureToday();
    final notificationAt = at ?? _now();
    final updated = Map<String, DoseEvent>.from(_state.events);
    updated[doseId] = DoseEvent(
      doseId: doseId,
      notificationAt: notificationAt,
    );
    _state = _state.copyWith(events: updated);
    _recomputeExpression();
  }

  void registerDoseTaken({
    required String doseId,
    DateTime? at,
  }) {
    _ensureToday();
    final now = at ?? _now();
    final existing = _state.events[doseId];
    if (existing == null) {
      // If there is no prior notification tracked, use this timestamp as both.
      final updated = Map<String, DoseEvent>.from(_state.events);
      updated[doseId] = DoseEvent(
        doseId: doseId,
        notificationAt: now,
        takenAt: now,
      );
      _state = _state.copyWith(events: updated);
      _recomputeExpression(now: now);
      return;
    }

    final updated = Map<String, DoseEvent>.from(_state.events);
    updated[doseId] = existing.copyWith(takenAt: now, missed: false);
    _state = _state.copyWith(events: updated);
    _recomputeExpression(now: now);
  }

  void registerDoseMissed({
    required String doseId,
  }) {
    _ensureToday();
    final existing = _state.events[doseId];
    final updated = Map<String, DoseEvent>.from(_state.events);
    if (existing == null) {
      updated[doseId] = DoseEvent(
        doseId: doseId,
        notificationAt: _now(),
        missed: true,
      );
    } else {
      updated[doseId] = existing.copyWith(missed: true);
    }
    _state = _state.copyWith(events: updated);
    _recomputeExpression();
  }

  void tick() {
    _ensureToday();
    _recomputeExpression();
  }

  void _ensureToday() {
    final now = _now();
    final dayNow = DateTime(now.year, now.month, now.day);
    if (dayNow != _state.dayKey) {
      startNewDay(date: now);
    }
  }

  void _recomputeExpression({DateTime? now}) {
    final currentTime = now ?? _now();
    final events = _state.events.values;

    // Rule: any fully missed dose keeps expression depressed for the day.
    final hasMissedDose = events.any((event) => event.missed);
    if (hasMissedDose) {
      _state = _state.copyWith(expression: PalExpression.depressed, clearSadUntil: true);
      return;
    }

    // Rule: if any dose is >= 30 minutes late, become sad.
    final lateEvents = events.where(
      (event) => event.delayAfterNotification != null && event.delayAfterNotification! >= const Duration(minutes: 30),
    );

    DateTime? sadUntil;
    for (final event in lateEvents) {
      final delay = event.delayAfterNotification!;
      final candidateSadUntil = event.takenAt!.add(delay);
      if (sadUntil == null || candidateSadUntil.isAfter(sadUntil)) {
        sadUntil = candidateSadUntil;
      }
    }

    if (sadUntil != null && currentTime.isBefore(sadUntil)) {
      _state = _state.copyWith(
        expression: PalExpression.sad,
        sadUntil: sadUntil,
      );
      return;
    }

    final tookAllExpectedDoses = _tookAllExpectedDoses();
    final allTakenWithin20Minutes = _allTakenWithin20Minutes();

    // Rule: happy when all required doses are taken and none are >20 mins late.
    if (tookAllExpectedDoses && allTakenWithin20Minutes) {
      _state = _state.copyWith(expression: PalExpression.happy, clearSadUntil: true);
      return;
    }

    // Default: neutral, and every new day starts from neutral.
    _state = _state.copyWith(expression: PalExpression.neutral, clearSadUntil: true);
  }

  bool _tookAllExpectedDoses() {
    if (_state.expectedDoseCount <= 0) return false;
    if (_state.events.length < _state.expectedDoseCount) return false;

    final takenCount = _state.events.values.where((event) => event.takenAt != null && !event.missed).length;
    return takenCount >= _state.expectedDoseCount;
  }

  bool _allTakenWithin20Minutes() {
    final takenEvents = _state.events.values.where((event) => event.takenAt != null && !event.missed);
    if (takenEvents.isEmpty) return false;

    return takenEvents.every((event) => event.delayAfterNotification! <= const Duration(minutes: 20));
  }
}
