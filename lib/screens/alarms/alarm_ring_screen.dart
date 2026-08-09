import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
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

  // Controls PopScope's canPop. Starts false so the hardware/gesture back
  // button can't dismiss the ring screen. Flipped to true right before any
  // programmatic pop we trigger ourselves (Stop / Snooze / timeout), since
  // canPop:false blocks ALL pops on this route -- not just the back button
  // -- including Navigator.of(context).pop() calls from our own code.
  bool _allowPop = false;

  // Same channel MainActivity.kt already uses for moveTaskToBack /
  // hasOverlayPermission etc. Reusing it rather than adding a second
  // channel — it's just one more method name on the existing bridge.
  static const _nativeChannel =
      MethodChannel('com.example.personal_os/lockscreen');

  // True once the volume-key silence has fired. Mutes the sound and swaps
  // the UI into a "Silenced" state, but deliberately does NOT pop this
  // screen or run _finalizeAndPop's bookkeeping — a volume-button bump
  // (in a pocket, reaching for the phone, etc.) is a much easier accident
  // than tapping Stop, so it shouldn't fully dismiss/disable the alarm.
  // The user still has to hit Stop (or let the ring timeout fire) to
  // actually close out.
  bool _silenced = false;

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

  /// How many times this ring cycle has already been snoozed, decoded from
  /// the notification body (see AlarmRingMarkers.snoozed/snoozeCountFrom).
  /// 0 for a fresh ring or a missed-retry ring — snooze count and the
  /// missed-retry marker are mutually exclusive, so this never collides
  /// with [_isRetryRing].
  int get _snoozeCount =>
      AlarmRingMarkers.snoozeCountFrom(widget.ringingSettings.notificationSettings.body);

  static const _maxSnoozes = 3;

  bool get _canSnooze => _snoozeCount < _maxSnoozes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WakelockPlus.enable();
    _nativeChannel.setMethodCallHandler(_handleNativeCall);

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
    _nativeChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'volumeKeyPressed') {
      await _silenceOnly();
    }
    return null;
  }

  /// Mutes the ringing sound without dismissing the screen or running any
  /// of the post-ring bookkeeping (unlike Stop). If it's already silenced,
  /// a second volume-key press is a no-op — nothing left to silence.
  Future<void> _silenceOnly() async {
    if (_handled || _silenced) return;
    setState(() => _silenced = true);
    try {
      await alarm_pkg.Alarm.stop(widget.ringingSettings.id);
    } catch (_) {
      // Already stopped — fine.
    }
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

  /// Flips _allowPop on and pops this route. Use this instead of a bare
  /// `Navigator.of(context).pop()` anywhere in this screen -- with
  /// PopScope's canPop normally false, a bare pop() is silently swallowed
  /// (route stays on the stack, nothing visibly happens, and the app can
  /// end up backgrounded over a ring screen that never actually closed).
  void _popRoute() {
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.of(context).pop();
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

    _popRoute();
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

    _popRoute();

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

  /// Snoozes this ring: cancels it and schedules a new one-shot ring
  /// [duration] out, tagging the next ring's body with an incremented
  /// snooze count so it (and only it) knows how many times this cycle
  /// has been snoozed. Capped at [_maxSnoozes] — [_canSnooze] should be
  /// checked before this is wired to a button, but it's also re-checked
  /// here as a safety net.
  ///
  /// Deliberately does NOT go through the missed-retry bookkeeping path:
  /// this is a direct user action, not a timeout, so it shouldn't count
  /// toward or interact with the separate missed-alarm-retry counter.
  Future<void> _snooze(Duration duration) async {
    if (_handled || !_canSnooze) return;
    _handled = true;
    _ringTimeoutTimer?.cancel();

    final nextCount = _snoozeCount + 1;

    await alarm_pkg.Alarm.set(
      alarmSettings: widget.ringingSettings.copyWith(
        dateTime: DateTime.now().add(duration),
        notificationSettings: alarm_pkg.NotificationSettings(
          title: widget.ringingSettings.notificationSettings.title,
          body: AlarmRingMarkers.snoozed(nextCount),
          stopButton: widget.ringingSettings.notificationSettings.stopButton,
        ),
      ),
    );

    _popRoute();

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
    final remainingSnoozes = _maxSnoozes - _snoozeCount;

    return PopScope(
      canPop: _allowPop, // was: false — see _popRoute() for why
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

                  if (_silenced) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Silenced — tap Stop to dismiss',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.4),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],

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

                  // Primary action: Stop (full-size, filled)
                  _GlassButton(
                    label: 'Stop',
                    icon: Icons.close_rounded,
                    onTap: _stop,
                    filled: true,
                  ),

                  const SizedBox(height: 12),

                  // Secondary action: Snooze — same pill size/shape as Stop
                  // (just unfilled, so Stop still reads as primary), sitting
                  // directly below it. Capped at _maxSnoozes; once used up,
                  // it's replaced by a same-height note instead of a
                  // disabled button, so it's clear this ring cycle is out
                  // of snoozes rather than looking like a bug.
                  SizedBox(
                    height: 58,
                    child: _canSnooze
                        ? _GlassButton(
                            label: remainingSnoozes < _maxSnoozes
                                ? 'Snooze 5 min · $remainingSnoozes left'
                                : 'Snooze 5 min',
                            icon: Icons.snooze_rounded,
                            onTap: () => _snooze(const Duration(minutes: 5)),
                            filled: false,
                          )
                        : Center(
                            child: Text(
                              'No snoozes left for this alarm',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 13,
                              ),
                            ),
                          ),
                  ),

                  // Extra bottom breathing room — was 24, which read as
                  // the button cluster sticking to the screen edge on
                  // most devices. This lifts Stop/Snooze up off the
                  // bottom without changing anything above them.
                  const SizedBox(height: 48),
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

/// Frosted-glass pill button — used for both Stop (filled) and Snooze
/// (unfilled), so they share the same size/shape and only differ in
/// fill/emphasis, keeping Stop read as primary without Snooze looking
/// like an afterthought.
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