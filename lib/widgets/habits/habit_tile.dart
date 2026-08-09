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

  static const _weekdayLetters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final today = startOfDay(DateTime.now());
    // Fixed Monday-Sunday week (today.weekday: 1=Mon..7=Sun), so the strip
    // resets visually every week instead of scrolling as a rolling 7-day
    // window. Streak math underneath is unaffected — it's still continuous
    // day-to-day regardless of week boundaries.
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final days = List.generate(7, (i) => monday.add(Duration(days: i)));
    final primaryColor = Theme.of(context).colorScheme.primary;

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
                  final letter = _weekdayLetters[day.weekday - 1];
                  final showIcon = status == HabitDayStatus.done ||
                      status == HabitDayStatus.missed;

                  // Letter color needs contrast against whatever _dotColor
                  // returns; done/missed dots are solid saturated colors so
                  // white works, everything else is a light tint so a
                  // muted dark tone reads better.
                  final letterColor = (status == HabitDayStatus.skipped)
                      ? Colors.white.withOpacity(0.85)
                      : Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.color
                          ?.withOpacity(0.6);

                  return GestureDetector(
                    // Only today's dot is editable. Past/future dots are
                    // read-only history/placeholders.
                    onTap:
                        (isToday && expected) ? () => onDotTap(day) : null,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _dotColor(status, expected),
                        border: isToday
                            ? Border.all(color: primaryColor, width: 2)
                            : null,
                      ),
                      child: Center(
                        child: showIcon
                            ? Icon(
                                status == HabitDayStatus.done
                                    ? Icons.check
                                    : Icons.close,
                                size: 14,
                                color: Colors.white,
                              )
                            : Text(
                                letter,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: letterColor,
                                ),
                              ),
                      ),
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