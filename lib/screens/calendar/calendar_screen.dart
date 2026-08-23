import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';
import '../../models/habits/habit.dart';
import '../../models/tags/tag.dart';
import '../../services/tasks/task_service.dart';
import '../../services/habits/habit_service.dart';
import '../../services/tags/tag_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tasks/day_agenda_tile.dart';
import '../../widgets/calendar/month_grid.dart';
import '../../widgets/calendar/calendar_widgets.dart';

/// Month grid + day agenda view over BOTH tasks and habits.
/// Day agenda is always Tasks first, then Habits below, per section
/// headers — never interleaved.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({
    super.key,
    required this.taskService,
    required this.habitService,
    required this.tagService,
  });

  final TaskService taskService;
  final HabitService habitService;
  final TagService tagService;

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
  /// with any completionLog dates in this month — but ONLY for tasks that
  /// actually have a real schedule (a dueDate, or a repeat pattern). The
  /// completionLog union exists to support backdating: a repeating task
  /// marked done for a day outside its normal computed pattern should
  /// still surface on that day. It deliberately does NOT apply to
  /// untethered tasks (no dueDate, repeatType.none) — those aren't due on
  /// any particular day in the first place, so completing one shouldn't
  /// pin it to whatever day happened to be "today" when it was checked
  /// off (which is what TaskService.toggleComplete logs against for
  /// tasks with no real dueDate). Without this guard, any no-due-date
  /// task would appear glued to its completion day on the calendar the
  /// moment you checked it off, which reads as "this was due today" even
  /// though it was never scheduled at all.
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

    // Untethered tasks (no dueDate, not repeating) have no real "day" to
    // be pinned to — skip the completionLog union for them entirely so
    // they never appear on the calendar at all, regardless of when they
    // were checked off.
    final isUntethered =
        task.repeatType == TaskRepeatType.none && task.dueDate == null;
    if (!isUntethered) {
      for (final key in task.completionLog.keys) {
        final parsed = _parseKey(key);
        if (parsed != null && parsed.year == year && parsed.month == month) {
          occurrences.add(parsed);
        }
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
        return AppColors.skip.withValues(alpha: 0.3);
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
      body: StreamBuilder<List<Tag>>(
        stream: widget.tagService.watchTags(),
        builder: (context, tagSnapshot) {
          final tags = tagSnapshot.data ?? [];
          final tagsById = {for (final t in tags) t.id: t};

          return StreamBuilder<List<Task>>(
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

              final totalCount =
                  selectedTasks.length + selectedHabits.length;

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
                  WeekdayHeader(theme: theme),
                  MonthGrid(
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
                                SectionHeader(
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
                                    tag: task.tagId == null
                                        ? null
                                        : tagsById[task.tagId],
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
                                SectionHeader(
                                  label: 'Habits',
                                  theme: theme,
                                ),
                                ...selectedHabits.map((habit) {
                                  final status = _habitStatusOn(habit, _selectedDay);
                                  final isFuture = _selectedDay.isAfter(today);
                                  return HabitAgendaTile(
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
          );
        },
      ),
    );
  }
}
