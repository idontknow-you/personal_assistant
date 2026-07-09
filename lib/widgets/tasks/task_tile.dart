import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onDismissed,
    this.onEdit,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onDismissed;
  final VoidCallback? onEdit;

  bool get _isOverdue {
    if (task.completed || task.dueDate == null) return false;
    final due = task.dueDate!.toDate();
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    return due.isBefore(todayStart);
  }

  String? _dueDateLabel() {
    if (task.dueDate == null) return null;
    final due = task.dueDate!.toDate();
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    final dueStart = DateTime(due.year, due.month, due.day);
    final diff = dueStart.difference(todayStart).inDays;

    final dateStr = '${due.day}/${due.month}/${due.year}';
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff == -1) return 'Yesterday';
    if (_isOverdue) return 'Overdue · $dateStr';
    return dateStr;
  }

  String? _repeatLabel() {
    switch (task.repeatType) {
      case TaskRepeatType.daily:
        return 'Daily';
      case TaskRepeatType.weekly:
        return task.repeatDays.isEmpty ? 'Weekly' : 'Weekly';
      case TaskRepeatType.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dueLabel = _dueDateLabel();
    final repeatLabel = _repeatLabel();

    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      onDismissed: (_) => onDismissed(),
      child: CheckboxListTile(
        value: task.completed,
        onChanged: (_) => onToggle(),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(
          task.title,
          style: TextStyle(
            decoration: task.completed ? TextDecoration.lineThrough : null,
            color: task.completed ? Colors.grey : null,
          ),
        ),
        subtitle: (dueLabel != null || repeatLabel != null)
            ? Row(
                children: [
                  if (dueLabel != null)
                    Text(
                      dueLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _isOverdue
                            ? theme.colorScheme.error
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: _isOverdue ? FontWeight.w600 : null,
                      ),
                    ),
                  if (dueLabel != null && repeatLabel != null)
                    Text(
                      '  ·  ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (repeatLabel != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.repeat, size: 12, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 2),
                        Text(
                          repeatLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              )
            : null,
        secondary: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (task.linkedAlarmId != null)
              const Padding(
                padding: EdgeInsets.only(right: 4),
                child: Icon(Icons.alarm, size: 20),
              ),
            if (onEdit != null)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: onEdit,
              ),
          ],
        ),
      ),
    );
  }
}