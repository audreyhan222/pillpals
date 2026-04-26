import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../pals/pill_pal.dart';
import '../../state/pill_completion_store.dart';
import '../../state/device_user_id_store.dart';
import '../../state/session_store.dart';
import '../../tamagotchi_backend/tamagotchi_expression_engine.dart';
import '../../tamagotchi_backend/tamagotchi_timer_service.dart';

extension _FirstOrNullExt<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _petController;
  late final TamagotchiExpressionEngine _engine;
  late final TamagotchiTimerService _timer;
  final Set<String> _registeredDoseIds = <String>{};

  PillPal? _selectedPal;
  String _palName = 'Pal';
  PalExpression _expression = PalExpression.neutral;
  bool _petPromptShown = false;
  bool _palBootstrapped = false;
  bool _palBootstrapScheduled = false;

  final _todayPills = const <_PillItem>[
    _PillItem(
      name: 'Metformin',
      dose: '500mg',
      timeLabel: 'Morning',
      instructions:
          'Take with food. If you feel nauseous, drink water and eat a small snack.',
      color: Color(0xFF4A90D9),
      icon: Icons.medication_outlined,
    ),
    _PillItem(
      name: 'Vitamin D',
      dose: '1 capsule',
      timeLabel: 'Afternoon',
      instructions:
          'Take with a meal. If you miss it, you can take it later today.',
      color: Color(0xFFE5A800),
      icon: Icons.sunny,
    ),
    _PillItem(
      name: 'Atorvastatin',
      dose: '20mg',
      timeLabel: 'Night',
      instructions:
          'Take at night. Avoid grapefruit. If you have muscle pain, tell your doctor.',
      color: Color(0xFF7DB8F7),
      icon: Icons.nightlight_round,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _petController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();

    _engine = TamagotchiExpressionEngine(expectedDoseCount: _todayPills.length);
    for (final pill in _todayPills) {
      _engine.registerDoseNotification(doseId: pill.doseId);
      _registeredDoseIds.add(pill.doseId);
    }
    _timer = TamagotchiTimerService(
      engine: _engine,
      tickInterval: const Duration(seconds: 10),
      onExpressionChanged: (expr) {
        if (!mounted) return;
        setState(() => _expression = expr);
      },
    )..start();
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
    _timer.dispose();
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
                onPressed: () => Navigator.of(context).pop(),
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
                        FilledButton.icon(
                          onPressed: alreadyTaken
                              ? null
                              : () async {
                                  await store.markDoseTaken(
                                    date: today,
                                    doseId: pill.doseId,
                                  );
                                  try {
                                    await _persistDoseTakenToFirestore(
                                      date: today,
                                      doseId: pill.doseId,
                                    );
                                  } catch (_) {
                                    // Non-fatal: local completion still works.
                                  }
                                  _engine.registerDoseTaken(doseId: pill.doseId);
                                  if (!mounted) return;
                                  setState(() => _expression = _engine.expression);
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

    await FirebaseFirestore.instance.runTransaction((txn) async {
      final snap = await txn.get(ref);
      final data = snap.data();
      final taken = (data?['takenDoseIds'] as List?)?.cast<dynamic>() ?? const [];
      final alreadyTaken = taken.any((e) => e.toString() == doseId);
      if (alreadyTaken) return;

      txn.set(
        ref,
        <String, dynamic>{
          'dayKey': key,
          'date': key,
          'takenDoseIds': FieldValue.arrayUnion([doseId]),
          'takenCount': FieldValue.increment(1),
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
                    child: _CircleNavButton(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Notifications',
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
                    _HappinessMeter(expression: _expression),
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
                                );
                                pills.add(pill);
                              }
                            }
                          }

                          pills.sort((a, b) => a.doseId.compareTo(b.doseId));

                          for (final p in pills) {
                            if (_registeredDoseIds.add(p.doseId)) {
                              _engine.registerDoseNotification(doseId: p.doseId);
                            }
                          }

                          return _TodayPillsPanel(
                            pills: pills.isEmpty ? _todayPills : pills,
                            onPillTap: _showPillDetails,
                          );
                        },
                      )
                    else
                      _TodayPillsPanel(
                        pills: _todayPills,
                        onPillTap: _showPillDetails,
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
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
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
            child: Icon(
              icon,
              color: const Color(0xFF1E2D4A),
              size: 34,
            ),
          ),
        ),
      ),
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

class _HappinessMeter extends StatelessWidget {
  const _HappinessMeter({required this.expression});

  final PalExpression expression;

  double get _value => switch (expression) {
        PalExpression.depressed => 0.20,
        PalExpression.sad => 0.45,
        PalExpression.neutral => 0.70,
        PalExpression.happy => 1.00,
      };

  String get _label => switch (expression) {
        PalExpression.depressed => 'Not feeling great',
        PalExpression.sad => 'A bit down',
        PalExpression.neutral => 'Doing okay',
        PalExpression.happy => 'Feeling great',
      };

  String get _emoji => switch (expression) {
        PalExpression.depressed => '😢',
        PalExpression.sad => '😕',
        PalExpression.neutral => '🙂',
        PalExpression.happy => '😁',
      };

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

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
              const Text(
                'Happiness',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E2D4A),
                  letterSpacing: 0.2,
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
                  // Mirrors the same backend-driven expression used for the pal sprite.
                  value: _value,
                  minHeight: 12,
                  backgroundColor: const Color(0xFFE8EFFE).withValues(alpha: 0.95),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color.lerp(const Color(0xFFFFC947), accent, 0.55) ?? accent,
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

class _TodayPillsPanel extends StatelessWidget {
  const _TodayPillsPanel({required this.pills, required this.onPillTap});

  final List<_PillItem> pills;
  final ValueChanged<_PillItem> onPillTap;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

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
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: pills.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final pill = pills[index];
                return _PillTile(
                  pill: pill,
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

class _PillTile extends StatelessWidget {
  const _PillTile({required this.pill, required this.onTap});

  final _PillItem pill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
                    Text(
                      '${pill.dose} • ${pill.timeLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black.withValues(alpha: 0.58),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
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
    required this.instructions,
    required this.color,
    required this.icon,
  });

  final String name;
  final String dose;
  final String timeLabel;
  final String instructions;
  final Color color;
  final IconData icon;

  String get doseId => '$name::$timeLabel';
}

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

