import 'package:flutter/material.dart';
import '../../main.dart';
import '../../models/alarms/alarm.dart';
import 'alarm_form_screen.dart';

class AlarmListScreen extends StatelessWidget {
  const AlarmListScreen({super.key});

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
                      ),
                    ));
                  },
                  title: Text(
                    _formatTime(alarm.hour, alarm.minute),
                    style: Theme.of(context).textTheme.headlineSmall,
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
            builder: (_) => AlarmFormScreen(alarmService: alarmService),
          ));
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}