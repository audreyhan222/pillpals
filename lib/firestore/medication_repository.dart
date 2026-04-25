import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../camera/pill_details.dart';
import '../state/device_user_id_store.dart';

class MedicationRepository {
  MedicationRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

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

