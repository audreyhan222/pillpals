import 'package:flutter/material.dart';

class PillDetails {
  const PillDetails({
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.times,
    required this.rawText,
  });

  final String name;
  final String dosage;
  final String instructions;
  final List<TimeOfDay> times;
  final String rawText;

  PillDetails copyWith({
    String? name,
    String? dosage,
    String? instructions,
    List<TimeOfDay>? times,
    String? rawText,
  }) {
    return PillDetails(
      name: name ?? this.name,
      dosage: dosage ?? this.dosage,
      instructions: instructions ?? this.instructions,
      times: times ?? this.times,
      rawText: rawText ?? this.rawText,
    );
  }
}
