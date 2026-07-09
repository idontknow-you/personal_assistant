import 'package:flutter/material.dart';
import 'package:alarm/alarm.dart' as alarm_pkg;
import '../../models/alarms/alarm.dart' as models;
import '../../services/alarms/alarm_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class AlarmRingScreen extends StatefulWidget {
  const AlarmRingScreen({
    super.key,
    required this.ringingSettings,
    required this.alarmService,
  });

  final alarm_pkg.AlarmSettings ringingSettings;
  final AlarmService alarmService;

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen>
    with WidgetsBindingObserver {
  bool _handled = false; // guards against double pop / double cleanup

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Covers the lock-screen case: user hit Stop from the native
    // notification while locked, sound stopped there, then they
    // unlock and land back on this (now stale) screen.
    if (state == AppLifecycleState.resumed) {
      _checkIfStoppedExternally();
    }
  }

  Future<void> _checkIfStoppedExternally() async {
    if (_handled) return;
    final stillRinging = await alarm_pkg.Alarm.isRinging(
      widget.ringingSettings.id,
    );
    if (!stillRinging) {
      await _finalizeAndPop();
    }
  }

  /// Runs the same "what happens after an alarm stops" bookkeeping
  /// (disable one-time / reschedule repeating) and pops, regardless
  /// of whether this was triggered by the in-app Stop button or by
  /// detecting an external stop.
  Future<void> _finalizeAndPop() async {
    if (_handled) return;
    _handled = true;

    try {
      final alarm = await widget.alarmService.getAlarm(
        widget.ringingSettings.id,
      );
      if (alarm != null) {
        if (alarm.type == models.AlarmType.oneTime) {
          await widget.alarmService.setEnabled(alarm, false);
        } else {
          await widget.alarmService.rescheduleAfterRing(alarm);
        }
      }
    } catch (_) {
      // Bookkeeping failure shouldn't trap the user on this screen.
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stop() async {
    try {
      await alarm_pkg.Alarm.stop(widget.ringingSettings.id);
    } catch (_) {
      // Already stopped natively (e.g. via lock-screen action) —
      // ignore and fall through to cleanup/pop anyway.
    }
    await _finalizeAndPop();
  }

  Future<void> _snooze(Duration duration) async {
    if (_handled) return;
    _handled = true;
    await alarm_pkg.Alarm.set(
      alarmSettings: widget.ringingSettings.copyWith(
        dateTime: DateTime.now().add(duration),
      ),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.ringingSettings.notificationSettings.title;
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
                    onPressed: () => _snooze(const Duration(minutes: 5)),
                    child: const Text('Snooze 5 min'),
                  ),
                ),
                const SizedBox(height: 16),

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
                    onPressed: _stop,
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