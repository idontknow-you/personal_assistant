import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/tasks/task.dart';
import '../../models/notes/future_letter.dart';
import '../../services/tasks/task_service.dart';
import '../../services/profile_service.dart';
import '../../services/notes/note_service.dart';
import '../../services/notes/future_letter_service.dart';
import '../../services/alarms/alarm_service.dart';
import '../../services/api/api_service.dart';
import '../../utils/date_utils.dart' as my_date_utils;

/// A morning-overview dashboard: greeting, today's tasks, streak, due letters.
class TodayScreen extends StatefulWidget {
  final String uid;
  final AlarmService alarmService;
  final VoidCallback? onMenuPressed;

  const TodayScreen({
    super.key,
    required this.uid,
    required this.alarmService,
    this.onMenuPressed,
  });

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late final ProfileService _profileService;
  late final TaskService _taskService;
  late final FutureLetterService _letterService;
  late final NoteService _noteService;
  String? _weeklyReview;
  bool _reviewLoading = false;
  bool _reviewExpanded = false;

  @override
  void initState() {
    super.initState();
    _profileService = ProfileService(widget.uid);
    _taskService = TaskService(widget.uid, alarmService: widget.alarmService);
    _letterService = FutureLetterService(widget.uid);
    _noteService = NoteService(widget.uid);
  }

  Future<void> _loadWeeklyReview() async {
    if (_reviewLoading || _weeklyReview != null) return;
    setState(() => _reviewLoading = true);

    try {
      // Gather data for review
      final tasksSnap = await _taskService.watchTasks().first;
      final notesSnap = await _noteService.watchNotes().first;
      final streakSnap = await _taskService.watchStreak().first;

      final tasksData = tasksSnap.map((t) => {
        'title': t.title,
        'completed': t.completed,
        'dueDate': t.dueDate?.toDate().toIso8601String() ?? '',
      }).toList();

      final notesData = notesSnap.map((n) => {
        'title': n.title,
        'mood': n.mood?.name ?? '',
        'content': n.content.length > 100 ? n.content.substring(0, 100) : n.content,
        'date': n.createdAt?.toDate().toIso8601String() ?? '',
      }).toList();

      final streak = streakSnap['currentStreak'] as int? ?? 0;

      final review = await ApiService.getWeeklyReview(
        tasks: tasksData,
        habits: [],
        notes: notesData,
        streak: streak,
      );

      if (mounted) {
        setState(() {
          _weeklyReview = review ?? 'Could not generate review.';
          _reviewLoading = false;
          _reviewExpanded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _weeklyReview = 'Review unavailable: $e';
          _reviewLoading = false;
        });
      }
    }
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

  Widget _buildWeeklyReviewCard() {
    final cs = Theme.of(context).colorScheme;

    // Loading state
    if (_reviewLoading) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Generating your weekly review...',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // No review yet — show a prompt to load
    if (_weeklyReview == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Card(
          child: ListTile(
            leading: Icon(Icons.auto_awesome, color: cs.primary),
            title: const Text('Weekly Review'),
            subtitle: const Text('Get an AI summary of your week'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _loadWeeklyReview,
          ),
        ),
      );
    }

    // Review loaded
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: ExpansionTile(
          leading: Icon(Icons.auto_awesome, color: cs.primary),
          title: const Text('Weekly Review'),
          initiallyExpanded: _reviewExpanded,
          onExpansionChanged: (expanded) {
            setState(() => _reviewExpanded = expanded);
          },
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                _weeklyReview!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateStr = DateFormat.EEEE().format(now); // "Monday"
    final fullDate = DateFormat.yMMMMd().format(now); // "August 22, 2026"

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu),
          tooltip: 'Menu',
          onPressed: widget.onMenuPressed,
        ),
      ),
      body: CustomScrollView(
        slivers: [
          // Greeting header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    dateStr,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 4),
                  StreamBuilder<String>(
                    stream: _profileService.watchName(),
                    builder: (context, snapshot) {
                      final name = snapshot.data ?? '';
                      final greeting = name.isNotEmpty
                          ? my_date_utils.greetingForName(name)
                          : 'Hello';
                      return Text(
                        greeting,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      );
                    },
                  ),
                  const SizedBox(height: 2),
                  Text(
                    fullDate,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),

          // Today's tasks + streak
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: StreamBuilder<List<Task>>(
                stream: _taskService.watchTasks(),
                builder: (context, taskSnapshot) {
                  final allTasks = taskSnapshot.data ?? [];
                  final todayTasks = allTasks.where(_isToday).toList();
                  final overdueTasks = allTasks.where(_isOverdue).toList();
                  final pendingToday =
                      todayTasks.where((t) => !t.completed).toList();
                  final completedToday =
                      todayTasks.where((t) => t.completed).toList();

                  return StreamBuilder<Map<String, dynamic>>(
                    stream: _taskService.watchStreak(),
                    builder: (context, streakSnapshot) {
                      final streak =
                          streakSnapshot.data?['currentStreak'] as int? ?? 0;

                      return Row(
                        children: [
                          Expanded(
                            child: _StatCard(
                              icon: Icons.today,
                              label: 'Due today',
                              value: '${pendingToday.length}',
                              subtitle: completedToday.isNotEmpty
                                  ? '${completedToday.length} done'
                                  : null,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              icon: Icons.warning_amber,
                              label: 'Overdue',
                              value: '${overdueTasks.length}',
                              color: overdueTasks.isNotEmpty
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _StatCard(
                              icon: Icons.local_fire_department,
                              label: 'Streak',
                              value: '$streak',
                              subtitle: streak > 0 ? 'days' : null,
                              color: streak > 0
                                  ? const Color(0xFFFF6D00)
                                  : Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
          ),

          // Due letters banner
          SliverToBoxAdapter(
            child: FutureBuilder<List<FutureLetter>>(
              future: _letterService.getDueLetters(),
              builder: (context, snapshot) {
                final dueLetters = snapshot.data ?? [];
                if (dueLetters.isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.mail,
                              color: Theme.of(context).colorScheme.primary,
                              size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${dueLetters.length} letter${dueLetters.length == 1 ? '' : 's'} from your past self',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Open them to see what you wrote.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right,
                              color: Theme.of(context).colorScheme.primary),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Weekly review card
          SliverToBoxAdapter(
            child: _buildWeeklyReviewCard(),
          ),

          // Today's task list
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                'Today\'s Tasks',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ),
          StreamBuilder<List<Task>>(
            stream: _taskService.watchTasks(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                );
              }

              final allTasks = snapshot.data ?? [];
              final pendingToday = allTasks
                  .where((t) => _isToday(t) && !t.completed)
                  .toList();
              final overdueTasks = allTasks.where(_isOverdue).toList();
              final todayTasks = [...overdueTasks, ...pendingToday];

              if (todayTasks.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 32),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 48,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            'Nothing due today!',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Tap + to add a task.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final task = todayTasks[index];
                    final isOverdue = overdueTasks.contains(task);
                    return CheckboxListTile(
                      value: task.completed,
                      onChanged: (_) => _taskService.toggleComplete(task),
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(
                        task.title,
                        style: TextStyle(
                          decoration: task.completed
                              ? TextDecoration.lineThrough
                              : null,
                          color: task.completed
                              ? Colors.grey
                              : null,
                        ),
                      ),
                      subtitle: (isOverdue)
                          ? Text(
                              'Overdue',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.error,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          : null,
                    );
                  },
                  childCount: todayTasks.length,
                ),
              );
            },
          ),

          // Bottom padding
          const SliverToBoxAdapter(
            child: SizedBox(height: 100),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
