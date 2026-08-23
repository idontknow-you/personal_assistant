import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';
import '../../models/habits/habit.dart';

class MonthGrid extends StatelessWidget {
  const MonthGrid({
    super.key,
    required this.visibleMonth,
    required this.selectedDay,
    required this.byDayTasks,
    required this.byDayHabits,
    required this.taskStatusOn,
    required this.habitStatusOn,
    required this.priorityColor,
    required this.habitStatusColor,
    required this.onSelectDay,
  });

  final DateTime visibleMonth;
  final DateTime selectedDay;
  final Map<String, List<Task>> byDayTasks;
  final Map<String, List<Habit>> byDayHabits;
  final bool? Function(Task, DateTime) taskStatusOn;
  final HabitDayStatus? Function(Habit, DateTime) habitStatusOn;
  final Color Function(Priority) priorityColor;
  final Color Function(HabitDayStatus?) habitStatusColor;
  final void Function(DateTime) onSelectDay;

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final firstOfMonth = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leadingBlanks = firstOfMonth.weekday - 1;
    final totalCells = leadingBlanks + daysInMonth;
    final rows = (totalCells / 7).ceil();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: 1,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: rows * 7,
      itemBuilder: (context, index) {
        final dayNum = index - leadingBlanks + 1;
        if (dayNum < 1 || dayNum > daysInMonth) {
          return const SizedBox.shrink();
        }
        final day = DateTime(visibleMonth.year, visibleMonth.month, dayNum);
        final tasksToday = byDayTasks[_key(day)] ?? [];
        final habitsToday = byDayHabits[_key(day)] ?? [];
        final isToday = day.year == today.year &&
            day.month == today.month &&
            day.day == today.day;
        final isSelected = day.year == selectedDay.year &&
            day.month == selectedDay.month &&
            day.day == selectedDay.day;
        final isPast = day.isBefore(today);

        final allTasksDone = tasksToday.isNotEmpty &&
            tasksToday.every((t) => taskStatusOn(t, day) ?? false);
        final hasMissedTask = isPast &&
            tasksToday.isNotEmpty &&
            tasksToday.any((t) => !(taskStatusOn(t, day) ?? false));

        Color? bg;
        if (isSelected) {
          bg = theme.colorScheme.primary;
        } else if (allTasksDone && tasksToday.isNotEmpty) {
          bg = theme.colorScheme.primaryContainer;
        } else if (hasMissedTask) {
          bg = theme.colorScheme.errorContainer.withValues(alpha: 0.5);
        }

        final textColor =
            isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

        final indicators = <Widget>[];
        for (final t in tasksToday.take(3)) {
          indicators.add(Container(
            width: 4,
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            decoration: BoxDecoration(
              color: isSelected ? theme.colorScheme.onPrimary : priorityColor(t.priority),
              shape: BoxShape.circle,
            ),
          ));
        }
        final remainingSlots = 3 - indicators.length;
        if (remainingSlots > 0) {
          for (final h in habitsToday.take(remainingSlots)) {
            indicators.add(Container(
              width: 4,
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: isSelected
                    ? theme.colorScheme.onPrimary
                    : habitStatusColor(habitStatusOn(h, day)),
                shape: BoxShape.rectangle,
              ),
            ));
          }
        }

        return GestureDetector(
          onTap: () => onSelectDay(day),
          child: Container(
            margin: const EdgeInsets.all(1),
            decoration: BoxDecoration(
              color: bg,
              shape: BoxShape.circle,
              border: isToday && !isSelected
                  ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$dayNum',
                  style: theme.textTheme.bodyMedium?.copyWith(color: textColor),
                ),
                if (indicators.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: indicators,
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
