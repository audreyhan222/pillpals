import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../state/session_store.dart';

class CaregiverElderlySelectionScreen extends StatefulWidget {
  const CaregiverElderlySelectionScreen({super.key});

  @override
  State<CaregiverElderlySelectionScreen> createState() =>
      _CaregiverElderlySelectionScreenState();
}

class _CaregiverElderlySelectionScreenState
    extends State<CaregiverElderlySelectionScreen> {
  final List<_LinkedElderly> _linked = <_LinkedElderly>[];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadLinked();
  }

  Future<void> _loadLinked() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final caregiverUsername =
          context.read<SessionStore>().username?.trim() ?? '';
      if (caregiverUsername.isEmpty) {
        throw Exception('Missing caregiver username in session.');
      }

      final caregiverDoc = await FirebaseFirestore.instance
          .collection('caretaker')
          .doc(caregiverUsername)
          .get();
      final data = caregiverDoc.data();
      final patients = (data?['patients'] as List?)?.cast<dynamic>() ?? const [];

      final items = <_LinkedElderly>[];
      for (final p in patients) {
        final m = (p is Map) ? p : null;
        final code = (m?['connectCode'] as String?)?.trim() ?? '';
        final elderlyUsername = (m?['elderlyUsername'] as String?)?.trim() ?? '';
        final name = (m?['elderlyName'] as String?)?.trim() ?? 'Linked user';
        if (code.isEmpty) continue;
        final subtitle = elderlyUsername.isNotEmpty
            ? 'Code $code • $elderlyUsername'
            : 'Code $code';
        items.add(
          _LinkedElderly(
            id: code,
            name: name,
            subtitle: subtitle,
            elderlyUsername: elderlyUsername,
            color: const Color(0xFF4A90D9),
            icon: Icons.link_rounded,
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _linked
          ..clear()
          ..addAll(items);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _promptAddPerson() async {
    final controller = TextEditingController();
    try {
      final addedId = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Link an elderly user'),
            content: TextField(
              controller: controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Connect code',
                hintText: 'e.g. ABCD2345',
              ),
              onSubmitted: (_) => Navigator.of(dialogContext).pop(controller.text),
            ),
            actions: [
              TextButton(
                // Empty string = cancelled (same pattern as pal rename; avoids null/edge issues).
                onPressed: () => Navigator.of(dialogContext).pop(''),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(controller.text),
                child: const Text('Add'),
              ),
            ],
          );
        },
      );

      if (!mounted) return;
      final id = (addedId ?? '').trim();
      // Cancel: no lookup / no SnackBar errors.
      if (id.isEmpty) return;

      final code = id.toUpperCase();
      final exists = _linked.any((p) => p.id.toUpperCase() == code);
      if (exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('That code is already linked: $code')),
        );
        return;
      }

      final caregiverUsername =
          context.read<SessionStore>().username?.trim() ?? '';
      if (caregiverUsername.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Missing caregiver username in session.')),
        );
        return;
      }

      // Resolve connect code -> elderly username
      final codeDoc = await FirebaseFirestore.instance
          .collection('connectCodes')
          .doc(code)
          .get();
      if (!codeDoc.exists) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No elderly account found for code: $code')),
        );
        return;
      }
      final elderlyUsername =
          (codeDoc.data()?['elderlyUsername'] as String?)?.trim() ?? '';

      String elderlyName = 'Linked user';
      if (elderlyUsername.isNotEmpty) {
        final elderlyDoc = await FirebaseFirestore.instance
            .collection('elderly')
            .doc(elderlyUsername)
            .get();
        elderlyName = (elderlyDoc.data()?['name'] as String?)?.trim() ?? elderlyName;
      }

      await FirebaseFirestore.instance
          .collection('caretaker')
          .doc(caregiverUsername)
          .set(
        <String, dynamic>{
          'patients': FieldValue.arrayUnion([
            <String, dynamic>{
              'connectCode': code,
              'elderlyUsername': elderlyUsername,
              'elderlyName': elderlyName,
              // NOTE: serverTimestamp is not allowed inside arrayUnion elements.
              // Use a concrete timestamp value to avoid crashes.
              'linkedAt': Timestamp.now(),
            }
          ]),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      if (!mounted) return;
      setState(() {
        _linked.add(
          _LinkedElderly(
            id: code,
            name: elderlyName,
            subtitle: elderlyUsername.isNotEmpty
                ? 'Code $code • $elderlyUsername'
                : 'Code $code',
            elderlyUsername: elderlyUsername,
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
                    _GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        context.go('/');
                      },
                    ),
                    const SizedBox(width: 10),
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
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Text(
                                _error!,
                                textAlign: TextAlign.center,
                              ),
                            )
                          : _linked.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 18),
                                    child: Text(
                                      'No linked patients yet.\nTap the + button to add someone using their connect code.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Colors.black.withValues(alpha: 0.65),
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                )
                          : ListView.separated(
                              itemCount: _linked.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final p = _linked[index];
                                return _PersonCard(
                                  person: p,
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    final target =
                                        p.elderlyUsername.isNotEmpty ? p.elderlyUsername : p.id;
                                    context.push('/caregiver/elderly/$target');
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
                    if (person.elderlyUsername.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _PatientDayStatusLine(elderlyUsername: person.elderlyUsername),
                    ],
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
    required this.elderlyUsername,
    required this.color,
    required this.icon,
  });

  final String id;
  final String name;
  final String subtitle;
  final String elderlyUsername;
  final Color color;
  final IconData icon;
}

class _PatientDayStatusLine extends StatelessWidget {
  const _PatientDayStatusLine({required this.elderlyUsername});

  final String elderlyUsername;

  static String _dayKey(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final username = elderlyUsername.trim();
    if (username.isEmpty) return const SizedBox.shrink();

    final db = FirebaseFirestore.instance;
    final todayKey = _dayKey(DateTime.now());
    final catalogStream = db
        .collection('elderly')
        .doc(username)
        .collection('medicationCatalog')
        .snapshots();
    final statusStream = db
        .collection('elderly')
        .doc(username)
        .collection('dailyStatus')
        .doc(todayKey)
        .snapshots();

    TextStyle style() => TextStyle(
          fontSize: 12,
          color: Colors.black.withValues(alpha: 0.62),
          fontWeight: FontWeight.w800,
        );

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: catalogStream,
      builder: (context, catSnap) {
        if (catSnap.hasData && catSnap.data!.docs.isEmpty) {
          // "Throw exception" behavior requested: treat empty catalog as a non-fatal
          // exceptional state and show an explicit "no medications" status instead.
          return Text('No medications', style: style(), maxLines: 1);
        }

        int totalLeft = 0;
        if (catSnap.hasData) {
          for (final doc in catSnap.data!.docs) {
            final v = doc.data()['totalLeft'];
            if (v is int) totalLeft += v;
            if (v is num) totalLeft += v.round();
          }
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: statusStream,
          builder: (context, statusSnap) {
            int takenToday = 0;
            if (statusSnap.hasData) {
              final data = statusSnap.data!.data();
              final v = data?['takenCount'];
              if (v is int) takenToday = v;
              if (v is num) takenToday = v.round();
            }

            final leftText =
                catSnap.connectionState == ConnectionState.waiting && !catSnap.hasData
                    ? 'Left: …'
                    : 'Left: $totalLeft';
            final takenText = statusSnap.connectionState == ConnectionState.waiting &&
                    !statusSnap.hasData
                ? 'Taken today: …'
                : 'Taken today: $takenToday';

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.85),
                  width: 1.2,
                ),
              ),
              child: Text('$leftText • $takenText', style: style(), maxLines: 1),
            );
          },
        );
      },
    );
  }
}

