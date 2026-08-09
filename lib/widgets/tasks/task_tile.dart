import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';
import '../../models/tags/tag.dart';
import '../../theme/app_theme.dart';

class TaskTile extends StatelessWidget {
  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    required this.onDismissed,
    this.onEdit,
    this.onSubtaskToggle,
    this.onShowHistory,
    this.tag,
  });

  final Task task;
  final VoidCallback onToggle;
  final VoidCallback onDismissed;
  final VoidCallback? onEdit;
  final void Function(String subtaskId, bool isCompleted)? onSubtaskToggle;

  /// Opens the completion-history sheet (backdating). Parent owns
  /// TaskService, so this stays a plain callback like the others.
  final VoidCallback? onShowHistory;

  /// The resolved Tag for task.tagId, if any — TaskTile has no way to
  /// look this up itself (Task only stores the id), so the caller
  /// resolves it from TagService.watchTags() and passes it in. Null if
  /// the task has no tag, or its tag was deleted and not yet unassigned.
  final Tag? tag;

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
    final priorityColor = AppColors.priorityColor(task.priority.name);

    return Dismissible(
      key: Key(task.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.redAccent,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        onDismissed();
        return false;
      },
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: priorityColor, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CheckboxListTile(
              value: task.completed,
              onChanged: (_) => onToggle(),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                task.title,
                style: TextStyle(
                  decoration:
                      task.completed ? TextDecoration.lineThrough : null,
                  color: task.completed ? Colors.grey : null,
                ),
              ),
              subtitle: (dueLabel != null || repeatLabel != null || tag != null)
                  ? Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
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
                              Icon(Icons.repeat,
                                  size: 12,
                                  color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 2),
                              Text(
                                repeatLabel,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        if (tag != null) ...[
                          if (dueLabel != null || repeatLabel != null)
                            const SizedBox(width: 8),
                          _TagChip(tag: tag!),
                        ],
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
                  if (onShowHistory != null)
                    IconButton(
                      icon: const Icon(Icons.event_note, size: 20),
                      tooltip: 'History',
                      onPressed: onShowHistory,
                    ),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20),
                      onPressed: onEdit,
                    ),
                ],
              ),
            ),
            if (task.subtasks.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 32, right: 16, bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: task.subtasks.map((sub) {
                    return Row(
                      children: [
                        SizedBox(
                          height: 32,
                          width: 32,
                          child: Checkbox(
                            value: sub.isCompleted,
                            onChanged: onSubtaskToggle == null
                                ? null
                                : (val) =>
                                    onSubtaskToggle!(sub.id, val ?? false),
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            sub.title,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              decoration: sub.isCompleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Small pill showing a tag's name, colored with the active theme's
/// primary color (tags no longer carry their own color — see Tag model).
/// Kept private to this file since DayAgendaTile defines an identical one
/// independently rather than sharing — both are trivial enough that a
/// shared widgets/tags/ file felt like more indirection than it's worth
/// for a single Container.
class _TagChip extends StatelessWidget {
  const _TagChip({required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final tagColor = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tagColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        tag.name,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: tagColor,
        ),
      ),
    );
  }
}