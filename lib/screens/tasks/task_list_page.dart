import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';
import '../../services/tasks/task_service.dart';
import '../../services/alarms/alarm_service.dart';
import '../../services/habits/habit_service.dart';
import '../../widgets/tasks/task_tile.dart';
import '../../widgets/tasks/completion_history_sheet.dart';
import '../settings/settings_screen.dart';
import 'task_form_screen.dart';
import 'task_stats_screen.dart';
import '../calendar/calendar_screen.dart';

enum TaskFilter { all, today, overdue, completed }

class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key, required this.uid, required this.alarmService});

  final String uid;
  final AlarmService alarmService;

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  late final TaskService _taskService;
  late final HabitService _habitService;
  TaskFilter _filter = TaskFilter.all;

  @override
  void initState() {
    super.initState();
    _taskService = TaskService(widget.uid, alarmService: widget.alarmService);
    _habitService = HabitService(widget.uid);
    _taskService.runDailyRollover();
  }

  void _showAddTaskSheet() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'New task title',
                  ),
                  onSubmitted: (value) {
                    _taskService.addTask(value);
                    Navigator.pop(context);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () {
                  _taskService.addTask(controller.text);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _openTaskForm({Task? existingTask}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskFormScreen(
          taskService: _taskService,
          alarmService: widget.alarmService,
          existingTask: existingTask,
        ),
      ),
    );
  }

  void _openStats() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskStatsScreen(taskService: _taskService),
      ),
    );
  }

  void _openCalendar() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CalendarScreen(
          taskService: _taskService,
          habitService: _habitService,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsScreen(),
      ),
    );
  }

  bool _isToday(Task t) {
    if (t.dueDate == null) return false;
    final due = t.dueDate!.toDate();
    final now = DateTime.now();
    return due.year == now.year && due.month == now.month && due.day == now.day;
  }

  bool _isOverdue(Task t) {
    if (t.completed || t.dueDate == null) return false;
    final due = t.dueDate!.toDate();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    return due.isBefore(todayStart);
  }

  List<Task> _applyFilter(List<Task> tasks) {
    switch (_filter) {
      case TaskFilter.today:
        return tasks.where((t) => _isToday(t) && !t.completed).toList();
      case TaskFilter.overdue:
        return tasks.where(_isOverdue).toList();
      case TaskFilter.completed:
        return tasks.where((t) => t.completed).toList();
      case TaskFilter.all:
        final pending = tasks.where((t) => !t.completed).toList();
        final done = tasks.where((t) => t.completed).toList();
        return [...pending, ...done];
    }
  }

  String _filterLabel(TaskFilter f) {
    switch (f) {
      case TaskFilter.all:
        return 'All';
      case TaskFilter.today:
        return 'Today';
      case TaskFilter.overdue:
        return 'Overdue';
      case TaskFilter.completed:
        return 'Completed';
    }
  }

  void _showStreakDetails(BuildContext context, int current, int best) {
    showDialog(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_fire_department, size: 32),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$current day${current == 1 ? '' : 's'}',
                          style: theme.textTheme.headlineSmall,
                        ),
                        Text(
                          'current streak',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Best: $best day${best == 1 ? '' : 's'}',
                  style: theme.textTheme.bodyMedium,
                ),
                const Divider(height: 32),
                Text(
                  'How this works',
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  'Your streak counts consecutive days where every task due '
                  'that day was completed. Missing even one task due on a '
                  'given day resets it to 0. You can backdate a missed day '
                  'from a task\'s history icon and it\'ll still count. Tasks '
                  'with no due date set don\'t count toward this.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tasks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            tooltip: 'Calendar',
            onPressed: _openCalendar,
          ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: 'Stats',
            onPressed: _openStats,
          ),
          StreamBuilder<Map<String, dynamic>>(
            stream: _taskService.watchStreak(),
            builder: (context, snapshot) {
              final data = snapshot.data;
              final current = data?['currentStreak'] as int? ?? 0;
              final best = data?['bestStreak'] as int? ?? 0;
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _showStreakDetails(context, current, best),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.local_fire_department, size: 20),
                      const SizedBox(width: 4),
                      Text('$current', style: Theme.of(context).textTheme.titleMedium),
                      if (best > 0) ...[
                        const SizedBox(width: 4),
                        Text('(best $best)', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: TaskFilter.values.map((f) {
                  final selected = _filter == f;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_filterLabel(f)),
                      selected: selected,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Task>>(
              stream: _taskService.watchTasks(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final allTasks = snapshot.data ?? [];
                final tasks = _applyFilter(allTasks);

                if (allTasks.isEmpty) {
                  return const Center(
                    child: Text('No tasks yet. Tap + to add one.'),
                  );
                }
                if (tasks.isEmpty) {
                  return Center(
                    child: Text('No ${_filterLabel(_filter).toLowerCase()} tasks.'),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 96,
                  ),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    final task = tasks[index];
                    return TaskTile(
                      task: task,
                      onToggle: () => _taskService.toggleComplete(task),
                      onDismissed: () => _taskService.deleteTask(task),
                      onEdit: () => _openTaskForm(existingTask: task),
                      onSubtaskToggle: (subtaskId, isCompleted) =>
                          _taskService.toggleSubtask(task.id, subtaskId, isCompleted),
                      onShowHistory: () => CompletionHistorySheet.show(
                        context,
                        task: task,
                        taskService: _taskService,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTaskForm(),
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
    );
  }
}