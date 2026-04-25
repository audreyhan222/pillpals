import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class CaregiverElderlySelectionScreen extends StatefulWidget {
  const CaregiverElderlySelectionScreen({super.key});

  @override
  State<CaregiverElderlySelectionScreen> createState() =>
      _CaregiverElderlySelectionScreenState();
}

class _CaregiverElderlySelectionScreenState
    extends State<CaregiverElderlySelectionScreen> {
  final List<_LinkedElderly> _linked = <_LinkedElderly>[
    const _LinkedElderly(
      id: 'e-1001',
      name: 'Maria G.',
      subtitle: '3 meds • last confirmed 2h ago',
      color: Color(0xFF4A90D9),
      icon: Icons.favorite_rounded,
    ),
    const _LinkedElderly(
      id: 'e-1002',
      name: 'James P.',
      subtitle: '5 meds • 1 dose pending',
      color: Color(0xFFE5A800),
      icon: Icons.alarm_rounded,
    ),
    const _LinkedElderly(
      id: 'e-1003',
      name: 'Evelyn S.',
      subtitle: '2 meds • streak 6 days',
      color: Color(0xFF7DB8F7),
      icon: Icons.insights_rounded,
    ),
  ];

  Future<void> _promptAddPerson() async {
    final controller = TextEditingController();
    try {
      final addedId = await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Link an elderly user'),
            content: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Unique ID',
                hintText: 'e.g. e-1042',
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
                child: const Text('Add'),
              ),
            ],
          );
        },
      );

      final id = (addedId ?? '').trim();
      if (!mounted) return;
      if (id.isEmpty) return;

      final exists = _linked.any(
        (p) => p.id.toLowerCase() == id.toLowerCase(),
      );
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('That ID is already linked: $id')),
        );
        return;
      }

      setState(() {
        _linked.add(
          _LinkedElderly(
            id: id,
            name: 'Linked user',
            subtitle: 'Linked by ID • stats loading soon',
            color: const Color(0xFF4A90D9),
            icon: Icons.link_rounded,
          ),
        );
      });
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    const Expanded(
                      child: Text(
                        'Your people',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E2D4A),
                        ),
                      ),
                    ),
                    _GlassIconButton(
                      icon: Icons.person_add_alt_1_rounded,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _promptAddPerson();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.07),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF4A90D9).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.shield_rounded, color: Color(0xFF4A90D9)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Select someone to view dose stats, missed alerts, and instructions.',
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
                  child: ListView.separated(
                    itemCount: _linked.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final p = _linked[index];
                      return _PersonCard(
                        person: p,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          context.push('/caregiver/elderly/${p.id}');
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.person, required this.onTap});

  final _LinkedElderly person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(26),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(26),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1.4,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: person.color.withValues(alpha: 0.08),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: person.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(person.icon, color: person.color, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1E2D4A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      person.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.black.withValues(alpha: 0.60),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 18,
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ],
          ),
        ),
      ),
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
          child: Icon(
            icon,
            size: 18,
            color: const Color(0xFF4A90D9),
          ),
        ),
      ),
    );
  }
}

class _LinkedElderly {
  const _LinkedElderly({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final String id;
  final String name;
  final String subtitle;
  final Color color;
  final IconData icon;
}

