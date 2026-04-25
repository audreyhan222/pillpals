import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class CaregiverElderlyDetailScreen extends StatelessWidget {
  const CaregiverElderlyDetailScreen({super.key, required this.elderlyId});

  final String elderlyId;

  @override
  Widget build(BuildContext context) {
    // Mock data for now; later this should come from backend.
    final profile = _ElderlyProfile.mock(elderlyId);
    final cs = Theme.of(context).colorScheme;

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
            child: Column(
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
                            profile.name,
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
                            'ID: ${profile.id}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black.withValues(alpha: 0.55),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _GlassIconButton(
                      icon: Icons.info_outline_rounded,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showDoseTooltip(context, profile);
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
                          'Weekly overview • tap “Dosage details” to see instructions.',
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
                              value: '${profile.weeklyAdherencePercent}%',
                              subtitle: 'last 7 days',
                              color: const Color(0xFF4A90D9),
                              icon: Icons.check_circle_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatTile(
                              title: 'Missed',
                              value: '${profile.weeklyMissedDoses}',
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
                              value: '${profile.streakDays}d',
                              subtitle: 'confirmed',
                              color: const Color(0xFF7DB8F7),
                              icon: Icons.insights_rounded,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatTile(
                              title: 'Next dose',
                              value: profile.nextDoseLabel,
                              subtitle: profile.nextDoseTime,
                              color: const Color(0xFF4A90D9),
                              icon: Icons.schedule_rounded,
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
                                  'Today’s medications',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF1E2D4A),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${profile.meds.length} total',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.black.withValues(alpha: 0.55),
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: profile.meds.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final m = profile.meds[index];
                                return _MedicationTile(
                                  med: m,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _showDoseTooltip(context, profile, initialMedId: m.id);
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: () {
                                  HapticFeedback.lightImpact();
                                  _showDoseTooltip(context, profile);
                                },
                                child: const Text('Dosage details'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showDoseTooltip(
    BuildContext context,
    _ElderlyProfile profile, {
    String? initialMedId,
  }) async {
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
        final meds = profile.meds;
        final initialIndex = initialMedId == null
            ? 0
            : meds.indexWhere((m) => m.id == initialMedId).clamp(0, meds.length - 1);
        return DraggableScrollableSheet(
          expand: false,
          minChildSize: 0.35,
          initialChildSize: 0.62,
          maxChildSize: 0.92,
          builder: (context, controller) {
            return ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90D9).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.medication_outlined, color: Color(0xFF4A90D9)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Dosage tooltip',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Scroll for times + instructions',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.black.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SegmentedPicker(
                  meds: meds,
                  initialIndex: initialIndex,
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _SegmentedPicker extends StatefulWidget {
  const _SegmentedPicker({required this.meds, required this.initialIndex});

  final List<_Medication> meds;
  final int initialIndex;

  @override
  State<_SegmentedPicker> createState() => _SegmentedPickerState();
}

class _SegmentedPickerState extends State<_SegmentedPicker> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final med = widget.meds[_index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (int i = 0; i < widget.meds.length; i++) ...[
                ChoiceChip(
                  label: Text(widget.meds[i].name),
                  selected: i == _index,
                  onSelected: (_) => setState(() => _index = i),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${med.dosage} • ${med.times.join(' • ')}',
          style: TextStyle(
            fontSize: 13,
            color: Colors.black.withValues(alpha: 0.62),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          med.instructions,
          style: const TextStyle(
            fontSize: 15,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        const Divider(height: 24),
        Text(
          'Dose history (mock)',
          style: TextStyle(
            fontSize: 13,
            color: Colors.black.withValues(alpha: 0.55),
            fontWeight: FontWeight.w800,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(height: 10),
        ...med.history.map(
          (h) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _HistoryRow(item: h),
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item});

  final _DoseHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final color = item.status == _DoseStatus.confirmed
        ? const Color(0xFF4A90D9)
        : const Color(0xFFE5A800);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              item.status == _DoseStatus.confirmed
                  ? Icons.check_rounded
                  : Icons.priority_high_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E2D4A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.6),
                    fontWeight: FontWeight.w700,
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

class _MedicationTile extends StatelessWidget {
  const _MedicationTile({required this.med, required this.onTap});

  final _Medication med;
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: med.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(med.icon, color: med.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      med.name,
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
                      '${med.dosage} • ${med.times.join(' • ')}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
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
                size: 18,
              ),
            ],
          ),
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
    return _GlassCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
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
                    color: Colors.black.withValues(alpha: 0.58),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
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
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withValues(alpha: 0.55),
                    fontWeight: FontWeight.w700,
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

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
            offset: const Offset(0, 10),
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
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.9),
            width: 1.5,
          ),
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

class _ElderlyProfile {
  const _ElderlyProfile({
    required this.id,
    required this.name,
    required this.weeklyAdherencePercent,
    required this.weeklyMissedDoses,
    required this.streakDays,
    required this.nextDoseLabel,
    required this.nextDoseTime,
    required this.meds,
  });

  final String id;
  final String name;
  final int weeklyAdherencePercent;
  final int weeklyMissedDoses;
  final int streakDays;
  final String nextDoseLabel;
  final String nextDoseTime;
  final List<_Medication> meds;

  static _ElderlyProfile mock(String id) {
    if (id == 'e-1002') {
      return const _ElderlyProfile(
        id: 'e-1002',
        name: 'James P.',
        weeklyAdherencePercent: 86,
        weeklyMissedDoses: 2,
        streakDays: 4,
        nextDoseLabel: 'Metformin',
        nextDoseTime: '8:00 AM',
        meds: [
          _Medication(
            id: 'm1',
            name: 'Metformin',
            dosage: '500mg',
            times: ['8:00 AM', '8:00 PM'],
            instructions: 'Take with food. Drink water if nauseous.',
            color: Color(0xFF4A90D9),
            icon: Icons.medication_outlined,
            history: [
              _DoseHistoryItem(
                label: 'Today • 8:00 AM',
                subtitle: 'Confirmed',
                status: _DoseStatus.confirmed,
              ),
              _DoseHistoryItem(
                label: 'Yesterday • 8:00 PM',
                subtitle: 'Missed',
                status: _DoseStatus.missed,
              ),
            ],
          ),
          _Medication(
            id: 'm2',
            name: 'Atorvastatin',
            dosage: '20mg',
            times: ['9:00 PM'],
            instructions: 'Take at night. Avoid grapefruit.',
            color: Color(0xFF7DB8F7),
            icon: Icons.nightlight_round,
            history: [
              _DoseHistoryItem(
                label: 'Yesterday • 9:00 PM',
                subtitle: 'Confirmed',
                status: _DoseStatus.confirmed,
              ),
              _DoseHistoryItem(
                label: '2 days ago • 9:00 PM',
                subtitle: 'Confirmed',
                status: _DoseStatus.confirmed,
              ),
            ],
          ),
        ],
      );
    }

    return const _ElderlyProfile(
      id: 'e-1001',
      name: 'Maria G.',
      weeklyAdherencePercent: 93,
      weeklyMissedDoses: 1,
      streakDays: 6,
      nextDoseLabel: 'Vitamin D',
      nextDoseTime: '12:00 PM',
      meds: [
        _Medication(
          id: 'm1',
          name: 'Metformin',
          dosage: '500mg',
          times: ['8:00 AM'],
          instructions: 'Take with food. If you feel nauseous, eat a small snack.',
          color: Color(0xFF4A90D9),
          icon: Icons.medication_outlined,
          history: [
            _DoseHistoryItem(
              label: 'Today • 8:00 AM',
              subtitle: 'Confirmed',
              status: _DoseStatus.confirmed,
            ),
            _DoseHistoryItem(
              label: 'Yesterday • 8:00 AM',
              subtitle: 'Confirmed',
              status: _DoseStatus.confirmed,
            ),
          ],
        ),
        _Medication(
          id: 'm2',
          name: 'Vitamin D',
          dosage: '1 capsule',
          times: ['12:00 PM'],
          instructions: 'Take with a meal. If missed, take later today.',
          color: Color(0xFFE5A800),
          icon: Icons.sunny,
          history: [
            _DoseHistoryItem(
              label: 'Yesterday • 12:00 PM',
              subtitle: 'Confirmed',
              status: _DoseStatus.confirmed,
            ),
            _DoseHistoryItem(
              label: '2 days ago • 12:00 PM',
              subtitle: 'Missed',
              status: _DoseStatus.missed,
            ),
          ],
        ),
      ],
    );
  }
}

class _Medication {
  const _Medication({
    required this.id,
    required this.name,
    required this.dosage,
    required this.times,
    required this.instructions,
    required this.color,
    required this.icon,
    required this.history,
  });

  final String id;
  final String name;
  final String dosage;
  final List<String> times;
  final String instructions;
  final Color color;
  final IconData icon;
  final List<_DoseHistoryItem> history;
}

enum _DoseStatus { confirmed, missed }

class _DoseHistoryItem {
  const _DoseHistoryItem({
    required this.label,
    required this.subtitle,
    required this.status,
  });

  final String label;
  final String subtitle;
  final _DoseStatus status;
}

