import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/pill_completion_store.dart';
import '../../state/session_store.dart';

class DashboardRightScreen extends StatelessWidget {
  const DashboardRightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PillCompletionStore>();
    final session = context.watch<SessionStore>();
    final username = session.username?.trim() ?? '';
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
                _GlassIconButton(
                  icon: Icons.arrow_back_ios_new_rounded,
                  onTap: () => context.pop(),
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Expanded(
                      child: Text(
                        'Calendar',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1E2D4A),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => context.push('/ocr/labels'),
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text('Label library'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF2E7D6A),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.9),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.07),
                          blurRadius: 24,
                          offset: const Offset(0, 8),
                        ),
                        BoxShadow(
                          color: const Color(0xFF4A90D9)
                              .withValues(alpha: 0.08),
                          blurRadius: 32,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: _PillCalendarCard(
                      store: store,
                      expectedDoseCount: 0,
                      elderlyUsername: username,
                    ),
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

class _PillCalendarCard extends StatefulWidget {
  const _PillCalendarCard({
    required this.store,
    required this.expectedDoseCount,
    required this.elderlyUsername,
  });

  final PillCompletionStore store;
  final int expectedDoseCount;
  final String elderlyUsername;

  @override
  State<_PillCalendarCard> createState() => _PillCalendarCardState();
}

class _PillCalendarCardState extends State<_PillCalendarCard> {
  late DateTime _month;
  DateTime _selected = DateTime.now();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _prevMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF1E2D4A);
    const accent = Color(0xFF4A90D9);

    final header = '${_monthNames[_month.month - 1]} ${_month.year}';
    final selectedKey = PillCompletionStore.dayKey(_selected);
    final selectedTaken = widget.store.takenDoseIdsForDay(_selected).toList()..sort();
    final username = widget.elderlyUsername.trim();
    final statusRef = username.isEmpty
        ? null
        : FirebaseFirestore.instance
            .collection('elderly')
            .doc(username)
            .collection('dailyStatus')
            .doc(selectedKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (username.isNotEmpty) ...[
          _StreakHeader(elderlyUsername: username),
          const SizedBox(height: 14),
        ],
        Row(
          children: [
            _MiniGlassIconButton(icon: Icons.chevron_left_rounded, onTap: _prevMonth),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                header,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: dark,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _MiniGlassIconButton(icon: Icons.chevron_right_rounded, onTap: _nextMonth),
          ],
        ),
        const SizedBox(height: 12),
        _WeekdayHeaderRow(),
        const SizedBox(height: 10),
        Expanded(
          child: _MonthGrid(
            month: _month,
            selected: _selected,
            expectedDoseCount: widget.expectedDoseCount,
            isComplete: (date) => widget.store.isDayComplete(
              date: date,
              expectedDoseCount: widget.expectedDoseCount,
            ),
            onSelect: (date) => setState(() => _selected = date),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.70),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.25),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Selected day',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 0.35,
                        fontWeight: FontWeight.w800,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  if (statusRef != null)
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: statusRef.snapshots(),
                      builder: (context, snap) {
                        final data = snap.data?.data();
                        final complete = data?['complete'] == true;
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: complete
                                ? const Color(0xFFDBF7E8)
                                : const Color(0xFFE8EFFE),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.9),
                              width: 1.0,
                            ),
                          ),
                          child: Text(
                            complete ? 'All taken ✅' : 'Not complete yet',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: complete ? const Color(0xFF1E6A4B) : accent,
                            ),
                          ),
                        );
                      },
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8EFFE),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.9),
                          width: 1.0,
                        ),
                      ),
                      child: const Text(
                        'Sign in to track',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: accent,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                selectedKey,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: dark,
                ),
              ),
              const SizedBox(height: 6),
              if (statusRef != null)
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: statusRef.snapshots(),
                  builder: (context, snap) {
                    final data = snap.data?.data();
                    int readInt(String key, {required int fallback}) {
                      final v = data?[key];
                      if (v is int) return v;
                      if (v is num) return v.round();
                      return fallback;
                    }

                    final takenCount =
                        readInt('takenCount', fallback: selectedTaken.length);
                    final expectedCount = readInt('expectedCount', fallback: 0);
                    final label = expectedCount > 0
                        ? 'Taken ($takenCount/$expectedCount)'
                        : 'Taken ($takenCount)';
                    return Text(
                      takenCount == 0 ? 'No pills marked taken on this day yet.' : label,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.25,
                        fontWeight: FontWeight.w700,
                        color: Colors.black.withValues(alpha: 0.60),
                      ),
                    );
                  },
                )
              else
                Text(
                  selectedTaken.isEmpty
                      ? 'No pills marked taken on this day yet.'
                      : 'Taken (${selectedTaken.length})',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: Colors.black.withValues(alpha: 0.60),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StreakHeader extends StatelessWidget {
  const _StreakHeader({required this.elderlyUsername});

  final String elderlyUsername;

  static DateTime _parseDayKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return DateTime.now();
    final y = int.tryParse(parts[0]) ?? DateTime.now().year;
    final m = int.tryParse(parts[1]) ?? DateTime.now().month;
    final d = int.tryParse(parts[2]) ?? DateTime.now().day;
    return DateTime(y, m, d);
  }

  static String _dayKey(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  @override
  Widget build(BuildContext context) {
    final u = elderlyUsername.trim();
    final ref = FirebaseFirestore.instance
        .collection('elderly')
        .doc(u)
        .collection('dailyStatus')
        .orderBy('dayKey', descending: true)
        .limit(120);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (context, snap) {
        int current = 0;
        int best = 0;

        final completeDays = <String, bool>{};
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
            final data = doc.data();
            final key = (data['dayKey'] as String?)?.trim() ?? doc.id;
            final complete = data['complete'] == true;
            if (key.isNotEmpty) completeDays[key] = complete;
          }
        }

        final today = DateTime.now();
        DateTime cursor = DateTime(today.year, today.month, today.day);
        while (true) {
          final k = _dayKey(cursor);
          if (completeDays[k] == true) {
            current++;
            cursor = cursor.subtract(const Duration(days: 1));
            continue;
          }
          break;
        }

        final keys = completeDays.keys.toList()
          ..sort((a, b) => _parseDayKey(a).compareTo(_parseDayKey(b)));
        int run = 0;
        DateTime? prev;
        for (final k in keys) {
          if (completeDays[k] != true) {
            run = 0;
            prev = null;
            continue;
          }
          final dt = _parseDayKey(k);
          if (prev == null || dt.difference(prev).inDays == 1) {
            run += 1;
          } else {
            run = 1;
          }
          if (run > best) best = run;
          prev = dt;
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.4),
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
                  color: const Color(0xFFDBF7E8).withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Color(0xFF1E6A4B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Streak',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.35,
                        color: Color(0xFF1E2D4A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$current days in a row',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Best: $best days',
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
      },
    );
  }
}

