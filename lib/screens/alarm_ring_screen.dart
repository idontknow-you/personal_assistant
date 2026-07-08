import 'package:flutter/material.dart';
import 'package:alarm/alarm.dart' as alarm_pkg;
import '../models/alarm.dart' as models;
import '../services/alarm_service.dart';

class AlarmRingScreen extends StatelessWidget {
  const AlarmRingScreen({
    super.key,
    required this.ringingSettings,
    required this.alarmService,
  });

  final alarm_pkg.AlarmSettings ringingSettings;
  final AlarmService alarmService;

  Future<void> _stop(BuildContext context) async {
    await alarm_pkg.Alarm.stop(ringingSettings.id);

    final alarm = await alarmService.getAlarm(ringingSettings.id);
    if (alarm != null) {
      // One-time alarms have no "next" occurrence — disable instead
      // of rescheduling. Repeating ones get queued for their next day.
      if (alarm.type == models.AlarmType.oneTime) {
        await alarmService.setEnabled(alarm, false);
      } else {
        await alarmService.rescheduleAfterRing(alarm);
      }
    }

    if (context.mounted) Navigator.of(context).pop();
  }

  Future<void> _snooze(BuildContext context, Duration duration) async {
    await alarm_pkg.Alarm.set(
      alarmSettings: ringingSettings.copyWith(
        dateTime: DateTime.now().add(duration),
      ),
    );
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = ringingSettings.notificationSettings.title;
    final theme = Theme.of(context);

    return PopScope(
      canPop: false, // force Stop/Snooze — no dismissing via back button
      child: Scaffold(
        backgroundColor: theme.colorScheme.primary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.alarm, size: 96, color: theme.colorScheme.onPrimary),
                const SizedBox(height: 24),
                Text(
                  title.isEmpty ? 'Alarm' : title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
                const SizedBox(height: 48),
                FilledButton(
                  onPressed: () => _snooze(context, const Duration(minutes: 5)),
                  child: const Text('Snooze 5 min'),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () => _stop(context),
                  child: const Text('Stop'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}