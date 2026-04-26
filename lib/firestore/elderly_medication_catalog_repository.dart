import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class ElderlyMedicationCatalogEntry {
  const ElderlyMedicationCatalogEntry({
    required this.id,
    required this.name,
    required this.totalLeft,
    required this.dosageAmount,
    required this.dosageSchedule,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;

  /// Total quantity remaining (user-defined units: pills, capsules, etc.)
  final int totalLeft;

  /// E.g. "500mg", "1 tablet", "2 puffs".
  final String dosageAmount;

  /// E.g. "Daily at 9am + 9pm", "Mon/Wed/Fri", "Every 8 hours".
  final String dosageSchedule;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  static ElderlyMedicationCatalogEntry fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};

    int readInt(String key) {
      final v = data[key];
      if (v is int) return v;
      if (v is num) return v.round();
      return 0;
    }

    String readString(String key) {
      final v = data[key];
      return v is String ? v : '';
    }

    DateTime? readTimestamp(String key) {
      final v = data[key];
      if (v is Timestamp) return v.toDate();
      return null;
    }

    return ElderlyMedicationCatalogEntry(
      id: doc.id,
      name: readString('name'),
      totalLeft: readInt('totalLeft'),
      dosageAmount: readString('dosageAmount'),
      dosageSchedule: readString('dosageSchedule'),
      createdAt: readTimestamp('createdAt'),
      updatedAt: readTimestamp('updatedAt'),
    );
  }
}

class ElderlyMedicationCatalogRepository {
  ElderlyMedicationCatalogRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _catalogRef({
    required String elderlyUsername,
  }) {
    final u = elderlyUsername.trim();
    if (u.isEmpty) {
      throw ArgumentError('elderlyUsername is required');
    }
    return _firestore
        .collection('elderly')
        .doc(u)
        .collection('medicationCatalog');
  }

  /// Uses the medication name as the "category" key.
  ///
  /// Firestore doc IDs cannot contain '/', so we normalize.
  String _docIdForName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return 'med';

    final lower = trimmed.toLowerCase();
    final buf = StringBuffer();
    for (int i = 0; i < lower.length; i++) {
      final c = lower.codeUnitAt(i);
      final isAz = c >= 97 && c <= 122;
      final is09 = c >= 48 && c <= 57;
      if (isAz || is09) {
        buf.writeCharCode(c);
      } else {
        // keep doc IDs stable while avoiding illegal/separator chars
        buf.write('_');
      }
    }
    final normalized = buf.toString().replaceAll(RegExp(r'_+'), '_');
    return normalized.length > 80 ? normalized.substring(0, 80) : normalized;
  }

  /// Create/update a medication category for an elderly user.
  ///
  /// Firestore path:
  /// `elderly/{elderlyUsername}/medicationCatalog/{normalizedName}`
  Future<DocumentReference<Map<String, dynamic>>> upsertMedication({
    required String elderlyUsername,
    required String name,
    required int totalLeft,
    required String dosageAmount,
    required String dosageSchedule,
    List<int>? timesMinutes,
    String? instructions,
  }) async {
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Medication name is required');
    }

    final ref =
        _catalogRef(elderlyUsername: elderlyUsername).doc(_docIdForName(trimmedName));

    await ref.set(
      <String, dynamic>{
        'name': trimmedName,
        'totalLeft': totalLeft,
        'dosageAmount': dosageAmount.trim(),
        'dosageSchedule': dosageSchedule.trim(),
        if (instructions != null) 'instructions': instructions.trim(),
        if (timesMinutes != null) 'timesMinutes': timesMinutes,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return ref;
  }

  /// Decrement/increment remaining quantity safely.
  Future<void> incrementTotalLeft({
    required String elderlyUsername,
    required String medicationName,
    required int delta,
  }) async {
    final trimmedName = medicationName.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('Medication name is required');
    }

    final ref =
        _catalogRef(elderlyUsername: elderlyUsername).doc(_docIdForName(trimmedName));
    await ref.set(
      <String, dynamic>{
        'name': trimmedName,
        'totalLeft': FieldValue.increment(delta),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Stream<List<ElderlyMedicationCatalogEntry>> watchCatalog({
    required String elderlyUsername,
  }) {
    return _catalogRef(elderlyUsername: elderlyUsername)
        .orderBy('name')
        .snapshots()
        .map(
          (snap) => snap.docs.map((d) => ElderlyMedicationCatalogEntry.fromDoc(d)).toList(),
        );
  }

  Future<void> deleteMedication({
    required String elderlyUsername,
    required String medicationName,
  }) async {
    final trimmedName = medicationName.trim();
    if (trimmedName.isEmpty) return;
    await _catalogRef(elderlyUsername: elderlyUsername)
        .doc(_docIdForName(trimmedName))
        .delete();
  }
}