class _MiniGlassIconButton extends StatelessWidget {
  const _MiniGlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.9),
            width: 1.4,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Icon(
            icon,
            size: 26,
            color: const Color(0xFF4A90D9),
          ),
        ),
      ),
    );
  }
}

class _WeekdayHeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const labels = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Row(
      children: [
        for (final l in labels)
          Expanded(
            child: Text(
              l,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Colors.black.withValues(alpha: 0.55),
                letterSpacing: 0.35,
              ),
            ),
          ),
      ],
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.expectedDoseCount,
    required this.isComplete,
    required this.onSelect,
  });

  final DateTime month;
  final DateTime selected;
  final int expectedDoseCount;
  final bool Function(DateTime date) isComplete;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month, 1);
    final firstWeekday = first.weekday % 7; // Sunday=0
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final totalCells = ((firstWeekday + daysInMonth) <= 35) ? 35 : 42;
    final today = DateTime.now();
    final todayKey = PillCompletionStore.dayKey(today);

    return GridView.builder(
      physics: const BouncingScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.0,
      ),
      itemCount: totalCells,
      itemBuilder: (context, index) {
        final dayNumber = index - firstWeekday + 1;
        if (dayNumber < 1 || dayNumber > daysInMonth) {
          return const SizedBox.shrink();
        }

        final date = DateTime(month.year, month.month, dayNumber);
        final key = PillCompletionStore.dayKey(date);
        final selectedKey = PillCompletionStore.dayKey(selected);

        final complete = isComplete(date);
        final isSelected = key == selectedKey;
        final isToday = key == todayKey;

        final bg = isSelected
            ? const Color(0xFF4A90D9).withValues(alpha: 0.20)
            : Colors.white.withValues(alpha: 0.65);

        final border = isSelected
            ? const Color(0xFF4A90D9).withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.9);

        return GestureDetector(
          onTap: () => onSelect(date),
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border, width: 1.25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              children: [
                Center(
                  child: Text(
                    '$dayNumber',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E2D4A),
                    ),
                  ),
                ),
                if (isToday)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFFFFA000),
                      ),
                    ),
                  ),
                if (complete)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF1E6A4B),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

const _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

