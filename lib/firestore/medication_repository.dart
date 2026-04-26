import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../camera/pill_details.dart';
import '../firestore/elderly_medication_catalog_repository.dart';
import '../state/device_user_id_store.dart';
import '../state/session_store.dart';

class MedicationRepository {
  MedicationRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// For elderly users, medication data should live under the elderly user doc.
  /// For non-elderly (caregiver/demo), we keep the existing per-device path.
  Future<void> addMedicationFromScanForSession({
    required BuildContext context,
    required PillDetails details,
  }) async {
    final session = context.read<SessionStore>();
    final role = session.role;
    final username = session.username?.trim();

    if (role == 'elderly' && username != null && username.isNotEmpty) {
      final times = details.times.toList()
        ..sort((a, b) => (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute));
      final timesMinutes = times.map((t) => t.hour * 60 + t.minute).toList();
      final schedule = times.isEmpty
          ? ''
          : 'Daily at ${times.map((t) => t.format(context)).join(', ')}';

      // We don’t know quantity-left from scan; default to 0 and allow manual edit.
      await ElderlyMedicationCatalogRepository(firestore: _firestore).upsertMedication(
        elderlyUsername: username,
        name: details.name,
        totalLeft: 0,
        dosageAmount: details.dosage,
        dosageSchedule: schedule,
        timesMinutes: timesMinutes,
      );
      return;
    }

    // Fallback: old per-device storage.
    await addMedicationFromScan(details: details);
  }

  Future<DocumentReference<Map<String, dynamic>>> addMedicationFromScan({
    required PillDetails details,
  }) async {
    final userId = await DeviceUserIdStore.getOrCreate();

    int minutesOfDay(TimeOfDay t) => t.hour * 60 + t.minute;

    final times = details.times.map(minutesOfDay).toList()..sort();

    return _firestore
        .collection('users')
        .doc(userId)
        .collection('medications')
        .add(<String, dynamic>{
      'name': details.name,
      'dosage': details.dosage,
      'instructions': details.instructions,
      'times': times, // list<int> minutes since midnight
      'rawText': details.rawText,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

