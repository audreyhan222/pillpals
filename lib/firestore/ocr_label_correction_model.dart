import 'package:cloud_firestore/cloud_firestore.dart';

/// User-corrected field values for a block of OCR text (one analysis path).
class OcrLabelCorrection {
  const OcrLabelCorrection({
    required this.id,
    required this.rawOcrText,
    required this.correctName,
    required this.correctDosage,
    required this.correctInstructions,
    this.updatedAt,
  });

  final String id;
  final String rawOcrText;
  final String correctName;
  final String correctDosage;
  final String correctInstructions;
  final DateTime? updatedAt;

  static String normalizeOcrKey(String s) {
    return s
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .toLowerCase();
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'rawOcrText': rawOcrText,
      'normalizedOcrKey': OcrLabelCorrection.normalizeOcrKey(rawOcrText),
      'correctName': correctName,
      'correctDosage': correctDosage,
      'correctInstructions': correctInstructions,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory OcrLabelCorrection.fromDoc(String id, Map<String, dynamic> data) {
    return OcrLabelCorrection(
      id: id,
      rawOcrText: (data['rawOcrText'] as String?)?.trim() ?? '',
      correctName: (data['correctName'] as String?)?.trim() ?? '',
      correctDosage: (data['correctDosage'] as String?)?.trim() ?? '',
      correctInstructions: (data['correctInstructions'] as String?)?.trim() ?? '',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
