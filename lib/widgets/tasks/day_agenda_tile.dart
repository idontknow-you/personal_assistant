import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';

/// A single task's row in the calendar's day agenda. Unlike TaskTile, this
/// is scoped to one specific [day] rather than the task's live [completed]
/// field — its checkbox reflects [completed] as passed in by the caller
/// (looked up from [Task.completionLog] for that day), and toggling it
/// should go through TaskService.setCompletionForDate rather than
/// toggleComplete, since the day shown here may not be the task's current
/// active period.
class DayAgendaTile extends StatelessWidget {
  const DayAgendaTile({
    super.key,
    required this.task,
    required this.day,
    required this.completed,
    required this.onToggle,
  });

  final Task task;
  final DateTime day;
  final bool completed;
  final VoidCallback onToggle;

  Color _priorityColor(ColorScheme scheme) {
    switch (task.priority) {
      case Priority.high:
        return scheme.error;
      case Priority.medium:
        return scheme.tertiary;
      case Priority.low:
        return scheme.secondary;
    }
  }

  String? _repeatLabel() {
    switch (task.repeatType) {
      case TaskRepeatType.daily:
        return 'Daily';
      case TaskRepeatType.weekly:
        return 'Weekly';
      case TaskRepeatType.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repeatLabel = _repeatLabel();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: _priorityColor(theme.colorScheme), width: 4),
        ),
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        leading: Checkbox(
          value: completed,
          onChanged: (_) => onToggle(),
        ),
        title: Text(
          task.title,
          style: theme.textTheme.bodyLarge?.copyWith(
            decoration: completed ? TextDecoration.lineThrough : null,
            color: completed ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: repeatLabel != null
            ? Text(
                repeatLabel,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            : null,
      ),
    );
  }
}