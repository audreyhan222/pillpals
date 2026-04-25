import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/session_store.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _petController;

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

  final _careAlerts = const <_CareAlert>[
    _CareAlert(
      title: 'Morning dose pending',
      subtitle: 'Metformin • scheduled 8:00 AM',
      severity: _CareSeverity.warning,
      icon: Icons.alarm_rounded,
      color: Color(0xFFE5A800),
    ),
    _CareAlert(
      title: 'All caught up',
      subtitle: 'No missed doses in the last 24h',
      severity: _CareSeverity.ok,
      icon: Icons.check_circle_rounded,
      color: Color(0xFF4A90D9),
    ),
    _CareAlert(
      title: 'Streak: 5 days',
      subtitle: 'Confirmed doses improving',
      severity: _CareSeverity.info,
      icon: Icons.insights_rounded,
      color: Color(0xFF7DB8F7),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _petController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _petController.dispose();
    super.dispose();
  }

  Future<void> _showPillDetails(_PillItem pill) async {
    HapticFeedback.lightImpact();
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
                    child: FilledButton(
                      onPressed: () => context.pop(),
                      child: const Text('Got it'),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final session = context.watch<SessionStore>();
    final role = session.role;

    if (role == null || role.isEmpty) {
      // Ensure the dashboard never renders without a role chosen.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/role');
      });
      return const Scaffold(body: SizedBox.shrink());
    }

    final isCaregiver = role == 'caregiver';

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
                      return Transform.translate(
                        offset: Offset(0, bob),
                        child: Transform.rotate(
                          angle: tilt,
                          child: _PetCard(
                            accent: cs.primary,
                            statusText: isCaregiver
                                ? 'Let’s check in on your person'
                                : 'I’m ready to help you today',
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),

              // Top-left circular button
              Positioned(
                top: 12,
                left: 12,
                child: _CircleNavButton(
                  icon: Icons.settings_rounded,
                  label: 'Left',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    context.push('/dashboard/left');
                  },
                ),
              ),

              // Top-right circular button
              Positioned(
                top: 12,
                right: 12,
                child: _CircleNavButton(
                  icon: Icons.notifications_rounded,
                  label: 'Right',
                  onTap: () {
                    HapticFeedback.lightImpact();
                    context.push('/dashboard/right');
                  },
                ),
              ),

              // Elderly-only: quick scan shortcut
              if (!isCaregiver)
                Positioned(
                  top: 66,
                  right: 12,
                  child: _CircleNavButton(
                    icon: Icons.camera_alt_rounded,
                    label: 'Scan',
                    onTap: () {
                      HapticFeedback.lightImpact();
                      context.push('/scan');
                    },
                  ),
                ),

              // Bottom pills panel
              Align(
                alignment: Alignment.bottomCenter,
                child: isCaregiver
                    ? _CaregiverPanel(alerts: _careAlerts)
                    : _TodayPillsPanel(
                        pills: _todayPills,
                        onPillTap: _showPillDetails,
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
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.95),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: const Color(0xFF1E2D4A), size: 22),
          ),
        ),
      ),
    );
  }
}

class _PetCard extends StatelessWidget {
  const _PetCard({required this.accent, required this.statusText});

  final Color accent;
  final String statusText;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 280,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF4A90D9).withValues(alpha: 0.08),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF7DB8F7).withValues(alpha: 0.22),
                  const Color(0xFFFFD166).withValues(alpha: 0.22),
                ],
              ),
            ),
            child: Center(
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF7DB8F7),
                      Color(0xFF4A90D9),
                      Color(0xFFFFD166),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(Icons.pets_rounded, color: Colors.white, size: 44),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1E2D4A),
              height: 1.15,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap a pill below to see details.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.black.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
            ),
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
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E2D4A),
                ),
              ),
              const Spacer(),
              Text(
                '${pills.length} total',
                style: TextStyle(
                  fontSize: 12,
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

class _CaregiverPanel extends StatelessWidget {
  const _CaregiverPanel({required this.alerts});

  final List<_CareAlert> alerts;

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
                'Care overview',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1E2D4A),
                ),
              ),
              const Spacer(),
              Text(
                '${alerts.length} updates',
                style: TextStyle(
                  fontSize: 12,
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
              itemCount: alerts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final a = alerts[index];
                return _CareAlertTile(alert: a);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CareAlertTile extends StatelessWidget {
  const _CareAlertTile({required this.alert});

  final _CareAlert alert;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          HapticFeedback.lightImpact();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(alert.subtitle)),
          );
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: alert.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(alert.icon, color: alert.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
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
                      alert.subtitle,
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
                alert.severity == _CareSeverity.warning
                    ? Icons.priority_high_rounded
                    : Icons.info_outline_rounded,
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
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
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
                        fontSize: 15,
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
}

enum _CareSeverity { ok, info, warning }

class _CareAlert {
  const _CareAlert({
    required this.title,
    required this.subtitle,
    required this.severity,
    required this.icon,
    required this.color,
  });

  final String title;
  final String subtitle;
  final _CareSeverity severity;
  final IconData icon;
  final Color color;
}

