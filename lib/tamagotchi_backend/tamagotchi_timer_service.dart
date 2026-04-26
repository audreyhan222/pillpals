import 'dart:async';

import '../pals/pill_pal.dart';
import 'tamagotchi_expression_engine.dart';
import 'tamagotchi_models.dart';

class TamagotchiTimerService {
  TamagotchiTimerService({
    required TamagotchiExpressionEngine engine,
    Duration tickInterval = const Duration(minutes: 1),
    void Function(PalExpression expression)? onExpressionChanged,
    void Function()? onTick,
  })  : _engine = engine,
        _tickInterval = tickInterval,
        _onExpressionChanged = onExpressionChanged,
        _onTick = onTick;

  final TamagotchiExpressionEngine _engine;
  final Duration _tickInterval;
  final void Function(PalExpression expression)? _onExpressionChanged;
  final void Function()? _onTick;

  Timer? _timer;
  PalExpression? _lastExpression;

  TamagotchiDailyState get state => _engine.state;

  void start() {
    _lastExpression = _engine.expression;
    _timer?.cancel();
    _timer = Timer.periodic(_tickInterval, (_) {
      _engine.tick();
      _onTick?.call();
      _emitIfChanged();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
  }

  void setExpectedDoseCount(int count) {
    _engine.setExpectedDoseCount(count);
    _emitIfChanged();
  }

  void onDoseNotification({
    required String doseId,
    DateTime? at,
  }) {
    _engine.registerDoseNotification(doseId: doseId, at: at);
    _emitIfChanged();
  }

  void onDoseTaken({
    required String doseId,
    DateTime? at,
  }) {
    _engine.registerDoseTaken(doseId: doseId, at: at);
    _emitIfChanged();
  }

  void onDoseMissed({
    required String doseId,
  }) {
    _engine.registerDoseMissed(doseId: doseId);
    _emitIfChanged();
  }

  void forceDailyReset({DateTime? date}) {
    _engine.startNewDay(date: date);
    _emitIfChanged();
  }

  void _emitIfChanged() {
    final current = _engine.expression;
    if (_lastExpression != current) {
      _lastExpression = current;
      _onExpressionChanged?.call(current);
    }
  }
}
