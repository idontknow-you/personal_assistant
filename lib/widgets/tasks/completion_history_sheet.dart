import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';
import '../../services/tasks/task_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';

/// Bottom sheet showing the last 14 days for a task, each day tappable to
/// mark done/undone for that specific date — this is the actual fix for
/// "can't mark done for a previous day." Uses local optimistic state so
/// taps feel instant; writes go to TaskService.setCompletionForDate in the
/// background without blocking the UI.
class CompletionHistorySheet extends StatefulWidget {
  const CompletionHistorySheet({
    super.key,
    required this.task,
    required this.taskService,
  });

  final Task task;
  final TaskService taskService;

  static Future<void> show(
    BuildContext context, {
    required Task task,
    required TaskService taskService,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CompletionHistorySheet(task: task, taskService: taskService),
    );
  }

  @override
  State<CompletionHistorySheet> createState() => _CompletionHistorySheetState();
}

class _CompletionHistorySheetState extends State<CompletionHistorySheet> {
  late Map<String, bool> _log;

  @override
  void initState() {
    super.initState();
    _log = {...widget.task.completionLog};
  }

  bool _valueFor(DateTime day, String key) {
    if (_log.containsKey(key)) return _log[key]!;
    // No log entry yet: if this day is the task's current active period,
    // fall back to the live `completed` field so it matches the tile.
    final due = widget.task.dueDate?.toDate();
    if (due != null && isSameDay(due, day)) return widget.task.completed;
    return false;
  }

  void _toggle(DateTime day) {
    final key = dateKey(day);
    final newValue = !_valueFor(day, key);
    setState(() => _log[key] = newValue);
    widget.taskService.setCompletionForDate(widget.task, day, newValue);
  }

  String _label(DateTime day, DateTime today) {
    final diff = startOfDay(today).difference(startOfDay(day)).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${day.day}/${day.month}/${day.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateTime.now();
    final days = List.generate(
      14,
      (i) => startOfDay(today.subtract(Duration(days: i))),
    );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.task.title, style: theme.textTheme.titleMedium),
            Text(
              'Tap a day to mark it done or undone',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: days.length,
                itemBuilder: (context, index) {
                  final day = days[index];
                  final key = dateKey(day);
                  final done = _valueFor(day, key);
                  return CheckboxListTile(
                    value: done,
                    onChanged: (_) => _toggle(day),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(_label(day, today)),
                    activeColor: AppColors.success,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}