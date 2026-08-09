import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';
import '../../models/tags/tag.dart';

/// A single task's row in the calendar's day agenda. Unlike TaskTile, this
/// is scoped to one specific [day] rather than the task's live [completed]
/// field — its checkbox reflects [completed] as passed in by the caller
/// (looked up from [Task.completionLog] for that day), and toggling it
/// should go through TaskService.setCompletionForDate rather than
/// toggleComplete, since the day shown here may not be the task's current
/// active period.
///
/// [onToggle] is nullable — pass null for days in the future, since you
/// can't mark something done that hasn't happened yet. When null, the
/// checkbox renders disabled rather than silently doing nothing on tap.
class DayAgendaTile extends StatelessWidget {
  const DayAgendaTile({
    super.key,
    required this.task,
    required this.day,
    required this.completed,
    required this.onToggle,
    this.tag,
  });

  final Task task;
  final DateTime day;
  final bool completed;
  final VoidCallback? onToggle;

  /// The resolved Tag for task.tagId, if any — resolved by the caller
  /// (CalendarScreen) from TagService.watchTags(), same as TaskTile.tag.
  final Tag? tag;

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
    final isFuture = onToggle == null;

    final subtitleParts = <String>[
      if (isFuture) 'Not due yet',
      if (repeatLabel != null) repeatLabel,
    ];

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
          onChanged: onToggle == null ? null : (_) => onToggle!(),
        ),
        title: Text(
          task.title,
          style: theme.textTheme.bodyLarge?.copyWith(
            decoration: completed ? TextDecoration.lineThrough : null,
            color: completed
                ? theme.colorScheme.onSurfaceVariant
                : (isFuture ? theme.colorScheme.onSurfaceVariant : null),
          ),
        ),
        subtitle: (subtitleParts.isNotEmpty || tag != null)
            ? Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    if (tag != null) ...[
                      if (subtitleParts.isNotEmpty) const SizedBox(width: 8),
                      _TagChip(tag: tag!),
                    ],
                  ],
                ),
              )
            : null,
      ),
    );
  }
}

/// Small pill showing a tag's name, colored with the active theme's
/// primary color (tags no longer carry their own color — see Tag model).
/// See TaskTile's identical private copy for why this isn't shared/extracted.
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