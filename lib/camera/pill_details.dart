import 'package:flutter/material.dart';

class PillDetails {
  const PillDetails({
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.times,
    required this.intervalMinutes,
    required this.rawText,
  });

  final String name;
  final String dosage;
  final String instructions;
  final List<TimeOfDay> times;
  /// Interval between doses in minutes. 0 means "unknown / not interval-based".
  final int intervalMinutes;
  final String rawText;

  PillDetails copyWith({
    String? name,
    String? dosage,
    String? instructions,
    List<TimeOfDay>? times,
    int? intervalMinutes,
    String? rawText,
  }) {
    return PillDetails(
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      instructions: instructions ?? this.instructions,
      times: times ?? this.times,
      intervalMinutes: intervalMinutes ?? this.intervalMinutes,
      rawText: rawText ?? this.rawText,
    );
  }
}
