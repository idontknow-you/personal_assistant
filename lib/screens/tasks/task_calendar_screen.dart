import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';
import '../../services/tasks/task_service.dart';
import '../../widgets/tasks/day_agenda_tile.dart';

/// Month grid + day agenda view over tasks. Repeating tasks are projected
/// forward/backward as "virtual" occurrences for display purposes only —
/// this screen never writes a new Task doc per occurrence, it just figures
/// out which days a task's single persistent doc counts as "due" on and
/// looks up (or writes, via TaskService.setCompletionForDate) that day's
/// entry in Task.completionLog.
class TaskCalendarScreen extends StatefulWidget {
  const TaskCalendarScreen({super.key, required this.taskService});

  final TaskService taskService;

  @override
  State<TaskCalendarScreen> createState() => _TaskCalendarScreenState();
}

class _TaskCalendarScreenState extends State<TaskCalendarScreen> {
  late DateTime _visibleMonth; // first-of-month, no time component
  late DateTime _selectedDay;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _key(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  DateTime? _parseKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  void _goToMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() {
      _visibleMonth = DateTime(now.year, now.month, 1);
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  /// Every day in the visible month this task counts as "due" on, unioned
  /// with any completionLog dates in this month (covers backdated entries
  /// that fall outside the computed recurrence, e.g. repeatDays changed
  /// after the fact).
  List<DateTime> _occurrencesInMonth(Task task) {
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final createdDay =
        task.createdAt != null ? _dayOnly(task.createdAt!.toDate()) : null;

    final occurrences = <DateTime>{};

    switch (task.repeatType) {
      case TaskRepeatType.daily:
        for (int d = 1; d <= daysInMonth; d++) {
          final day = DateTime(year, month, d);
          if (createdDay != null && day.isBefore(createdDay)) continue;
          occurrences.add(day);
        }
        break;
      case TaskRepeatType.weekly:
        for (int d = 1; d <= daysInMonth; d++) {
          final day = DateTime(year, month, d);
          if (createdDay != null && day.isBefore(createdDay)) continue;
          if (task.repeatDays.contains(day.weekday)) occurrences.add(day);
        }
        break;
      case TaskRepeatType.none:
        if (task.dueDate != null) {
          final due = _dayOnly(task.dueDate!.toDate());
          if (due.year == year && due.month == month) occurrences.add(due);
        }
        break;
    }

    for (final key in task.completionLog.keys) {
      final parsed = _parseKey(key);
      if (parsed != null && parsed.year == year && parsed.month == month) {
        occurrences.add(parsed);
      }
    }

    return occurrences.toList();
  }

  /// Completion status for [task] on [day]: true/false if there's a record,
  /// null if unknown (a future day, or a day never toggled/backdated).
  bool? _statusOn(Task task, DateTime day) {
    final key = _key(day);
    if (task.completionLog.containsKey(key)) return task.completionLog[key];
    final isActivePeriod =
        task.dueDate != null && _sameDay(task.dueDate!.toDate(), day);
    if (isActivePeriod) return task.completed;
    return null;
  }

  Color _priorityColor(Priority p, ColorScheme scheme) {
    switch (p) {
      case Priority.high:
        return scheme.error;
      case Priority.medium:
        return scheme.tertiary;
      case Priority.low:
        return scheme.secondary;
    }
  }

  String _monthLabel(DateTime month) => '${_monthNames[month.month - 1]} ${month.year}';

  String _agendaLabel(DateTime day) {
    final now = DateTime.now();
    if (_sameDay(day, DateTime(now.year, now.month, now.day))) return 'Today';
    return '${_monthNames[day.month - 1]} ${day.day}, ${day.year}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar'),
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            tooltip: 'Jump to today',
            onPressed: _goToToday,
          ),
        ],
      ),
      body: StreamBuilder<List<Task>>(
        stream: widget.taskService.watchTasks(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final tasks = snapshot.data ?? [];

          final Map<String, List<Task>> byDay = {};
          for (final task in tasks) {
            for (final day in _occurrencesInMonth(task)) {
              byDay.putIfAbsent(_key(day), () => []).add(task);
            }
          }

          final selectedTasks = List<Task>.from(byDay[_key(_selectedDay)] ?? []);
          selectedTasks.sort((a, b) {
            final aDone = _statusOn(a, _selectedDay) ?? false;
            final bDone = _statusOn(b, _selectedDay) ?? false;
            if (aDone != bDone) return aDone ? 1 : -1;
            return b.priority.index.compareTo(a.priority.index);
          });

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => _goToMonth(-1),
                    ),
                    Text(_monthLabel(_visibleMonth), style: theme.textTheme.titleMedium),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => _goToMonth(1),
                    ),
                  ],
                ),
              ),
              _WeekdayHeader(theme: theme),
              _MonthGrid(
                visibleMonth: _visibleMonth,
                selectedDay: _selectedDay,
                byDay: byDay,
                statusOn: _statusOn,
                priorityColor: (p) => _priorityColor(p, theme.colorScheme),
                onSelectDay: (day) => setState(() => _selectedDay = day),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text(_agendaLabel(_selectedDay), style: theme.textTheme.titleSmall),
                    const Spacer(),
                    Text(
                      '${selectedTasks.length} task${selectedTasks.length == 1 ? '' : 's'}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: selectedTasks.isEmpty
                    ? Center(
                        child: Text(
                          'Nothing due this day.',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.builder(
                        itemCount: selectedTasks.length,
                        itemBuilder: (context, index) {
                          final task = selectedTasks[index];
                          final done = _statusOn(task, _selectedDay) ?? false;
                          return DayAgendaTile(
                            task: task,
                            day: _selectedDay,
                            completed: done,
                            onToggle: () => widget.taskService.setCompletionForDate(
                              task,
                              _selectedDay,
                              !done,
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.theme});
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

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.visibleMonth,
    required this.selectedDay,
    required this.byDay,
    required this.statusOn,
    required this.priorityColor,
    required this.onSelectDay,
  });

  final DateTime visibleMonth;
  final DateTime selectedDay;
  final Map<String, List<Task>> byDay;
  final bool? Function(Task, DateTime) statusOn;
  final Color Function(Priority) priorityColor;
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
    // firstOfMonth.weekday: 1=Mon..7=Sun. Grid starts on Monday.
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
        final tasksToday = byDay[_key(day)] ?? [];
        final isToday = day.year == today.year &&
            day.month == today.month &&
            day.day == today.day;
        final isSelected = day.year == selectedDay.year &&
            day.month == selectedDay.month &&
            day.day == selectedDay.day;
        final isPast = day.isBefore(today);

        final allDone = tasksToday.isNotEmpty &&
            tasksToday.every((t) => statusOn(t, day) ?? false);
        final hasMissed = isPast &&
            tasksToday.isNotEmpty &&
            tasksToday.any((t) => !(statusOn(t, day) ?? false));

        Color? bg;
        if (isSelected) {
          bg = theme.colorScheme.primary;
        } else if (allDone) {
          bg = theme.colorScheme.primaryContainer;
        } else if (hasMissed) {
          bg = theme.colorScheme.errorContainer.withValues(alpha: 0.5);
        }

        final textColor =
            isSelected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

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
                if (tasksToday.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: tasksToday.take(3).map((t) {
                        return Container(
                          width: 4,
                          height: 4,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? theme.colorScheme.onPrimary
                                : priorityColor(t.priority),
                            shape: BoxShape.circle,
                          ),
                        );
                      }).toList(),
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