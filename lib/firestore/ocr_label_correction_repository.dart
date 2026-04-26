import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/device_user_id_store.dart';
import '../state/session_store.dart';
import 'ocr_label_correction_model.dart';

class OcrLabelCorrectionRepository {
  OcrLabelCorrectionRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  static String docIdForNormalizedKey(String normalizedKey) {
    final bytes = utf8.encode(normalizedKey);
    return sha256.convert(bytes).toString();
  }

  Future<CollectionReference<Map<String, dynamic>>> _collectionResolved(
    BuildContext context,
  ) async {
    final session = context.read<SessionStore>();
    final username = session.username?.trim() ?? '';
    if (session.role == 'elderly' && username.isNotEmpty) {
      return _firestore
          .collection('elderly')
          .doc(username)
          .collection('ocrLabelCorrections');
    }
    final userId = await DeviceUserIdStore.getOrCreate();
    return _firestore.collection('users').doc(userId).collection('ocrLabelCorrections');
  }

  /// Looks up saved corrections for this exact raw OCR block (normalized key).
  Future<OcrLabelCorrection?> getForRawOcr(
    BuildContext context,
    String rawOcrText,
  ) async {
    final norm = OcrLabelCorrection.normalizeOcrKey(rawOcrText);
    if (norm.isEmpty) return null;
    final docId = docIdForNormalizedKey(norm);
    final col = await _collectionResolved(context);
    final snap = await col.doc(docId).get();
    if (!snap.exists || snap.data() == null) return null;
    return OcrLabelCorrection.fromDoc(snap.id, snap.data()!);
  }

  /// Saves or updates the correct name / dosage / instructions for this photo’s OCR text.
  Future<void> upsertCorrection({
    required BuildContext context,
    required String rawOcrText,
    required String correctName,
    required String correctDosage,
    required String correctInstructions,
  }) async {
    final norm = OcrLabelCorrection.normalizeOcrKey(rawOcrText);
    if (norm.isEmpty) return;

    final docId = docIdForNormalizedKey(norm);
    final col = await _collectionResolved(context);

    final correction = OcrLabelCorrection(
      id: docId,
      rawOcrText: rawOcrText.trim(),
      correctName: correctName.trim(),
      correctDosage: correctDosage.trim(),
      correctInstructions: correctInstructions.trim(),
    );

    await col.doc(docId).set(correction.toFirestore(), SetOptions(merge: true));
  }

  Future<void> deleteCorrection({
    required BuildContext context,
    required String docId,
  }) async {
    final col = await _collectionResolved(context);
    await col.doc(docId).delete();
  }

  /// Newest first; use with [StreamBuilder] after awaiting once in [State].
  Future<Stream<QuerySnapshot<Map<String, dynamic>>>> openSnapshots(
    BuildContext context,
  ) async {
    final col = await _collectionResolved(context);
    return col.orderBy('updatedAt', descending: true).snapshots();
  }
}
