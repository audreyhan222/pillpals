import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists which dose IDs were taken on which day.
///
/// Storage format:
/// - key: yyyy-mm-dd
/// - value: list of doseIds taken that day
class PillCompletionStore extends ChangeNotifier {
  static const _storageKey = 'pill_completion_v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  bool _bootstrapped = false;
  bool get bootstrapped => _bootstrapped;

  final Map<String, Set<String>> _takenByDay = {};

  static String dayKey(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  Set<String> takenDoseIdsForDay(DateTime date) {
    return Set<String>.from(_takenByDay[dayKey(date)] ?? const <String>{});
  }

  bool isDoseTaken({required DateTime date, required String doseId}) {
    final set = _takenByDay[dayKey(date)];
    if (set == null) return false;
    return set.contains(doseId);
  }

  bool isDayComplete({required DateTime date, required int expectedDoseCount}) {
    if (expectedDoseCount <= 0) return false;
    return takenDoseIdsForDay(date).length >= expectedDoseCount;
  }

  Future<void> bootstrap() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw == null || raw.trim().isEmpty) {
        _bootstrapped = true;
        notifyListeners();
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _takenByDay.clear();
        for (final entry in decoded.entries) {
          final key = entry.key?.toString();
          if (key == null) continue;
          final value = entry.value;
          if (value is List) {
            _takenByDay[key] = value.map((e) => e.toString()).toSet();
          }
        }
      }
    } catch (_) {
      // If storage is corrupted, don't crash the UI — start fresh.
      _takenByDay.clear();
    } finally {
      _bootstrapped = true;
      notifyListeners();
    }
  }

  Future<void> markDoseTaken({
    required DateTime date,
    required String doseId,
  }) async {
    final key = dayKey(date);
    final set = _takenByDay[key] ?? <String>{};
    final changed = set.add(doseId);
    _takenByDay[key] = set;

    if (changed) {
      await _persist();
      notifyListeners();
    }
  }

  Future<void> clearDay(DateTime date) async {
    final key = dayKey(date);
    final hadAny = _takenByDay.remove(key) != null;
    if (hadAny) {
      await _persist();
      notifyListeners();
    }
  }

  Future<void> clearAll() async {
    if (_takenByDay.isEmpty) return;
    _takenByDay.clear();
    await _storage.delete(key: _storageKey);
    notifyListeners();
  }

  Future<void> _persist() async {
    final map = <String, List<String>>{};
    for (final entry in _takenByDay.entries) {
      map[entry.key] = entry.value.toList()..sort();
    }
    await _storage.write(key: _storageKey, value: jsonEncode(map));
  }
}

