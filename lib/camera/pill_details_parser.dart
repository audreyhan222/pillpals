import 'package:flutter/material.dart';

import 'pill_details.dart';

class PillDetailsParser {
  static PillDetails parse(String text) {
    final normalized = text.trim();
    final lines = normalized
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final name = _extractName(lines);
    final dosage = _extractDosage(lines);
    final instructions = _extractInstructions(lines);
    final times = _extractTimes(lines, normalized);

    return PillDetails(
      name: name,
      dosage: dosage,
      instructions: instructions,
      times: times,
      rawText: normalized,
    );
  }

  static String _extractName(List<String> lines) {
    if (lines.isEmpty) return '';
    final first = lines.first;
    if (first.toLowerCase().startsWith('name:')) {
      return first.substring(5).trim();
    }
    return first;
  }

  static String _extractDosage(List<String> lines) {
    final dosageRegex = RegExp(
      r'(\d+(\.\d+)?\s?(mg|mcg|g|ml|units?|tablets?|capsules?))',
      caseSensitive: false,
    );

    for (final line in lines) {
      if (line.toLowerCase().contains('dosage')) {
        final split = line.split(':');
        if (split.length > 1) return split.sublist(1).join(':').trim();
      }
      final match = dosageRegex.firstMatch(line);
      if (match != null) return match.group(0)!.trim();
    }
    return '';
  }

  static String _extractInstructions(List<String> lines) {
    for (final line in lines) {
      final lower = line.toLowerCase();
      if (lower.startsWith('instructions:')) {
        return line.substring('instructions:'.length).trim();
      }
      if (lower.contains('take') ||
          lower.contains('with food') ||
          lower.contains('after meals') ||
          lower.contains('before bed')) {
        return line;
      }
    }
    return '';
  }

  static List<TimeOfDay> _extractTimes(List<String> lines, String fullText) {
    final results = <TimeOfDay>{};

    final timeRegex = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b', caseSensitive: false);
    for (final line in lines) {
      for (final match in timeRegex.allMatches(line)) {
        final hour = int.parse(match.group(1)!);
        final minute = int.parse(match.group(2) ?? '0');
        final period = match.group(3)!.toLowerCase();
        final hour24 = _to24Hour(hour, period);
        results.add(TimeOfDay(hour: hour24, minute: minute));
      }
    }

    final lowerText = fullText.toLowerCase();
    if (results.isEmpty) {
      if (lowerText.contains('once daily')) {
        results.add(const TimeOfDay(hour: 9, minute: 0));
      } else if (lowerText.contains('twice daily')) {
        results
          ..add(const TimeOfDay(hour: 9, minute: 0))
          ..add(const TimeOfDay(hour: 21, minute: 0));
      } else if (lowerText.contains('three times daily')) {
        results
          ..add(const TimeOfDay(hour: 8, minute: 0))
          ..add(const TimeOfDay(hour: 13, minute: 0))
          ..add(const TimeOfDay(hour: 20, minute: 0));
      }
    }

    final sorted = results.toList()
      ..sort((a, b) {
        final aMinutes = a.hour * 60 + a.minute;
        final bMinutes = b.hour * 60 + b.minute;
        return aMinutes.compareTo(bMinutes);
      });
    return sorted;
  }

  static int _to24Hour(int hour, String period) {
    if (period == 'am') return hour == 12 ? 0 : hour;
    return hour == 12 ? 12 : hour + 12;
  }
}
