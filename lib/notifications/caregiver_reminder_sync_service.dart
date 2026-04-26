import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'notification_service.dart';

/// Caregiver-side reminder mirroring based on Firestore connect-code linking.
///
/// This is a best-effort MVP: it schedules local escalation notifications on the
/// caregiver device for linked elderly users. When an elderly user acknowledges
/// a dose, we cancel the caregiver’s series for that doseId.
class CaregiverReminderSyncService {
  CaregiverReminderSyncService._();
  static final CaregiverReminderSyncService instance = CaregiverReminderSyncService._();

  StreamSubscription? _caretakerSub;
  final Map<String, StreamSubscription> _catalogSubs = {};
  final Map<String, StreamSubscription> _ackSubs = {};

  final Set<String> _scheduledDoseKeys = <String>{};

  Future<void> start({
    required String caregiverUsername,
  }) async {
    if (kIsWeb) return;
    final caregiver = caregiverUsername.trim();
    if (caregiver.isEmpty) return;

    await stop();

    _caretakerSub = FirebaseFirestore.instance
        .collection('caretaker')
        .doc(caregiver)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      final patients = (data?['patients'] as List?)?.cast<dynamic>() ?? const [];
      final elderlyUsernames = <String>{};
      for (final p in patients) {
        final m = p is Map ? p : null;
        final elderlyUsername = (m?['elderlyUsername'] as String?)?.trim() ?? '';
        if (elderlyUsername.isNotEmpty) elderlyUsernames.add(elderlyUsername);
      }

      // Remove subs for unlinked patients.
      final existing = _catalogSubs.keys.toSet();
      for (final u in existing.difference(elderlyUsernames)) {
        _catalogSubs.remove(u)?.cancel();
        _ackSubs.remove(u)?.cancel();
      }

      // Add subs for new patients.
      for (final elderly in elderlyUsernames) {
        _catalogSubs.putIfAbsent(elderly, () => _watchCatalog(elderly));
        _ackSubs.putIfAbsent(elderly, () => _watchAcks(elderly));
      }
    });
  }

  StreamSubscription _watchCatalog(String elderlyUsername) {
    return FirebaseFirestore.instance
        .collection('elderly')
        .doc(elderlyUsername)
        .collection('medicationCatalog')
        .snapshots()
        .listen((snap) async {
      for (final doc in snap.docs) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim() ?? '';
        final dosage = (data['dosageAmount'] as String?)?.trim() ?? '';
        final times = (data['timesMinutes'] as List?)?.cast<dynamic>() ?? const [];
        if (name.isEmpty) continue;
        for (final t in times) {
          final minutes = t is int ? t : (t is num ? t.round() : null);
          if (minutes == null) continue;
          if (minutes < 0 || minutes >= 24 * 60) continue;

          final hour = minutes ~/ 60;
          final minute = minutes % 60;
          final time = TimeOfDay(hour: hour, minute: minute);

          // Caregiver-only doseId namespace.
          final doseId =
              'cg_${elderlyUsername.toLowerCase()}_${name.toLowerCase()}_${hour.toString().padLeft(2, '0')}${minute.toString().padLeft(2, '0')}';
          final key = '$doseId@${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}';
          if (_scheduledDoseKeys.contains(key)) continue;
          _scheduledDoseKeys.add(key);

          // Only schedule escalation stages (5m + 15m) for caregivers.
          await NotificationService.instance.scheduleEscalatingDoseReminder(
            doseId: doseId,
            medicationName: '$name ($elderlyUsername)',
            dosageText: dosage,
            time: time,
          );
        }
      }
    });
  }

  StreamSubscription _watchAcks(String elderlyUsername) {
    return FirebaseFirestore.instance
        .collection('elderly')
        .doc(elderlyUsername)
        .collection('doseAcks')
        .snapshots()
        .listen((snap) async {
      for (final doc in snap.docs) {
        final data = doc.data();
        final doseId = (data['doseId'] as String?)?.trim() ?? '';
        if (doseId.isEmpty) continue;

        // Cancel any caregiver notifications that used this doseId.
        // NOTE: caregiver doseIds are prefixed with 'cg_' so we cancel by that id.
        final cgDoseId = doseId.startsWith('cg_')
            ? doseId
            : 'cg_${elderlyUsername.toLowerCase()}_${doseId.toLowerCase()}';
        await NotificationService.instance.cancelEscalationSeries(doseId: cgDoseId);
      }
    });
  }

  Future<void> stop() async {
    await _caretakerSub?.cancel();
    _caretakerSub = null;
    for (final sub in _catalogSubs.values) {
      await sub.cancel();
    }
    for (final sub in _ackSubs.values) {
      await sub.cancel();
    }
    _catalogSubs.clear();
    _ackSubs.clear();
  }
}

