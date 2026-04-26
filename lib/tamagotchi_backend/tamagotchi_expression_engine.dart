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
  double get happiness => _state.happiness;

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
    double happinessDelta = 0.0,
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
      _state = _state.copyWith(
        events: updated,
        happinessOffset: _state.happinessOffset + happinessDelta,
      );
      _recomputeExpression(now: now);
      return;
    }

    final updated = Map<String, DoseEvent>.from(_state.events);
    updated[doseId] = existing.copyWith(takenAt: now, missed: false);
    _state = _state.copyWith(
      events: updated,
      happinessOffset: _state.happinessOffset + happinessDelta,
    );
    _recomputeExpression(now: now);
  }

  /// Called when the +5 minute (missed) notification is triggered.
  /// Drops happiness by 25% immediately.
  void applyMissedReminderPenalty() {
    applyHappinessPenalty(0.25);
  }

  /// Drops happiness by [amount01] (0..1) immediately.
  void applyHappinessPenalty(double amount01) {
    _ensureToday();
    final now = _now();
    final current = _clamp01(_baseHappiness01(now) + _state.happinessOffset);
    final newHappiness = _clamp01(current - amount01);
    _state = _state.copyWith(happinessOffset: newHappiness - _baseHappiness01(now));
    _recomputeExpression(now: now);
  }

  void applyHappinessDelta(double delta) {
    _ensureToday();
    final now = _now();
    final current = _clamp01(_baseHappiness01(now) + _state.happinessOffset);
    final newHappiness = _clamp01(current + delta);
    _state = _state.copyWith(happinessOffset: newHappiness - _baseHappiness01(now));
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
    final now = _now();
    _applyOverduePenalties(now);
    _recomputeExpression(now: now);
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

    final happiness = _clamp01(_baseHappiness01(currentTime) + _state.happinessOffset);
    _state = _state.copyWith(happiness: happiness);

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

    final expr = switch (happiness) {
      >= 0.85 => PalExpression.happy,
      >= 0.55 => PalExpression.neutral,
      >= 0.30 => PalExpression.sad,
      _ => PalExpression.depressed,
    };
    _state = _state.copyWith(expression: expr, clearSadUntil: true);
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

  /// Baseline mood if the user is **not** offsetting with on-time doses.
  /// Starts at neutral (~55% bar); by late evening the base line alone is **well
  /// below half** of that start (>50% relative drop) — [happinessOffset] from
  /// taking pills on time pulls the pal back up.
  double _baseHappiness01(DateTime t) {
    final dayStart = DateTime(t.year, t.month, t.day);
    final elapsedSec = t.difference(dayStart).inSeconds.clamp(0, 86400);
    final frac = elapsedSec / 86400.0;
    final eased = 1.0 - ((1.0 - frac) * (1.0 - frac)); // easeOutQuad
    const startNeutral = 0.55; // ~55% at local day start; matches neutral band
    // ~20% at day end: (0.55-0.20)/0.55 ≈ 64% drop from morning baseline
    // (i.e. more than 50% unless happinessOffset from on-time usage lifts it).
    const endOfDay = 0.20;
    return _clamp01(startNeutral - (startNeutral - endOfDay) * eased);
  }

  double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

  void _applyOverduePenalties(DateTime now) {
    // Applies the +5m (-0.25) and +10m (-0.30) penalties while the app is running.
    // (Local notifications cannot run app logic at fire-time if the app is closed.)
    var happiness = _clamp01(_baseHappiness01(now) + _state.happinessOffset);
    final p5 = Set<String>.from(_state.penalized5m);
    final p10 = Set<String>.from(_state.penalized10m);

    for (final e in _state.events.values) {
      if (e.takenAt != null) continue;
      if (e.missed) continue;
      final doseId = e.doseId;
      final five = e.notificationAt.add(const Duration(minutes: 5));
      final ten = e.notificationAt.add(const Duration(minutes: 10));

      if (!p5.contains(doseId) && now.isAfter(five)) {
        happiness = _clamp01(happiness - 0.25);
        p5.add(doseId);
      }
      if (!p10.contains(doseId) && now.isAfter(ten)) {
        happiness = _clamp01(happiness - 0.30);
        p10.add(doseId);
      }
    }

    final newOffset = happiness - _baseHappiness01(now);
    _state = _state.copyWith(
      happinessOffset: newOffset,
      penalized5m: p5,
      penalized10m: p10,
    );
  }
}
