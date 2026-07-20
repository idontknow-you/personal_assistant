import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../main.dart';
import '../../models/alarms/alarm.dart';
import '../../services/tasks/task_service.dart';
import 'alarm_form_screen.dart';
import '../../services/alarms/alarm_service.dart';

class AlarmListScreen extends StatelessWidget {
  final AlarmService alarmService;
  const AlarmListScreen({super.key, required this.alarmService});
  
  static const _weekdayLabels = {
    1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu',
    5: 'Fri', 6: 'Sat', 7: 'Sun',
  };

  String _formatTime(int hour, int minute) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    final displayMinute = minute.toString().padLeft(2, '0');
    return '$displayHour:$displayMinute $period';
  }

  String _formatSubtitle(AlarmModel alarm) {
    if (alarm.type == AlarmType.oneTime) {
      final date = alarm.oneTimeDate!;
      return 'One-time · ${date.day}/${date.month}/${date.year}';
    }
    if (alarm.repeatDays.isEmpty) return 'Repeating · no days set';
    final sortedDays = alarm.repeatDays.toList()..sort();
    return sortedDays.map((d) => _weekdayLabels[d]).join(' ');
  }

  /// Returns a TaskService for the current user, or null if somehow no
  /// user is signed in yet (shouldn't happen once anonymous auth has run,
  /// but this screen shouldn't crash if it does).
  TaskService? _currentTaskService() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return TaskService(uid);
  }

  Future<void> _confirmDelete(BuildContext context, AlarmModel alarm) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete alarm?'),
        content: Text(
          alarm.label.isEmpty
              ? 'This alarm will be permanently deleted.'
              : '"${alarm.label}" will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await alarmService.deleteAlarm(alarm.id);

      // If this alarm was created from a task's "reminder" toggle, clear
      // the back-reference so the task stops showing a bell icon for an
      // alarm that no longer exists.
      if (alarm.linkedTaskId != null) {
        final taskService = _currentTaskService();
        if (taskService != null) {
          await taskService.clearLinkedAlarm(alarm.linkedTaskId!);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Alarms')),
      body: StreamBuilder<List<AlarmModel>>(
        stream: alarmService.watchAlarms(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Something went wrong: ${snapshot.error}'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final alarms = snapshot.data!
            ..sort((a, b) {
              final aMinutes = a.hour * 60 + a.minute;
              final bMinutes = b.hour * 60 + b.minute;
              return aMinutes.compareTo(bMinutes);
            });

          if (alarms.isEmpty) {
            return Center(
              child: Text(
                'No alarms yet — tap + to add one',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: alarms.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final alarm = alarms[index];
              return Dismissible(
                key: ValueKey(alarm.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(
                    Icons.delete_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                confirmDismiss: (_) async {
                  await _confirmDelete(context, alarm);
                  return false; // we handle deletion ourselves via the stream
                },
                child: ListTile(
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => AlarmFormScreen(
                        alarmService: alarmService,
                        existingAlarm: alarm,
                        taskService: _currentTaskService(),
                      ),
                    ));
                  },
                  title: Row(
                    children: [
                      Text(
                        _formatTime(alarm.hour, alarm.minute),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (alarm.linkedTaskId != null) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.link,
                          size: 18,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    alarm.label.isEmpty
                        ? _formatSubtitle(alarm)
                        : '${alarm.label} · ${_formatSubtitle(alarm)}',
                  ),
                  trailing: Switch(
                    value: alarm.isEnabled,
                    onChanged: (value) => alarmService.setEnabled(alarm, value),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => AlarmFormScreen(
              alarmService: alarmService,
              taskService: _currentTaskService(),
            ),
          ));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}