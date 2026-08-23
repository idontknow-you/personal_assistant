import 'package:flutter/material.dart';
import '../../models/habits/habit.dart';
import '../../theme/app_theme.dart';

class WeekdayHeader extends StatelessWidget {
  const WeekdayHeader({super.key, required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: labels
            .map((l) => Expanded(
                  child: Center(
                    child: Text(
                      l,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
                ))
            .toList(),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.label, required this.theme});
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class HabitAgendaTile extends StatelessWidget {
  const HabitAgendaTile({
    super.key,
    required this.habit,
    required this.status,
    required this.statusColor,
    this.onTap,
  });

  final Habit habit;
  final HabitDayStatus? status;
  final Color statusColor;

  /// Null for future days — you can't mark a habit done/skipped/missed for
  /// a day that hasn't happened yet.
  final VoidCallback? onTap;

  String _statusLabel() {
    if (onTap == null) return 'Not due yet';
    switch (status) {
      case HabitDayStatus.done:
        return 'Done';
      case HabitDayStatus.skipped:
        return 'Skipped';
      case HabitDayStatus.missed:
        return 'Missed';
      case null:
        return 'Not marked — tap to cycle';
    }
  }

  IconData? _statusIcon() {
    switch (status) {
      case HabitDayStatus.done:
        return Icons.check;
      case HabitDayStatus.missed:
        return Icons.close;
      case HabitDayStatus.skipped:
      case null:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _statusIcon();
    final isFuture = onTap == null;
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isFuture ? statusColor.withValues(alpha: 0.3) : statusColor,
        ),
        child: icon != null
            ? Icon(icon, size: 16, color: Colors.white)
            : null,
      ),
      title: Text(
        habit.name,
        style: isFuture
            ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
      subtitle: Text(_statusLabel()),
      trailing: habit.currentStreak > 0
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.local_fire_department,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: 2),
                Text('${habit.currentStreak}', style: theme.textTheme.bodySmall),
              ],
            )
          : null,
    );
  }
}
