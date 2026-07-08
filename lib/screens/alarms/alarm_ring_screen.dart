import 'package:flutter/material.dart';
import 'package:alarm/alarm.dart' as alarm_pkg;
import '../../models/alarms/alarm.dart' as models;
import '../../services/alarms/alarm_service.dart';

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
    final onPrimary = theme.colorScheme.onPrimary;
    final primary = theme.colorScheme.primary;

    return PopScope(
      canPop: false, // force Stop/Snooze — no dismissing via back button
      child: Scaffold(
        backgroundColor: primary,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Icon in a soft circular container instead of floating bare
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: onPrimary.withValues(alpha: 0.15),
                  ),
                  child: Icon(Icons.alarm, size: 72, color: onPrimary),
                ),
                const SizedBox(height: 32),
                Text(
                  title.isEmpty ? 'Alarm' : title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 64),

                // Snooze — solid, high-contrast pill so it reads as tappable
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: onPrimary,
                      foregroundColor: primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () => _snooze(context, const Duration(minutes: 5)),
                    child: const Text('Snooze 5 min'),
                  ),
                ),
                const SizedBox(height: 16),

                // Stop — outlined with explicit onPrimary border + text so
                // it's actually visible against the primary-colored bg
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: onPrimary,
                      side: BorderSide(color: onPrimary, width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () => _stop(context),
                    child: const Text('Stop'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}