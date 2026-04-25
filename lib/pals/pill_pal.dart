import 'package:flutter/material.dart';

enum PalExpression {
  neutral('neutral', 'Neutral'),
  happy('happy', 'Happy'),
  sad('sad', 'Sad'),
  depressed('depressed', 'Depressed');

  const PalExpression(this.fileName, this.label);
  final String fileName;
  final String label;
}

class PillPal {
  const PillPal({
    required this.id,
    required this.name,
    required this.color,
  });

  final String id;
  final String name;
  final Color color;

  String assetFor(PalExpression expression) {
    return 'assets/pals/$id/${expression.fileName}.png';
  }
}

const List<PillPal> availablePillPals = [
  PillPal(id: 'cat', name: 'Milo the Cat', color: Color(0xFFBFDFFF)),
  PillPal(id: 'penguin', name: 'Penny the Penguin', color: Color(0xFFC5D4FF)),
  PillPal(id: 'bunny', name: 'Luna the Bunny', color: Color(0xFFFFEFD1)),
];
