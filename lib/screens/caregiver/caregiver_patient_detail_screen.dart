import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/session_store.dart';

class CaregiverPatientDetailScreen extends StatelessWidget {
  const CaregiverPatientDetailScreen({super.key, required this.elderlyUsername});

  final String elderlyUsername;

  static String _dayKey(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  static int _readInt(Map<String, dynamic>? data, String key, {int fallback = 0}) {
    final v = data?[key];
    if (v is int) return v;
    if (v is num) return v.round();
    return fallback;
  }

  @override
  Widget build(BuildContext context) {
    final u = elderlyUsername.trim();
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final todayKey = _dayKey(now);

    final elderlyDocStream =
        FirebaseFirestore.instance.collection('elderly').doc(u).snapshots();
    final catalogStream = FirebaseFirestore.instance
        .collection('elderly')
        .doc(u)
        .collection('medicationCatalog')
        .snapshots();
    final statusStream = FirebaseFirestore.instance
        .collection('elderly')
        .doc(u)
        .collection('dailyStatus')
        .orderBy('dayKey', descending: true)
        .limit(30)
        .snapshots();

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
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: elderlyDocStream,
              builder: (context, elderlySnap) {
                final elderly = elderlySnap.data?.data();
                final name = (elderly?['name'] as String?)?.trim();
                final displayName =
                    (name != null && name.isNotEmpty) ? name : 'Patient';

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: catalogStream,
                  builder: (context, catSnap) {
                    final meds = catSnap.data?.docs ?? const [];

                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: statusStream,
                      builder: (context, statusSnap) {
                        final statusDocs = statusSnap.data?.docs ?? const [];
                        final statusByKey = <String, Map<String, dynamic>>{};
                        for (final d in statusDocs) {
                          final data = d.data();
                          final k = (data['dayKey'] as String?)?.trim() ?? d.id;
                          if (k.isNotEmpty) statusByKey[k] = data;
                        }

                        // Weekly stats
                        final days = List.generate(
                          7,
                          (i) => DateTime(now.year, now.month, now.day)
                              .subtract(Duration(days: i)),
                        );
                        int daysWithSchedule = 0;
                        int completeDays = 0;
                        int missedDoses = 0;
                        for (final d in days) {
                          final s = statusByKey[_dayKey(d)];
                          if (s == null) continue;
                          final expected = _readInt(s, 'expectedCount', fallback: 0);
                          final taken = _readInt(s, 'takenCount', fallback: 0);
                          if (expected <= 0) continue;
                          daysWithSchedule++;
                          if (s['complete'] == true || taken >= expected) completeDays++;
                          if (taken < expected) missedDoses += (expected - taken);
                        }
                        final adherencePct = daysWithSchedule == 0
                            ? 0
                            : ((completeDays / daysWithSchedule) * 100).round();

                        // Streak
                        int streak = 0;
                        DateTime cursor = DateTime(now.year, now.month, now.day);
                        while (true) {
                          final s = statusByKey[_dayKey(cursor)];
                          if (s != null && s['complete'] == true) {
                            streak++;
                            cursor = cursor.subtract(const Duration(days: 1));
                            continue;
                          }
                          break;
                        }

                        // Next dose
                        final todayStatus = statusByKey[todayKey];
                        final takenToday = <String>{
                          for (final e in ((todayStatus?['takenDoseIds'] as List?)
                                  ?.cast<dynamic>() ??
                              const []))
                            e.toString()
                        };
                        String nextDoseLabel = '—';
                        String nextDoseTime = 'No upcoming doses';
                        DateTime? nextAt;
                        Map<String, dynamic>? nextDoseMed;
                        int? nextDoseMinutes;
                        for (final doc in meds) {
                          final data = doc.data();
                          final medName = (data['name'] as String?)?.trim() ?? '';
                          if (medName.isEmpty) continue;
                          final times =
                              (data['timesMinutes'] as List?)?.cast<dynamic>() ?? const [];
                          for (final t in times) {
                            final minutes = t is int ? t : (t is num ? t.round() : null);
                            if (minutes == null || minutes < 0 || minutes >= 24 * 60) continue;
                            final hh = (minutes ~/ 60).toString().padLeft(2, '0');
                            final mm = (minutes % 60).toString().padLeft(2, '0');
                            final doseId = '${medName.toLowerCase()}_$hh$mm';
                            final dt = DateTime(
                              now.year,
                              now.month,
                              now.day,
                              minutes ~/ 60,
                              minutes % 60,
                            );
                            if (dt.isBefore(now) && takenToday.contains(doseId)) continue;
                            final candidate =
                                dt.isBefore(now) ? dt.add(const Duration(days: 1)) : dt;
                            if (nextAt == null || candidate.isBefore(nextAt)) {
                              nextAt = candidate;
                              nextDoseLabel = medName;
                              nextDoseTime =
                                  '${candidate.month}/${candidate.day} • ${TimeOfDay(hour: candidate.hour, minute: candidate.minute).format(context)}';
                              nextDoseMed = data;
                              nextDoseMinutes = minutes;
                            }
                          }
                        }

                        Future<void> sendReminderNudge() async {
                          final caregiverUsername =
                              context.read<SessionStore>().username?.trim() ?? '';
                          await FirebaseFirestore.instance
                              .collection('elderly')
                              .doc(u)
                              .collection('caregiverNudges')
                              .add(<String, dynamic>{
                            'title': 'Medication reminder',
                            'body': 'Your caregiver is reminding you to take your meds.',
                            'from': caregiverUsername,
                            'createdAt': FieldValue.serverTimestamp(),
                          });
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Reminder sent.')),
                          );
                        }

                        Future<void> showNextDoseDetails() async {
                          if (nextAt == null || nextDoseMed == null) return;
                          final doseAmount =
                              (nextDoseMed['dosageAmount'] as String?)?.trim() ?? '';
                          final instructions =
                              (nextDoseMed['instructions'] as String?)?.trim() ?? '';
                          final minutes = nextDoseMinutes ?? 0;
                          final hh = (minutes ~/ 60).toString().padLeft(2, '0');
                          final mm = (minutes % 60).toString().padLeft(2, '0');
                          final doseId = '${nextDoseLabel.toLowerCase()}_$hh$mm';

                          await showModalBottomSheet<void>(
                            context: context,
                            useSafeArea: true,
                            showDragHandle: true,
                            builder: (ctx) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Next dose details',
                                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                                    ),
                                    const SizedBox(height: 10),
                                    Text('Medication: $nextDoseLabel',
                                        style: const TextStyle(fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 6),
                                    Text('When: $nextDoseTime'),
                                    if (doseAmount.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text('Dosage: $doseAmount'),
                                    ],
                                    if (instructions.isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Text('Instructions: $instructions'),
                                    ],
                                    const SizedBox(height: 6),
                                    Text('Dose ID: $doseId',
                                        style: TextStyle(
                                          color: Colors.black.withValues(alpha: 0.55),
                                          fontWeight: FontWeight.w700,
                                        )),
                                  ],
                                ),
                              );
                            },
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _GlassIconButton(
                                  icon: Icons.arrow_back_ios_new_rounded,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    context.pop();
                                  },
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF1E2D4A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'ID: $u',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.black.withValues(alpha: 0.55),
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                _GlassIconButton(
                                  icon: Icons.notifications_active_rounded,
                                  onTap: () async {
                                    HapticFeedback.lightImpact();
                                    try {
                                      await sendReminderNudge();
                                    } catch (e) {
                                      if (!context.mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Failed to send reminder: $e')),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            _GlassCard(
                              child: Row(
                                children: [
                                  Container(
                                    width: 52,
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Icon(Icons.bar_chart_rounded, color: cs.primary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Weekly overview • adherence, missed doses, streak, next dose, and reorders.',
                                      style: TextStyle(
                                        color: Colors.black.withValues(alpha: 0.65),
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: ListView(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _StatTile(
                                          title: 'Adherence',
                                          value: '$adherencePct%',
                                          subtitle: 'last 7 days',
                                          color: const Color(0xFF4A90D9),
                                          icon: Icons.check_circle_rounded,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _StatTile(
                                          title: 'Missed',
                                          value: '$missedDoses',
                                          subtitle: 'doses',
                                          color: const Color(0xFFE5A800),
                                          icon: Icons.priority_high_rounded,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _StatTile(
                                          title: 'Streak',
                                          value: '${streak}d',
                                          subtitle: 'complete',
                                          color: const Color(0xFF7DB8F7),
                                          icon: Icons.local_fire_department_rounded,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () async {
                                            HapticFeedback.lightImpact();
                                            await showNextDoseDetails();
                                          },
                                          child: _StatTile(
                                            title: 'Next dose',
                                            value: nextDoseLabel,
                                            subtitle: 'Tap to expand',
                                            color: const Color(0xFF4A90D9),
                                            icon: Icons.schedule_rounded,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 14),
                                  _GlassCard(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text(
                                              'Pharmacy / pill reorder',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                color: Color(0xFF1E2D4A),
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              '${meds.length} meds',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.black.withValues(alpha: 0.55),
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        if (meds.isEmpty)
                                          Text(
                                            'No medications yet.',
                                            style: TextStyle(
                                              color: Colors.black.withValues(alpha: 0.65),
                                              fontWeight: FontWeight.w700,
                                            ),
                                          )
                                        else
                                          ListView.separated(
                                            shrinkWrap: true,
                                            physics: const NeverScrollableScrollPhysics(),
                                            itemCount: meds.length,
                                            separatorBuilder: (_, __) =>
                                                const SizedBox(height: 10),
                                            itemBuilder: (context, index) {
                                              final m = meds[index].data();
                                              final medName =
                                                  (m['name'] as String?)?.trim() ?? 'Medication';
                                              final left = _readInt(m, 'totalLeft', fallback: 0);
                                              final isLow = left <= 5;
                                              return _ReorderTile(
                                                name: medName,
                                                pillsLeft: left,
                                                low: isLow,
                                                onTap: () async {
                                                  HapticFeedback.lightImpact();
                                                  await showDialog<void>(
                                                    context: context,
                                                    builder: (ctx) {
                                                      return AlertDialog(
                                                        title: const Text('Reorder request'),
                                                        content: Text(
                                                          'This is an MVP placeholder.\n\nRequest reorder for “$medName”?',
                                                        ),
                                                        actions: [
                                                          TextButton(
                                                            onPressed: () =>
                                                                Navigator.of(ctx).pop(),
                                                            child: const Text('Close'),
                                                          ),
                                                          FilledButton(
                                                            onPressed: () =>
                                                                Navigator.of(ctx).pop(),
                                                            child: const Text('Request'),
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  );
                                                },
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Icon(icon, size: 18, color: const Color(0xFF4A90D9)),
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.4),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w900,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E2D4A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReorderTile extends StatelessWidget {
  const _ReorderTile({
    required this.name,
    required this.pillsLeft,
    required this.low,
    required this.onTap,
  });

  final String name;
  final int pillsLeft;
  final bool low;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.60),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: (low ? const Color(0xFFFF5A7A) : const Color(0xFF4A90D9))
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.local_pharmacy_rounded,
                  color: low ? const Color(0xFFFF2D55) : const Color(0xFF4A90D9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E2D4A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      low ? 'Low stock • $pillsLeft left' : '$pillsLeft left',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: low
                            ? const Color(0xFFFF2D55)
                            : Colors.black.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.chevron_right_rounded, color: Color(0xFF1E2D4A)),
            ],
          ),
        ),
      ),
    );
  }
}

