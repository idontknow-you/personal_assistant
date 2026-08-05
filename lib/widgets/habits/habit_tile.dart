import 'package:flutter/material.dart';
import '../../models/habits/habit.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';

class HabitTile extends StatelessWidget {
  final Habit habit;
  final void Function(DateTime date) onDotTap;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const HabitTile({
    super.key,
    required this.habit,
    required this.onDotTap,
    this.onTap,
    this.onLongPress,
  });

  Color _dotColor(HabitDayStatus? status, bool expected) {
    if (!expected) return AppColors.skip.withOpacity(0.15);
    switch (status) {
      case HabitDayStatus.done:
        return AppColors.success;
      case HabitDayStatus.skipped:
        return AppColors.skip;
      case HabitDayStatus.missed:
        return AppColors.error;
      case null:
        return AppColors.skip.withOpacity(0.25);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = startOfDay(DateTime.now());
    // Last 7 days, oldest first, today last.
    final days = List.generate(
      7,
      (i) => today.subtract(Duration(days: 6 - i)),
    );

    return Card(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      habit.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  if (habit.currentStreak > 0) ...[
                    const Icon(Icons.local_fire_department,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 2),
                    Text(
                      '${habit.currentStreak}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: days.map((day) {
                  final isToday = isSameDay(day, today);
                  final expected = habit.isExpectedOn(day.weekday);
                  final status = habit.statusOn(dateKey(day));
                  return GestureDetector(
                    onTap: expected ? () => onDotTap(day) : null,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _dotColor(status, expected),
                        border: isToday
                            ? Border.all(color: AppColors.primary, width: 2)
                            : null,
                      ),
                      child: status == HabitDayStatus.done
                          ? const Icon(Icons.check, size: 14, color: Colors.white)
                          : status == HabitDayStatus.missed
                              ? const Icon(Icons.close,
                                  size: 14, color: Colors.white)
                              : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}