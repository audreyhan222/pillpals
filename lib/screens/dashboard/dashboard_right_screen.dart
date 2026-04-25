import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/pill_completion_store.dart';
import 'package:flutter/foundation.dart';

class DashboardRightScreen extends StatelessWidget {
  const DashboardRightScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<PillCompletionStore>();
    const expectedDoseCount = 3; // Matches the current "Today’s pills" list.
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
                const Text(
                  'Calendar',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF1E2D4A),
                  ),
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
                      expectedDoseCount: expectedDoseCount,
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
  });

  final PillCompletionStore store;
  final int expectedDoseCount;

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
    final selectedTaken = widget.store.takenDoseIdsForDay(_selected).toList()
      ..sort();
    final isSelectedComplete = widget.store.isDayComplete(
      date: _selected,
      expectedDoseCount: widget.expectedDoseCount,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (kDebugMode) ...[
          _DevResetRow(
            onResetSelected: () async {
              await widget.store.clearDay(_selected);
              if (!mounted) return;
              setState(() {});
            },
            onResetAll: () async {
              await widget.store.clearAll();
              if (!mounted) return;
              setState(() {});
            },
            onJumpToday: () {
              final now = DateTime.now();
              setState(() {
                _selected = DateTime(now.year, now.month, now.day);
                _month = DateTime(now.year, now.month);
              });
            },
          ),
          const SizedBox(height: 10),
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelectedComplete
                          ? const Color(0xFFDBF7E8)
                          : const Color(0xFFE8EFFE),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.9),
                        width: 1.0,
                      ),
                    ),
                    child: Text(
                      isSelectedComplete ? 'All taken ✅' : 'Not complete yet',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: isSelectedComplete ? const Color(0xFF1E6A4B) : accent,
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
              Text(
                selectedTaken.isEmpty
                    ? 'No pills marked taken on this day yet.'
                    : 'Taken (${selectedTaken.length}/${widget.expectedDoseCount}): ${selectedTaken.join(', ')}',
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

class _DevResetRow extends StatelessWidget {
  const _DevResetRow({
    required this.onResetSelected,
    required this.onResetAll,
    required this.onJumpToday,
  });

  final VoidCallback onJumpToday;
  final Future<void> Function() onResetSelected;
  final Future<void> Function() onResetAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 1.25),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Dev tools',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 0.35,
              fontWeight: FontWeight.w900,
              color: Colors.black.withValues(alpha: 0.60),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onJumpToday,
                  icon: const Icon(Icons.today_rounded),
                  label: const Text('Today'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => onResetSelected(),
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Reset day'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFFE8E8),
              foregroundColor: const Color(0xFF8A1F1F),
            ),
            onPressed: () => onResetAll(),
            icon: const Icon(Icons.delete_forever_rounded),
            label: const Text('Reset ALL history'),
          ),
        ],
      ),
    );
  }
}

