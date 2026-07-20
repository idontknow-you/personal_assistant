import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:alarm/alarm.dart' as alarm_pkg;
import '../../models/alarms/alarm.dart' as models;
import '../../services/alarms/alarm_service.dart';
import '../../services/native_bridge.dart';
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

  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  /// How long an alarm rings unanswered before we treat it as missed.
  /// Tweak freely — 60s felt like a reasonable "gave it a real chance to
  /// wake someone up" window without ringing forever.
  static const _ringTimeoutDuration = Duration(seconds: 60);
  Timer? _ringTimeoutTimer;

  /// True if this ring is the automatic 5-minute retry (not the original
  /// alarm firing). Tagged via the notification body when the retry was
  /// scheduled — see AlarmService.scheduleMissedRetry.
  bool get _isRetryRing =>
      widget.ringingSettings.notificationSettings.body ==
      AlarmRingMarkers.missedRetry;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();

    _ringTimeoutTimer = Timer(_ringTimeoutDuration, _handleRingTimeout);

    // Live clock — purely cosmetic, doesn't touch any alarm logic.
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    _clockTimer?.cancel();
    _ringTimeoutTimer?.cancel();
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

  /// Fired when the alarm has been ringing unanswered for
  /// [_ringTimeoutDuration]. First time round: stop the sound and
  /// schedule one retry 5 minutes out. If THIS was already the retry:
  /// give up, leave a "missed alarm" notification, and run the normal
  /// post-ring bookkeeping so the alarm doesn't keep firing forever.
  Future<void> _handleRingTimeout() async {
    if (_handled) return;
    _handled = true;

    try {
      await alarm_pkg.Alarm.stop(widget.ringingSettings.id);
    } catch (_) {
      // Might already be stopped; fall through regardless.
    }

    try {
      if (_isRetryRing) {
        await widget.alarmService.fireMissedNotification(widget.ringingSettings);
        final alarm = await widget.alarmService.getAlarm(widget.ringingSettings.id);
        if (alarm != null) {
          if (alarm.type == models.AlarmType.oneTime) {
            await widget.alarmService.setEnabled(alarm, false);
          } else {
            await widget.alarmService.rescheduleAfterRing(alarm);
          }
        }
      } else {
        await widget.alarmService.scheduleMissedRetry(widget.ringingSettings);
      }
    } catch (_) {
      // Bookkeeping/retry-scheduling failure shouldn't trap the user here.
    }

    if (mounted) {
      Navigator.of(context).pop();
    }
    await WidgetsBinding.instance.endOfFrame;
    await NativeBridge.moveTaskToBack();
  }

  /// Runs the same "what happens after an alarm stops" bookkeeping
  /// (disable one-time / reschedule repeating), pops this screen, waits
  /// for the pop to actually commit, then backgrounds the task so the
  /// lock screen can reassert itself instead of leaving the app visible
  /// underneath. Order matters here: backgrounding before the pop fully
  /// commits can leave this route stuck in the stack (stale ring screen
  /// reappearing on next launch) and can leave WakelockPlus enabled
  /// indefinitely since dispose() never gets a frame to run.
  Future<void> _finalizeAndPop() async {
    if (_handled) return;
    _handled = true;
    _ringTimeoutTimer?.cancel();

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

    if (mounted) {
      Navigator.of(context).pop();
    }

    // Give Flutter one frame to commit the pop (and this screen's
    // dispose/WakelockPlus.disable) before backgrounding the task. With
    // the ring route now using a zero-duration transition, a single
    // frame is enough — no more multi-frame reveal of the screen
    // underneath before we background.
    await WidgetsBinding.instance.endOfFrame;

    await NativeBridge.moveTaskToBack();
  }

  Future<void> _stop() async {
    _ringTimeoutTimer?.cancel();
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
    _ringTimeoutTimer?.cancel();

    await alarm_pkg.Alarm.set(
      alarmSettings: widget.ringingSettings.copyWith(
        dateTime: DateTime.now().add(duration),
      ),
    );

    if (mounted) {
      Navigator.of(context).pop();
    }

    await WidgetsBinding.instance.endOfFrame;

    await NativeBridge.moveTaskToBack();
  }

  String get _timeString {
    final hour = _now.hour.toString().padLeft(2, '0');
    final minute = _now.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.ringingSettings.notificationSettings.title;

    return PopScope(
      canPop: false, // force Stop/Snooze — no dismissing via back button
      child: Scaffold(
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF0A0A14),
                Color(0xFF14101F),
                Color(0xFF090812),
              ],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  const Spacer(flex: 3),

                  // Pulsing glow behind a small alarm glyph
                  _GlowDot(),

                  const SizedBox(height: 28),

                  // Alarm label
                  Text(
                    title.isEmpty ? 'Alarm' : title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 1.2,
                    ),
                  ),

                  const SizedBox(height: 14),

                  // Large glowing time display
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        _timeString,
                        style: TextStyle(
                          fontSize: 76,
                          fontWeight: FontWeight.w200,
                          color: const Color(0xFF9B8CFF).withValues(alpha: 0.35),
                          letterSpacing: 2,
                          shadows: [
                            Shadow(
                              color: const Color(0xFF7C6CFF).withValues(alpha: 0.6),
                              blurRadius: 40,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _timeString,
                        style: const TextStyle(
                          fontSize: 76,
                          fontWeight: FontWeight.w200,
                          color: Colors.white,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),

                  const Spacer(flex: 4),

                  // Frosted-glass Snooze button
                  _GlassButton(
                    label: 'Snooze 5 min',
                    icon: Icons.snooze_rounded,
                    onTap: () => _snooze(const Duration(minutes: 5)),
                    filled: false,
                  ),
                  const SizedBox(height: 14),

                  // Frosted-glass Stop button, accent-filled
                  _GlassButton(
                    label: 'Stop',
                    icon: Icons.close_rounded,
                    onTap: _stop,
                    filled: true,
                  ),

                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Soft pulsing glow with a centered alarm glyph.
class _GlowDot extends StatefulWidget {
  @override
  State<_GlowDot> createState() => _GlowDotState();
}

class _GlowDotState extends State<_GlowDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF7C6CFF).withValues(alpha: 0.10 + t * 0.06),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7C6CFF).withValues(alpha: 0.25 + t * 0.25),
                blurRadius: 30 + t * 20,
                spreadRadius: 2 + t * 4,
              ),
            ],
          ),
          child: Icon(
            Icons.alarm_rounded,
            size: 34,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        );
      },
    );
  }
}

/// Frosted-glass pill button used for both Stop and Snooze.
class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.filled,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: filled
              ? const Color(0xFF7C6CFF).withValues(alpha: 0.85)
              : Colors.white.withValues(alpha: 0.06),
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: Colors.white.withValues(alpha: filled ? 0.15 : 0.12),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 20, color: Colors.white.withValues(alpha: 0.9)),
                  const SizedBox(width: 10),
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}