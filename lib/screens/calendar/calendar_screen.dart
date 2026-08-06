import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';
import '../../models/habits/habit.dart';
import '../../services/tasks/task_service.dart';
import '../../services/habits/habit_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tasks/day_agenda_tile.dart';

/// Month grid + day agenda view over BOTH tasks and habits. Repeating
/// tasks and habits are projected forward/backward as "virtual"
/// occurrences for display purposes only — this screen never writes a new
/// doc per occurrence, it just figures out which days a task/habit's
/// single persistent doc counts as "due" on and looks up (or writes, via
/// TaskService.setCompletionForDate / HabitService.cycleStatus) that
/// day's entry in the relevant log.
///
/// Day agenda is always Tasks first, then Habits below, per section
/// headers — never interleaved.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.taskService,
    required this.habitService,
  });

  final TaskService taskService;
  final HabitService habitService;

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
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

  // ---------------- Tasks ----------------

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
  ///
  /// Mirrors TaskService._syncsLiveCompleted: non-repeating tasks have no
  /// real "days," so once a one-off task is completed, `task.completed`
  /// applies to every day, not just the day it happened to be recorded on.
  bool? _statusOn(Task task, DateTime day) {
    final key = _key(day);
    if (task.completionLog.containsKey(key)) return task.completionLog[key];
    if (task.repeatType == TaskRepeatType.none) return task.completed;
    final effectiveActiveDate = task.dueDate?.toDate() ?? DateTime.now();
    if (_sameDay(effectiveActiveDate, day)) return task.completed;
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

  // ---------------- Habits ----------------

  /// Every day in the visible month this habit is expected on (per
  /// frequency/restDays), unioned with any log dates in this month (covers
  /// backdated entries that fall outside the current frequency, e.g.
  /// frequency changed after the fact).
  List<DateTime> _habitOccurrencesInMonth(Habit habit) {
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final createdDay =
        habit.createdAt != null ? _dayOnly(habit.createdAt!.toDate()) : null;

    final occurrences = <DateTime>{};

    for (int d = 1; d <= daysInMonth; d++) {
      final day = DateTime(year, month, d);
      if (createdDay != null && day.isBefore(createdDay)) continue;
      if (habit.isExpectedOn(day.weekday)) occurrences.add(day);
    }

    for (final key in habit.log.keys) {
      final parsed = _parseKey(key);
      if (parsed != null && parsed.year == year && parsed.month == month) {
        occurrences.add(parsed);
      }
    }

    return occurrences.toList();
  }

  HabitDayStatus? _habitStatusOn(Habit habit, DateTime day) =>
      habit.statusOn(_key(day));

  Color _habitStatusColor(HabitDayStatus? status) {
    switch (status) {
      case HabitDayStatus.done:
        return AppColors.success;
      case HabitDayStatus.skipped:
        return AppColors.skip;
      case HabitDayStatus.missed:
        return AppColors.error;
      case null:
        return AppColors.skip.withOpacity(0.3);
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
        builder: (context, taskSnapshot) {
          return StreamBuilder<List<Habit>>(
            stream: widget.habitService.watchHabits(),
            builder: (context, habitSnapshot) {
              if (taskSnapshot.connectionState == ConnectionState.waiting ||
                  habitSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final tasks = taskSnapshot.data ?? [];
              final habits = habitSnapshot.data ?? [];
              final now = DateTime.now();
              final today = DateTime(now.year, now.month, now.day);

              final Map<String, List<Task>> byDayTasks = {};
              for (final task in tasks) {
                for (final day in _occurrencesInMonth(task)) {
                  byDayTasks.putIfAbsent(_key(day), () => []).add(task);
                }
              }

              final Map<String, List<Habit>> byDayHabits = {};
              for (final habit in habits) {
                for (final day in _habitOccurrencesInMonth(habit)) {
                  byDayHabits.putIfAbsent(_key(day), () => []).add(habit);
                }
              }

              final selectedTasks =
                  List<Task>.from(byDayTasks[_key(_selectedDay)] ?? []);
              selectedTasks.sort((a, b) {
                final aDone = _statusOn(a, _selectedDay) ?? false;
                final bDone = _statusOn(b, _selectedDay) ?? false;
                if (aDone != bDone) return aDone ? 1 : -1;
                return b.priority.index.compareTo(a.priority.index);
              });

              final selectedHabits =
                  List<Habit>.from(byDayHabits[_key(_selectedDay)] ?? []);
              selectedHabits.sort((a, b) {
                final aDone =
                    _habitStatusOn(a, _selectedDay) == HabitDayStatus.done;
                final bDone =
                    _habitStatusOn(b, _selectedDay) == HabitDayStatus.done;
                if (aDone != bDone) return aDone ? 1 : -1;
                return a.name.compareTo(b.name);
              });

              final totalCount = selectedTasks.length + selectedHabits.length;

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
                    byDayTasks: byDayTasks,
                    byDayHabits: byDayHabits,
                    taskStatusOn: _statusOn,
                    habitStatusOn: _habitStatusOn,
                    priorityColor: (p) => _priorityColor(p, theme.colorScheme),
                    habitStatusColor: _habitStatusColor,
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
                          '$totalCount item${totalCount == 1 ? '' : 's'}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: totalCount == 0
                        ? Center(
                            child: Text(
                              'Nothing due this day.',
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                            ),
                          )
                        : ListView(
                            children: [
                              if (selectedTasks.isNotEmpty) ...[
                                _SectionHeader(
                                  label: 'Tasks',
                                  theme: theme,
                                ),
                                ...selectedTasks.map((task) {
                                  final done = _statusOn(task, _selectedDay) ?? false;
                                  final isFuture = _selectedDay.isAfter(today);
                                  return DayAgendaTile(
                                    task: task,
                                    day: _selectedDay,
                                    completed: done,
                                    onToggle: isFuture
                                        ? null
                                        : () => widget.taskService.setCompletionForDate(
                                              task,
                                              _selectedDay,
                                              !done,
                                            ),
                                  );
                                }),
                              ],
                              if (selectedHabits.isNotEmpty) ...[
                                _SectionHeader(
                                  label: 'Habits',
                                  theme: theme,
                                ),
                                ...selectedHabits.map((habit) {
                                  final status = _habitStatusOn(habit, _selectedDay);
                                  final isFuture = _selectedDay.isAfter(today);
                                  return _HabitAgendaTile(
                                    habit: habit,
                                    status: status,
                                    statusColor: _habitStatusColor(status),
                                    onTap: isFuture
                                        ? null
                                        : () => widget.habitService.cycleStatus(
                                              habit,
                                              _selectedDay,
                                            ),
                                  );
                                }),
                              ],
                            ],
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.theme});
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

class _HabitAgendaTile extends StatelessWidget {
  const _HabitAgendaTile({
    required this.habit,
    required this.status,
    required this.statusColor,
    required this.onTap,
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
          color: isFuture ? statusColor.withOpacity(0.3) : statusColor,
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

        // Combined indicator row: task dots (circles, priority color) get
        // first claim on the 3 available slots, habit dots (small squares,
        // status color) fill any remaining slots. This keeps the cell from
        // needing a second row, which doesn't fit the fixed circular cell.
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