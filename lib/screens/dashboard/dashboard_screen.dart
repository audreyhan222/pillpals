import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

import '../../pals/pill_pal.dart';
import '../../state/pill_completion_store.dart';
import '../../state/device_user_id_store.dart';
import '../../state/session_store.dart';
import '../../notifications/notification_service.dart';
import '../../tamagotchi_backend/tamagotchi_expression_engine.dart';
import '../../tamagotchi_backend/tamagotchi_timer_service.dart';
import '../../debug/debug_log.dart';

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Red 8:55 AM demo on Today’s pills (mock + empty state) for this user only.
const kRedTimeDemoPillUserId = 'FDB2EMND';

bool isRedTimeDemoPillUser({String? deviceUserId, String? sessionUsername}) {
  final a = (deviceUserId ?? '').trim();
  if (a == kRedTimeDemoPillUserId) return true;
  if ((sessionUsername ?? '').trim() == kRedTimeDemoPillUserId) return true;
  return false;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _petController;
  TamagotchiExpressionEngine? _engine;
  TamagotchiTimerService? _timer;
  bool _tamagotchiReady = false;
  String? _deviceUserId;
  /// Non-Firestore “Today’s pills” list (caregiver / demo); chosen after [DeviceUserIdStore] resolves.
  List<_PillItem> _mockPills = _kDefaultMockTodayPills;
  final Set<String> _registeredDoseIds = <String>{};
  StreamSubscription<NotificationEvent>? _notifSub;
  StreamSubscription? _nudgeSub;
  String? _lastNudgeDocId;

  PillPal? _selectedPal;
  String _palName = 'Pal';
  PalExpression _expression = PalExpression.neutral;
  double _happiness = 0.55;
  bool _petPromptShown = false;
  bool _palBootstrapped = false;
  bool _palBootstrapScheduled = false;

  @override
  void initState() {
    super.initState();
    _petController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrapTamagotchi());
    });

    // Caregiver nudges (Firestore → local notification).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = context.read<SessionStore>();
      final role = session.role;
      final username = session.username?.trim() ?? '';
      if (role != 'elderly' || username.isEmpty) return;

      _nudgeSub?.cancel();
      _nudgeSub = FirebaseFirestore.instance
          .collection('elderly')
          .doc(username)
          .collection('caregiverNudges')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots()
          .listen((snap) {
        // #region agent log
        DebugLog.write(
          runId: 'pre',
          hypothesisId: 'NUDGE_SPAM',
          location: 'dashboard_screen.dart:nudge_listener',
          message: 'Nudge snapshot',
          data: {'count': snap.docs.length},
        );
        // #endregion
        if (snap.docs.isEmpty) return;
        final doc = snap.docs.first;
        // #region agent log
        DebugLog.write(
          runId: 'pre',
          hypothesisId: 'NUDGE_SPAM',
          location: 'dashboard_screen.dart:nudge_listener',
          message: 'Nudge doc seen',
          data: {'docId': doc.id, 'isDuplicate': _lastNudgeDocId == doc.id},
        );
        // #endregion
        if (_lastNudgeDocId == doc.id) return;
        _lastNudgeDocId = doc.id;
        final data = doc.data();
        final title = (data['title'] as String?)?.trim() ?? 'Medication reminder';
        final body = (data['body'] as String?)?.trim() ??
            'Your caregiver sent a reminder to take your meds.';

        // #region agent log
        DebugLog.write(
          runId: 'pre',
          hypothesisId: 'NUDGE_SPAM',
          location: 'dashboard_screen.dart:nudge_listener',
          message: 'Received caregiver nudge snapshot',
          data: {
            'docId': doc.id,
            'hasTitle': title.isNotEmpty,
            'hasBody': body.isNotEmpty,
          },
        );
        // #endregion

        NotificationService.instance.showCaregiverNudgeNow(
          title: title,
          body: body,
          payload: 'caregiver_nudge:${doc.id}',
        );
      });
    });
  }

  Future<void> _bootstrapTamagotchi() async {
    try {
      final id = await DeviceUserIdStore.getOrCreate();
      if (!mounted) return;
      final uname = context.read<SessionStore>().username?.trim();
      final useRed = isRedTimeDemoPillUser(deviceUserId: id, sessionUsername: uname);
      final pills = useRed ? _kRedTimeDemoMockTodayPills : _kDefaultMockTodayPills;
      setState(() {
        _deviceUserId = id;
        _mockPills = pills;
      });
      _engine = TamagotchiExpressionEngine(expectedDoseCount: pills.length);
      for (final pill in pills) {
        _engine!.registerDoseNotification(doseId: pill.doseId);
        _registeredDoseIds.add(pill.doseId);
      }
      _timer = TamagotchiTimerService(
        engine: _engine!,
        tickInterval: const Duration(seconds: 10),
        onExpressionChanged: (expr) {
          if (!mounted) return;
          setState(() {
            _expression = expr;
            _happiness = _engine!.happiness;
          });
        },
        onTick: () {
          if (!mounted) return;
          setState(() => _happiness = _engine!.happiness);
        },
      )..start();

      _notifSub = NotificationService.instance.eventStream.listen((event) {
        final parsed = DoseReminderPayload.tryDecode(event.payload);
        if (parsed == null) return;
        if (parsed.stage == 2) {
          _engine?.applyHappinessPenalty(0.25);
          if (mounted) {
            setState(() {
              _expression = _engine!.expression;
              _happiness = _engine!.happiness;
            });
          }
        }
        if (parsed.stage == 3) {
          _engine?.applyHappinessPenalty(0.30);
          if (mounted) {
            setState(() {
              _expression = _engine!.expression;
              _happiness = _engine!.happiness;
            });
          }
        }
      });
    } catch (_) {
      if (!mounted) return;
      const pills = _kDefaultMockTodayPills;
      setState(() {
        _mockPills = pills;
      });
      _engine = TamagotchiExpressionEngine(expectedDoseCount: pills.length);
      for (final pill in pills) {
        _engine!.registerDoseNotification(doseId: pill.doseId);
        _registeredDoseIds.add(pill.doseId);
      }
      _timer = TamagotchiTimerService(
        engine: _engine!,
        tickInterval: const Duration(seconds: 10),
        onExpressionChanged: (expr) {
          if (!mounted) return;
          setState(() {
            _expression = expr;
            _happiness = _engine!.happiness;
          });
        },
        onTick: () {
          if (!mounted) return;
          setState(() => _happiness = _engine!.happiness);
        },
      )..start();
    }
    if (mounted) {
      setState(() => _tamagotchiReady = true);
    }
  }

  /// Pal prefs live on `elderly/{username}` for signed-in elderly users; otherwise
  /// `users/{deviceUserId}` (e.g. caregivers / demo).
  Future<DocumentReference<Map<String, dynamic>>> _palPrefsDocRef(
    SessionStore session,
  ) async {
    final role = session.role;
    final username = session.username?.trim();
    if (role == 'elderly' &&
        username != null &&
        username.isNotEmpty) {
      return FirebaseFirestore.instance.collection('elderly').doc(username);
    }
    final userId = await DeviceUserIdStore.getOrCreate();
    return FirebaseFirestore.instance.collection('users').doc(userId);
  }

  Future<void> _bootstrapPal() async {
    try {
      if (!mounted) return;
      final session = context.read<SessionStore>();
      final ref = await _palPrefsDocRef(session);
      final doc = await ref.get();
      final data = doc.data();
      final palId = (data?['palId'] as String?)?.trim();
      final palName = (data?['palName'] as String?)?.trim();
      if (!mounted) return;

      if (palId != null && palId.isNotEmpty) {
        final pal = availablePillPals.where((p) => p.id == palId).firstOrNull;
        if (pal != null) {
          setState(() {
            _selectedPal = pal;
            if (palName != null && palName.isNotEmpty) _palName = palName;
          });
        }
      }
    } catch (_) {
      // Non-fatal: we'll prompt as usual if reading fails.
    } finally {
      if (mounted) {
        setState(() => _palBootstrapped = true);
      }
    }
  }

  @override
  void dispose() {
    _petController.dispose();
    _timer?.dispose();
    _notifSub?.cancel();
    _nudgeSub?.cancel();
    super.dispose();
  }

  Future<void> _maybePromptForPet() async {
    if (!_palBootstrapped) return;
    if (_selectedPal != null || _petPromptShown) return;
    _petPromptShown = true;

    final selected = await showDialog<_PalSelection>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return const _PetPickerDialog();
      },
    );

    if (!mounted) return;
    if (selected == null) return;
    setState(() {
      _selectedPal = selected.pal;
      _palName = selected.name;
    });

    try {
      if (!mounted) return;
      final session = context.read<SessionStore>();
      final ref = await _palPrefsDocRef(session);
      await ref.set(
        <String, dynamic>{
          'palId': selected.pal.id,
          'palName': selected.name,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    } catch (_) {
      // Non-fatal; selection still applies locally.
    }
  }

  Future<void> _promptRenamePal() async {
    final controller = TextEditingController(text: _palName);
    try {
      final name = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text(
              'Rename your Pal',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            content: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Sunny',
              ),
              onSubmitted: (_) => Navigator.of(context).pop(controller.text),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(''),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(controller.text),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );

      final trimmed = (name ?? '').trim();
      if (!mounted) return;
      // Cancel should not trigger validation/snackbars.
      if (trimmed.isEmpty) return;
      setState(() => _palName = trimmed);

      try {
        if (!mounted) return;
        final session = context.read<SessionStore>();
        final ref = await _palPrefsDocRef(session);
        await ref.set(
          <String, dynamic>{
            'palName': trimmed,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      } catch (_) {
        // ignore
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _showPillDetails(_PillItem pill) async {
    HapticFeedback.lightImpact();
    final store = context.read<PillCompletionStore>();
    final today = DateTime.now();
    final alreadyTaken = store.isDoseTaken(date: today, doseId: pill.doseId);
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        Future<void> editMedication() async {
          final elderlyUsername = pill.elderlyUsername?.trim() ?? '';
          final docId = pill.medicationDocId?.trim() ?? '';
          if (elderlyUsername.isEmpty || docId.isEmpty) {
            ScaffoldMessenger.of(this.context).showSnackBar(
              const SnackBar(content: Text('This entry cannot be edited.')),
            );
            return;
          }

          final db = FirebaseFirestore.instance;
          final ref = db
              .collection('elderly')
              .doc(elderlyUsername)
              .collection('medicationCatalog')
              .doc(docId);

          final snap = await ref.get();
          final data = snap.data() ?? const <String, dynamic>{};
          final originalName =
              ((data['name'] as String?)?.trim() ?? pill.name).trim();
          final originalTimes = ((data['timesMinutes'] as List?)?.cast<dynamic>() ?? const [])
              .map((t) => t is int ? t : (t is num ? t.round() : null))
              .whereType<int>()
              .where((m) => m >= 0 && m < 24 * 60)
              .toSet()
              .toList()
            ..sort();

          final nameCtrl = TextEditingController(text: (data['name'] as String?)?.trim() ?? pill.name);
          final dosageCtrl = TextEditingController(
            text: (data['dosageAmount'] as String?)?.trim() ?? pill.dose,
          );
          final instrCtrl = TextEditingController(
            text: (data['instructions'] as String?)?.trim() ?? pill.instructions,
          );
          final totalLeftCtrl = TextEditingController(
            text: (() {
              final v = data['totalLeft'];
              if (v is int) return v.toString();
              if (v is num) return v.round().toString();
              return '';
            })(),
          );
          var times = ((data['timesMinutes'] as List?)?.cast<dynamic>() ?? const [])
              .map((t) => t is int ? t : (t is num ? t.round() : null))
              .whereType<int>()
              .where((m) => m >= 0 && m < 24 * 60)
              .toSet()
              .toList()
            ..sort();

          try {
            if (!mounted) return;
            final saved = await showDialog<bool>(
              context: this.context,
              builder: (ctx) {
                return StatefulBuilder(
                  builder: (ctx, setLocal) {
                    Future<void> addTimeWheel() async {
                      int hh = 9;
                      int mm = 0;
                      final ok = await showModalBottomSheet<bool>(
                        context: ctx,
                        showDragHandle: true,
                        useSafeArea: true,
                        builder: (ctx2) {
                          return SizedBox(
                            height: 340,
                            child: Column(
                              children: [
                                const SizedBox(height: 6),
                                const Text(
                                  'Pick a time',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                                ),
                                const SizedBox(height: 8),
                                Expanded(
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: ListWheelScrollView.useDelegate(
                                          itemExtent: 40,
                                          physics: const FixedExtentScrollPhysics(),
                                          onSelectedItemChanged: (v) => hh = v,
                                          childDelegate: ListWheelChildBuilderDelegate(
                                            childCount: 24,
                                            builder: (context, index) => Center(
                                              child: Text(index.toString().padLeft(2, '0')),
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: ListWheelScrollView.useDelegate(
                                          itemExtent: 40,
                                          physics: const FixedExtentScrollPhysics(),
                                          onSelectedItemChanged: (v) => mm = v,
                                          childDelegate: ListWheelChildBuilderDelegate(
                                            childCount: 60,
                                            builder: (context, index) => Center(
                                              child: Text(index.toString().padLeft(2, '0')),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: TextButton(
                                          onPressed: () => Navigator.of(ctx2).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton(
                                          onPressed: () => Navigator.of(ctx2).pop(true),
                                          child: const Text('Add'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                      if (ok != true) return;
                      final minutes = hh * 60 + mm;
                      if (!times.contains(minutes)) {
                        setLocal(() {
                          times = [...times, minutes]..sort();
                        });
                      }
                    }

                    return AlertDialog(
                      title: const Text('Edit medication'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: nameCtrl,
                              decoration: const InputDecoration(labelText: 'Name'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: totalLeftCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Total left'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: dosageCtrl,
                              decoration: const InputDecoration(labelText: 'Dosage amount'),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: instrCtrl,
                              minLines: 2,
                              maxLines: 3,
                              decoration: const InputDecoration(labelText: 'Instructions'),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text('Times', style: TextStyle(fontWeight: FontWeight.w900)),
                                ),
                                TextButton.icon(
                                  onPressed: addTimeWheel,
                                  icon: const Icon(Icons.add_alarm_rounded),
                                  label: const Text('Add'),
                                ),
                              ],
                            ),
                            if (times.isEmpty)
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text('No times set.'),
                              )
                            else
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: times
                                      .map((m) {
                                        final tod = TimeOfDay(hour: m ~/ 60, minute: m % 60);
                                        return InputChip(
                                          label: Text(tod.format(ctx)),
                                          onDeleted: () => setLocal(() {
                                            times = times.where((x) => x != m).toList();
                                          }),
                                        );
                                      })
                                      .toList(),
                                ),
                              ),
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          child: const Text('Save'),
                        ),
                      ],
                    );
                  },
                );
              },
            );

            if (saved != true) return;

            final trimmedName = nameCtrl.text.trim();
            final left = int.tryParse(totalLeftCtrl.text.trim()) ?? 0;

            await ref.set(
              <String, dynamic>{
                'name': trimmedName,
                'totalLeft': left,
                'dosageAmount': dosageCtrl.text.trim(),
                'instructions': instrCtrl.text.trim(),
                'timesMinutes': times,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );

            // Keep reminders + dose IDs in sync with updated times.
            // Cancel all previously scheduled series for the old times,
            // then schedule for the new times.
            try {
              for (final m in originalTimes) {
                final hh = (m ~/ 60).toString().padLeft(2, '0');
                final mm = (m % 60).toString().padLeft(2, '0');
                final oldDoseId = '${originalName.toLowerCase()}_$hh$mm';
                await NotificationService.instance.cancelEscalationSeries(doseId: oldDoseId);
              }
              for (final m in times) {
                final hh = (m ~/ 60).toString().padLeft(2, '0');
                final mm = (m % 60).toString().padLeft(2, '0');
                final newDoseId = '${trimmedName.toLowerCase()}_$hh$mm';
                await NotificationService.instance.scheduleEscalatingDoseReminder(
                  doseId: newDoseId,
                  medicationName: trimmedName.isEmpty ? 'Medication' : trimmedName,
                  time: TimeOfDay(hour: m ~/ 60, minute: m % 60),
                );
              }
            } catch (_) {
              // Non-fatal: Firestore update succeeded; reminders can be resynced on next save.
            }

            if (mounted) {
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('Medication updated')),
              );
            }
          } finally {
            nameCtrl.dispose();
            dosageCtrl.dispose();
            instrCtrl.dispose();
            totalLeftCtrl.dispose();
          }
        }

        Future<void> deleteMedication() async {
          final elderlyUsername = pill.elderlyUsername?.trim() ?? '';
          final docId = pill.medicationDocId?.trim() ?? '';
          if (elderlyUsername.isEmpty || docId.isEmpty) {
            ScaffoldMessenger.of(this.context).showSnackBar(
              const SnackBar(content: Text('This entry cannot be deleted.')),
            );
            return;
          }
          final ok = await showDialog<bool>(
            context: this.context,
            builder: (ctx) {
              return AlertDialog(
                title: const Text('Delete medication?'),
                content: Text('Delete “${pill.name}”? This can’t be undone.'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Delete'),
                  ),
                ],
              );
            },
          );
          if (ok != true) return;

          await FirebaseFirestore.instance
              .collection('elderly')
              .doc(elderlyUsername)
              .collection('medicationCatalog')
              .doc(docId)
              .delete();

          if (mounted) {
            Navigator.of(this.context).pop(); // close pill sheet
            ScaffoldMessenger.of(this.context).showSnackBar(
              const SnackBar(content: Text('Medication deleted')),
            );
          }
        }

        return DraggableScrollableSheet(
          expand: false,
          minChildSize: 0.35,
          initialChildSize: 0.55,
          maxChildSize: 0.9,
          builder: (context, controller) {
            return SingleChildScrollView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: pill.color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(pill.icon, color: pill.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pill.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${pill.dose} • ${pill.timeLabel}',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black.withValues(alpha: 0.6),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Instructions',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.black.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pill.instructions,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if ((pill.elderlyUsername ?? '').trim().isNotEmpty &&
                            (pill.medicationDocId ?? '').trim().isNotEmpty) ...[
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              await editMedication();
                            },
                            icon: const Icon(Icons.edit_rounded),
                            label: const Text('Edit pill'),
                          ),
                          const SizedBox(height: 10),
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              await deleteMedication();
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: const Text('Delete'),
                          ),
                          const SizedBox(height: 10),
                        ],
                        FilledButton.icon(
                          onPressed: alreadyTaken
                              ? null
                              : () async {
                                  await store.markDoseTaken(
                                    date: today,
                                    doseId: pill.doseId,
                                  );
                                  try {
                                    // Happiness gain based on interval:
                                    // 1 / (24 / intervalHours) == intervalHours / 24
                                    final intervalMinutes = pill.intervalMinutes ?? 1440;
                                    final intervalHours = (intervalMinutes / 60.0).clamp(0.0, 24.0);
                                    // Slow the gain rate a bit so it feels more earned.
                                    final delta = intervalHours / 48.0;
                                    _engine!.registerDoseTaken(
                                      doseId: pill.doseId,
                                      happinessDelta: delta,
                                    );
                                    await _persistDoseTakenToFirestore(
                                      date: today,
                                      doseId: pill.doseId,
                                    );
                                    await NotificationService.instance
                                        .cancelEscalationSeries(doseId: pill.doseId);
                                  } catch (_) {
                                    // Non-fatal: local completion still works.
                                  }
                                  if (!mounted) return;
                                  setState(() {
                                    _expression = _engine!.expression;
                                    _happiness = _engine!.happiness;
                                  });
                                  if (context.mounted) context.pop();
                                },
                          icon: Icon(
                            alreadyTaken
                                ? Icons.check_circle_rounded
                                : Icons.check_rounded,
                          ),
                          label: Text(alreadyTaken ? 'Taken today' : 'Mark as taken'),
                        ),
                        const SizedBox(height: 10),
                        FilledButton(
                          onPressed: () => context.pop(),
                          child: const Text('Close'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _persistDoseTakenToFirestore({
    required DateTime date,
    required String doseId,
  }) async {
    if (!mounted) return;
    final session = context.read<SessionStore>();
    final role = session.role;
    final username = session.username?.trim();
    if (role != 'elderly' || username == null || username.isEmpty) return;

    final key = PillCompletionStore.dayKey(date);
    final ref = FirebaseFirestore.instance
        .collection('elderly')
        .doc(username)
        .collection('dailyStatus')
        .doc(key);

    // Expected doses for the day = all scheduled times across the current catalog.
    // We persist this alongside taken doses so streaks can be computed from Firestore alone.
    final expectedDoseIds = <String>{};
    try {
      final catalogSnap = await FirebaseFirestore.instance
          .collection('elderly')
          .doc(username)
          .collection('medicationCatalog')
          .get();
      for (final doc in catalogSnap.docs) {
        final data = doc.data();
        final name = (data['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        final times = (data['timesMinutes'] as List?)?.cast<dynamic>() ?? const [];
        for (final t in times) {
          final minutes = t is int ? t : (t is num ? t.round() : null);
          if (minutes == null) continue;
          if (minutes < 0 || minutes >= 24 * 60) continue;
          final hh = (minutes ~/ 60).toString().padLeft(2, '0');
          final mm = (minutes % 60).toString().padLeft(2, '0');
          expectedDoseIds.add('${name.toLowerCase()}_$hh$mm');
        }
      }
    } catch (_) {
      // Non-fatal: if we can't compute expected doses, we still record taken doses.
    }

    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(ref);
      final data = snap.data();
      final taken = (data?['takenDoseIds'] as List?)?.cast<dynamic>() ?? const [];
      final alreadyTaken = taken.any((e) => e.toString() == doseId);
      if (alreadyTaken) return;

      final takenCountNew = taken.length + 1;
      final expectedCount = expectedDoseIds.isEmpty
          ? (data?['expectedCount'] as int?) ?? 0
          : expectedDoseIds.length;
      final isComplete = expectedCount > 0 && takenCountNew >= expectedCount;

      txn.set(
        ref,
        <String, dynamic>{
          'dayKey': key,
          'date': key,
          'takenDoseIds': FieldValue.arrayUnion([doseId]),
          'takenCount': FieldValue.increment(1),
          if (expectedDoseIds.isNotEmpty) 'expectedDoseIds': expectedDoseIds.toList()..sort(),
          if (expectedDoseIds.isNotEmpty) 'expectedCount': expectedDoseIds.length,
          'complete': isComplete,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final session = context.watch<SessionStore>();
    final role = session.role;
    final username = session.username?.trim() ?? '';

    if (role == null || role.isEmpty) {
      // Ensure the dashboard never renders without a role chosen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/role');
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    if (!_tamagotchiReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isCaregiver = role == 'caregiver';

    if (session.bootstrapped &&
        !_palBootstrapped &&
        !_palBootstrapScheduled) {
      _palBootstrapScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_palBootstrapped) _bootstrapPal();
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybePromptForPet();
    });

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.35, 0.7, 1.0],
            colors: [
              Color(0xFFC2DEFF),
              Color(0xFFE8EFFE),
              Color(0xFFFFF3C4),
              Color(0xFFFFE07A),
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              // Center "pet widget"
              Positioned.fill(
                child: Center(
                  child: AnimatedBuilder(
                    animation: _petController,
                    builder: (context, _) {
                      final t = _petController.value * 2 * math.pi;
                      final bob = math.sin(t) * 6;
                      final tilt = math.sin(t) * 0.03;
                      final petAssetPath =
                          (_selectedPal ?? availablePillPals.first).assetFor(_expression);

                      final palId =
                          (_selectedPal ?? availablePillPals.first).id.toLowerCase();
                      final spriteScale = (palId == 'cat' || palId == 'penguin')
                          ? 1.10
                          : 1.00;

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.translate(
                            // Move the sprite up, but keep the name stable.
                            offset: Offset(0, bob - 140),
                            child: Transform.rotate(
                              angle: tilt,
                              child: Transform.scale(
                                scale: spriteScale,
                                child: _FloatingPalSprite(
                                  accent: cs.primary,
                                  petAssetPath: petAssetPath,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // Pal name badge centered at top
              Positioned(
                top: 22,
                left: 0,
                right: 0,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 210),
                    child: _PalNameBadge(
                      name: _palName,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _promptRenamePal();
                      },
                    ),
                  ),
                ),
              ),

              // Top-left circular button
              Positioned(
                top: 14,
                left: 14,
                child: _CircleNavButton(
                  icon: Icons.arrow_back_rounded,
                  label: 'Back to landing',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    context.go('/');
                  },
                ),
              ),

              // Top-right circular button
              if (isCaregiver)
                Positioned(
                  top: 14,
                  right: 14,
                  child: _CircleNavButton(
                    icon: Icons.local_fire_department_rounded,
                    label: 'Notifications',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.push('/dashboard/right');
                    },
                  ),
                ),

              // Elderly-only: quick scan shortcut
              if (!isCaregiver)
                ...[
                  // Swapped: Scan is now top-right.
                  Positioned(
                    top: 14,
                    right: 14,
                    child: _CircleNavButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Scan',
                      onTap: () {
                        HapticFeedback.lightImpact();
                        context.push('/scan');
                      },
                    ),
                  ),
                  // Swapped: Notifications is now under Scan.
                  Positioned(
                    top: 96,
                    right: 14,
                    child: _StreakCircleButton(
                      elderlyUsername: username,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        context.push('/dashboard/right');
                      },
                    ),
                  ),
                ],

              // Bottom pills panel
              Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _AnimatedHappinessMeter(value: _happiness),
                    const SizedBox(height: 10),
                    if (role == 'elderly' && username.isNotEmpty)
                      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('elderly')
                            .doc(username)
                            .collection('medicationCatalog')
                            .snapshots(),
                        builder: (context, snap) {
                          final pills = <_PillItem>[];
                          if (snap.hasData) {
                            for (final doc in snap.data!.docs) {
                              final data = doc.data();
                              final name = (data['name'] as String?)?.trim() ?? '';
                              if (name.isEmpty) continue;
                              final dose = (data['dosageAmount'] as String?)?.trim() ?? '';
                              final instructions =
                                  (data['instructions'] as String?)?.trim() ?? '';
                              final times = (data['timesMinutes'] as List?)
                                      ?.cast<dynamic>() ??
                                  const [];
                              final intervalMinutesRaw = data['intervalMinutes'];
                              final intervalMinutes = intervalMinutesRaw is int
                                  ? intervalMinutesRaw
                                  : (intervalMinutesRaw is num
                                      ? intervalMinutesRaw.round()
                                      : null);
                              if (times.isEmpty) {
                                pills.add(
                                  _PillItem(
                                    name: name,
                                    dose: dose.isEmpty ? '—' : dose,
                                    timeLabel: 'No time set',
                                    instructions: instructions.isEmpty
                                        ? 'No instructions.'
                                        : instructions,
                                    color: const Color(0xFF4A90D9),
                                    icon: Icons.medication_outlined,
                                    medicationDocId: doc.id,
                                    elderlyUsername: username,
                                    intervalMinutes: intervalMinutes,
                                  ),
                                );
                              } else {
                                for (final t in times) {
                                  final minutes = t is int
                                      ? t
                                      : (t is num ? t.round() : null);
                                  if (minutes == null) continue;
                                  if (minutes < 0 || minutes >= 24 * 60) continue;
                                  final hour = minutes ~/ 60;
                                  final minute = minutes % 60;
                                  final tod = TimeOfDay(hour: hour, minute: minute);
                                  final timeLabel = tod.format(context);
                                  final pill = _PillItem(
                                    name: name,
                                    dose: dose.isEmpty ? '—' : dose,
                                    timeLabel: timeLabel,
                                    instructions: instructions.isEmpty
                                        ? 'No instructions.'
                                        : instructions,
                                    color: const Color(0xFF4A90D9),
                                    icon: Icons.medication_outlined,
                                    minutesOfDay: minutes,
                                    medicationDocId: doc.id,
                                    elderlyUsername: username,
                                    intervalMinutes: intervalMinutes,
                                  );
                                  pills.add(pill);
                                }
                              }
                            }
                          }

                          pills.sort((a, b) => a.doseId.compareTo(b.doseId));

                          for (final p in pills) {
                            if (_registeredDoseIds.add(p.doseId)) {
                              _engine!.registerDoseNotification(doseId: p.doseId);
                            }
                          }

                          // Hide pills that are already taken today.
                          final store = context.watch<PillCompletionStore>();
                          final today = DateTime.now();
                          final remaining = pills
                              .where((p) => !store.isDoseTaken(date: today, doseId: p.doseId))
                              .toList();

                          return _TodayPillsPanel(
                            pills: remaining.isEmpty ? const <_PillItem>[] : remaining,
                            onPillTap: _showPillDetails,
                            showEmptyStateRedDemoPill: isRedTimeDemoPillUser(
                              deviceUserId: _deviceUserId,
                              sessionUsername: username.isEmpty ? null : username,
                            ),
                          );
                        },
                      )
                    else
                      _TodayPillsPanel(
                        pills: _mockPills
                            .where((p) => !context.watch<PillCompletionStore>().isDoseTaken(
                                  date: DateTime.now(),
                                  doseId: p.doseId,
                                ))
                            .toList(),
                        onPillTap: _showPillDetails,
                        showEmptyStateRedDemoPill: isRedTimeDemoPillUser(
                          deviceUserId: _deviceUserId,
                          sessionUsername: username.isEmpty ? null : username,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleNavButton extends StatelessWidget {
  const _CircleNavButton({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onTap,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.white.withValues(alpha: 0.7),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.95),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.10),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Center(
              child: iconWidget ??
                  Icon(
                    icon,
                    color: const Color(0xFF1E2D4A),
                    size: 34,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StreakCircleButton extends StatelessWidget {
  const _StreakCircleButton({
    required this.elderlyUsername,
    required this.onTap,
  });

  final String elderlyUsername;
  final VoidCallback onTap;

  static String _dayKey(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  Color _flameColorForStreak(int streak) {
    // 0..30 maps orange -> red.
    final t = (streak / 30.0).clamp(0.0, 1.0);
    return Color.lerp(const Color(0xFFFFA000), const Color(0xFFFF2D55), t) ??
        const Color(0xFFFFA000);
  }

  @override
  Widget build(BuildContext context) {
    final u = elderlyUsername.trim();
    if (u.isEmpty) {
      return _CircleNavButton(
        icon: Icons.local_fire_department_rounded,
        label: 'Streak',
        onTap: onTap,
      );
    }

    final ref = FirebaseFirestore.instance
        .collection('elderly')
        .doc(u)
        .collection('dailyStatus')
        .orderBy('dayKey', descending: true)
        .limit(60);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        final complete = <String, bool>{};
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final data = doc.data();
            final key = (data['dayKey'] as String?)?.trim() ?? doc.id;
            complete[key] = data['complete'] == true;
          }
        }

        int streak = 0;
        DateTime cursor = DateTime.now();
        cursor = DateTime(cursor.year, cursor.month, cursor.day);
        while (true) {
          final k = _dayKey(cursor);
          if (complete[k] == true) {
            streak++;
            cursor = cursor.subtract(const Duration(days: 1));
            continue;
          }
          break;
        }

        final flameColor = _flameColorForStreak(streak);
        final textColor =
            streak >= 10 ? Colors.white : const Color(0xFF1E2D4A);

        return _CircleNavButton(
          label: 'Streak',
          onTap: onTap,
          iconWidget: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                color: flameColor,
                size: 38,
              ),
              // Count in the middle of the flame.
              Text(
                streak.toString(),
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: textColor,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PalNameBadge extends StatelessWidget {
  const _PalNameBadge({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.92),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF7DB8F7).withValues(alpha: 0.9),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E2D4A),
                    height: 1.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingPalSprite extends StatelessWidget {
  const _FloatingPalSprite({
    required this.accent,
    required this.petAssetPath,
  });

  final Color accent;
  final String petAssetPath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 250,
            height: 250,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  accent.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.0),
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),
          Image.asset(
            petAssetPath,
            width: 280,
            height: 280,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ],
      ),
    );
  }
}

class _AnimatedHappinessMeter extends StatefulWidget {
  const _AnimatedHappinessMeter({required this.value});

  /// Engine value 0.0–1.0; animates smoothly when this changes.
  final double value;

  @override
  State<_AnimatedHappinessMeter> createState() => _AnimatedHappinessMeterState();
}

class _AnimatedHappinessMeterState extends State<_AnimatedHappinessMeter>
    with SingleTickerProviderStateMixin {
  static const _curve = Curves.easeOutCubic;
  static const _duration = Duration(milliseconds: 900);

  late final AnimationController _ctrl;
  double _a = 0.55;
  double _b = 0.55;

  @override
  void initState() {
    super.initState();
    final v = _clamp01(widget.value);
    _a = v;
    _b = v;
    _ctrl = AnimationController(
      vsync: this,
      duration: _duration,
    )..addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(covariant _AnimatedHappinessMeter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_sameTarget(oldWidget.value, widget.value)) return;
    final t = _curve.transform(_ctrl.value);
    _a = _a + (_b - _a) * t;
    _b = _clamp01(widget.value);
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  bool _sameTarget(double u, double v) {
    if (u.isNaN && v.isNaN) return true;
    if (u.isNaN || v.isNaN) return false;
    return (u - v).abs() < 0.0005;
  }

  double get _display01 {
    final t = _curve.transform(_ctrl.value);
    return _clamp01(_a + (_b - _a) * t);
  }

  double _clamp01(double v) {
    if (v.isNaN) return 0.0;
    return v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
  }

  int get _percent => (_display01 * 100).round().clamp(0, 100);

  String get _label {
    final v = _display01;
    if (v >= 0.85) return 'Feeling great';
    if (v >= 0.55) return 'Doing okay';
    if (v >= 0.30) return 'A bit down';
    return 'Not feeling great';
  }

  String get _emoji {
    final v = _display01;
    if (v >= 0.85) return '😁';
    if (v >= 0.55) return '🙂';
    if (v >= 0.30) return '😕';
    return '😢';
  }

  @override
  Widget build(BuildContext context) {
    Color meterColor() {
      final t = _display01;
      return Color.lerp(const Color(0xFFFF2D55), const Color(0xFF1EBC61), t) ??
          const Color(0xFF1EBC61);
    }

    return Container(
      width: 320,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.92),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -2,
            right: 0,
            child: Text(
              _emoji,
              style: const TextStyle(fontSize: 22),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Keep the title + % clear of the emoji in the top-right.
              Padding(
                padding: const EdgeInsets.only(right: 40),
                child: Row(
                  children: [
                    const Text(
                      'Happiness',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E2D4A),
                        letterSpacing: 0.2,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$_percent%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.black.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black.withValues(alpha: 0.62),
                ),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: _display01,
                  minHeight: 12,
                  backgroundColor: const Color(0xFFE8EFFE).withValues(alpha: 0.95),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    meterColor(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TodayPillsPanel extends StatefulWidget {
  const _TodayPillsPanel({
    required this.pills,
    required this.onPillTap,
    this.showEmptyStateRedDemoPill = false,
  });

  final List<_PillItem> pills;
  final ValueChanged<_PillItem> onPillTap;
  /// [kRedTimeDemoPillUserId] only: empty list shows a tappable 8:55 AM sample in red.
  final bool showEmptyStateRedDemoPill;

  @override
  State<_TodayPillsPanel> createState() => _TodayPillsPanelState();
}

class _TodayPillsPanelState extends State<_TodayPillsPanel> {
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    // Refresh the “time until dose” display once per minute.
    _countdownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final pills = widget.pills;
    final onPillTap = widget.onPillTap;

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      padding: EdgeInsets.fromLTRB(16, 14, 16, 12 + bottomInset * 0.25),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.92),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 26,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Today’s pills',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E2D4A),
                ),
              ),
              const Spacer(),
              Text(
                '${pills.length} total',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.black.withValues(alpha: 0.55),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Keep panel height stable regardless of pill count.
          SizedBox(
            height: 190,
            child: pills.isEmpty
                ? (widget.showEmptyStateRedDemoPill
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: Text(
                              'All done for today 🎉',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Sample pill for this device',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.black.withValues(alpha: 0.4),
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Expanded(
                            child: _PillTile(
                              pill: _kEmptyStateExamplePill,
                              asOf: now,
                              onTap: () => onPillTap(_kEmptyStateExamplePill),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Text(
                          'All done for today 🎉',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Colors.black.withValues(alpha: 0.6),
                          ),
                        ),
                      ))
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: pills.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final pill = pills[index];
                      return _PillTile(
                        pill: pill,
                        asOf: now,
                        onTap: () => onPillTap(pill),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Time left until today’s scheduled dose, or "Overdue" if that time has passed.
String _doseTimeRemainingLabel(_PillItem pill, DateTime asOf) {
  final m = pill.minutesOfDay;
  if (m == null) return '';
  final h = m ~/ 60;
  final min = m % 60;
  final sched = DateTime(asOf.year, asOf.month, asOf.day, h, min);
  final until = sched.difference(asOf);
  if (until.isNegative) return 'Overdue';
  if (until.inSeconds < 60) return 'Due now';
  return 'in ${_formatHrsMinsUpcoming(until)}';
}

String _formatHrsMinsUpcoming(Duration d) {
  var mins = d.inMinutes;
  if (mins < 1) return '0m';
  if (mins < 60) return '${mins}m';
  final h = mins ~/ 60;
  final m = mins % 60;
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

const _kPillTimeEmphasis = Color(0xFFE85D4C);

/// Red time for 11:55 AM, or an explicit [PillItem.timeLabelColor] (e.g. demo 8:55).
Color? _highlightTimeColorForPill(_PillItem pill) {
  if (pill.timeLabelColor != null) return pill.timeLabelColor;
  final m = pill.minutesOfDay;
  if (m == 11 * 60 + 55) return _kPillTimeEmphasis;
  return null;
}

class _PillTile extends StatelessWidget {
  const _PillTile({required this.pill, required this.asOf, required this.onTap});

  final _PillItem pill;
  final DateTime asOf;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final remaining = _doseTimeRemainingLabel(pill, asOf);
    final isOverdue = remaining == 'Overdue';
    final isUnset = remaining.isEmpty;
    final timeColor = _highlightTimeColorForPill(pill);

    return Material(
      color: Colors.white.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: pill.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(pill.icon, color: pill.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pill.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E2D4A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    timeColor == null
                        ? Text(
                            '${pill.dose} • ${pill.timeLabel}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black.withValues(alpha: 0.58),
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : Text.rich(
                            TextSpan(
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.black.withValues(alpha: 0.58),
                                fontWeight: FontWeight.w700,
                              ),
                              children: [
                                TextSpan(text: '${pill.dose} • '),
                                TextSpan(
                                  text: pill.timeLabel,
                                  style: TextStyle(
                                    color: timeColor,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(
                  isUnset ? '—' : remaining,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    color: isUnset
                        ? Colors.black.withValues(alpha: 0.4)
                        : (isOverdue
                            ? const Color(0xFFE85D4C)
                            : const Color(0xFF2E7D6A)),
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.info_outline_rounded,
                color: Colors.black.withValues(alpha: 0.45),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PillItem {
  const _PillItem({
    required this.name,
    required this.dose,
    required this.timeLabel,
    this.timeLabelColor,
    required this.instructions,
    required this.color,
    required this.icon,
    this.minutesOfDay,
    this.medicationDocId,
    this.elderlyUsername,
    this.intervalMinutes,
  });

  final String name;
  final String dose;
  final String timeLabel;
  /// When set, [timeLabel] is shown in this color (e.g. red for 8:55 AM emphasis).
  final Color? timeLabelColor;
  final String instructions;
  final Color color;
  final IconData icon;
  final int? minutesOfDay;
  final String? medicationDocId;
  final String? elderlyUsername;
  final int? intervalMinutes;

  String get doseId {
    final m = minutesOfDay;
    if (m == null) return '$name::$timeLabel';
    final hh = (m ~/ 60).toString().padLeft(2, '0');
    final mm = (m % 60).toString().padLeft(2, '0');
    return '${name.toLowerCase()}_$hh$mm';
  }
}

const _kDefaultMockTodayPills = <_PillItem>[
  _PillItem(
    name: 'Metformin',
    dose: '500mg',
    timeLabel: '8:00 AM',
    instructions:
        'Take with food. If you feel nauseous, drink water and eat a small snack.',
    color: Color(0xFF4A90D9),
    icon: Icons.medication_outlined,
    minutesOfDay: 8 * 60,
  ),
  _PillItem(
    name: 'Vitamin D',
    dose: '1 capsule',
    timeLabel: '2:00 PM',
    instructions:
        'Take with a meal. If you miss it, you can take it later today.',
    color: Color(0xFFE5A800),
    icon: Icons.sunny,
    minutesOfDay: 14 * 60,
  ),
  _PillItem(
    name: 'Atorvastatin',
    dose: '20mg',
    timeLabel: '9:00 PM',
    instructions:
        'Take at night. Avoid grapefruit. If you have muscle pain, tell your doctor.',
    color: Color(0xFF7DB8F7),
    icon: Icons.nightlight_round,
    minutesOfDay: 21 * 60,
  ),
];

const _kRedTimeDemoMockTodayPills = <_PillItem>[
  _PillItem(
    name: 'Metformin',
    dose: '500mg',
    timeLabel: '8:55 AM',
    timeLabelColor: Color(0xFFE85D4C),
    instructions:
        'Take with food. If you feel nauseous, drink water and eat a small snack.',
    color: Color(0xFF4A90D9),
    icon: Icons.medication_outlined,
    minutesOfDay: 8 * 60 + 55,
  ),
  _PillItem(
    name: 'Vitamin D',
    dose: '1 capsule',
    timeLabel: '2:00 PM',
    instructions:
        'Take with a meal. If you miss it, you can take it later today.',
    color: Color(0xFFE5A800),
    icon: Icons.sunny,
    minutesOfDay: 14 * 60,
  ),
  _PillItem(
    name: 'Atorvastatin',
    dose: '20mg',
    timeLabel: '9:00 PM',
    instructions:
        'Take at night. Avoid grapefruit. If you have muscle pain, tell your doctor.',
    color: Color(0xFF7DB8F7),
    icon: Icons.nightlight_round,
    minutesOfDay: 21 * 60,
  ),
];

/// Shown for [kRedTimeDemoPillUserId] when there are no remaining doses (same pill behavior as a real row; time in red only).
const _kEmptyStateExamplePill = _PillItem(
  name: "Today's sample",
  dose: '10 mg',
  timeLabel: '8:55 AM',
  timeLabelColor: Color(0xFFE85D4C),
  instructions: 'This is a sample for your device ID so you can see how a scheduled time is highlighted.',
  color: Color(0xFF4A90D9),
  icon: Icons.medication_outlined,
  minutesOfDay: 535,
);

class _PetPickerDialog extends StatelessWidget {
  const _PetPickerDialog();

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: 'Pal');
    return AlertDialog(
      title: const Text(
        'Choose your Pal',
        style: TextStyle(fontWeight: FontWeight.w900),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pick a little friend to join your pill routine.',
              style: TextStyle(
                color: Colors.black.withValues(alpha: 0.65),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Name your Pal',
                hintText: 'e.g. Sunny',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                for (final pal in availablePillPals) ...[
                  Expanded(
                    child: _PetChoiceTile(
                      pal: pal,
                      onTap: () {
                        final name = controller.text.trim().isEmpty
                            ? 'Pal'
                            : controller.text.trim();
                        Navigator.of(context).pop(_PalSelection(pal: pal, name: name));
                      },
                    ),
                  ),
                  if (pal != availablePillPals.last) const SizedBox(width: 10),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PetChoiceTile extends StatelessWidget {
  const _PetChoiceTile({required this.pal, required this.onTap});

  final PillPal pal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFE8EFFE).withValues(alpha: 0.9),
                ),
                padding: const EdgeInsets.all(10),
                child: Image.asset(
                  pal.assetFor(PalExpression.neutral),
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                pal.name,
                maxLines: 3,
                softWrap: true,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                  color: Color(0xFF1E2D4A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PalSelection {
  const _PalSelection({required this.pal, required this.name});
  final PillPal pal;
  final String name;
}

