import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, MethodCall;
import 'package:alarm/alarm.dart' as alarm_pkg;
import '../../models/alarms/alarm.dart' as models;
import '../../services/alarms/alarm_service.dart';
import '../../services/native_bridge.dart';
import '../../widgets/alarms/alarm_ring_widgets.dart';
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

  /// The linked task's "why it matters" commitment text, if any — loaded
  /// best-effort in initState. Empty string renders nothing, so standalone
  /// alarms (no linked task) and offline/error lookups just show the
  /// normal ring screen with no extra section.
  String _commitmentText = '';

  /// How long an alarm rings unanswered before we treat it as missed.
  /// Tweak freely — 60s felt like a reasonable "gave it a real chance to
  /// wake someone up" window without ringing forever.
  static const _ringTimeoutDuration = Duration(seconds: 60);
  Timer? _ringTimeoutTimer;

  /// True if this ring is the automatic 5-minute retry for a STANDALONE
  /// alarm (not linked to a task). Tagged via the notification body when
  /// the retry was scheduled — see AlarmService.scheduleMissedRetry.
  bool get _isRetryRing =>
      widget.ringingSettings.notificationSettings.body ==
      AlarmRingMarkers.missedRetry;

  /// Which rung of the task-linked escalation ladder this ring is
  /// (0-based, see AlarmService.escalationIntervals), or -1 if it isn't
  /// an escalated retry (fresh ring, standalone retry, or snoozed).
  int get _escalationStage => AlarmRingMarkers.escalationStageFrom(
      widget.ringingSettings.notificationSettings.body);

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

    _loadCommitmentText();
  }

  /// Best-effort fetch of the linked task's commitment text: alarm →
  /// linkedTaskId → task doc → commitmentText. Any failure (offline,
  /// standalone alarm, task deleted) just leaves [_commitmentText] empty
  /// and the ring screen renders unchanged — this must never block or
  /// delay an actual ringing alarm.
  Future<void> _loadCommitmentText() async {
    try {
      final alarm = await widget.alarmService.getAlarm(
        widget.ringingSettings.id,
      );
      final taskId = alarm?.linkedTaskId;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (taskId == null || uid == null) return;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('tasks')
          .doc(taskId)
          .get();
      if (!doc.exists) return;
      final text = (doc.data()?['commitmentText'] as String?) ?? '';
      if (!mounted || text.isEmpty) return;
      setState(() => _commitmentText = text);
    } catch (_) {
      // Silent best-effort — see doc comment above.
    }
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
  /// [_ringTimeoutDuration]. What happens next depends on the alarm type:
  ///  - Fresh task-linked reminder: schedule rung 0 of the escalation
  ///    ladder (5 min → 15 min → 1 hr; only the final rung gives up).
  ///  - Fresh standalone alarm: schedule the single 5-minute retry.
  ///  - Escalation rung that timed out: advance to the next rung, or give
  ///    up after the last one (missed notification + post-ring bookkeeping).
  ///  - Standalone retry that timed out: give up (same bookkeeping).
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
        // Standalone alarm's retry timed out — give up.
        await _giveUpAfterMissedRing();
      } else if (_escalationStage >= 0) {
        // Task-linked escalation rung timed out. Advance to the next
        // rung unless this was the final one, in which case give up.
        final nextStage = _escalationStage + 1;
        if (nextStage < AlarmService.escalationIntervals.length) {
          await widget.alarmService.scheduleEscalatedRetry(
            widget.ringingSettings,
            nextStage,
          );
        } else {
          await _giveUpAfterMissedRing();
        }
      } else {
        // Fresh ring. Task-linked reminders get the escalating ladder;
        // standalone alarms keep the single 5-minute retry.
        final alarm = await widget.alarmService.getAlarm(
          widget.ringingSettings.id,
        );
        if (alarm?.linkedTaskId != null) {
          await widget.alarmService.scheduleEscalatedRetry(
            widget.ringingSettings,
            0,
          );
        } else {
          await widget.alarmService.scheduleMissedRetry(widget.ringingSettings);
        }
      }
    } catch (_) {
      // Bookkeeping/retry-scheduling failure shouldn't trap the user here.
    }

    _popRoute();
    await WidgetsBinding.instance.endOfFrame;
    await NativeBridge.moveTaskToBack();
  }

  /// Shared "this alarm is never coming back" cleanup: leave a missed
  /// notification, then disable a one-time alarm or reschedule a
  /// repeating one so it doesn't keep firing forever.
  Future<void> _giveUpAfterMissedRing() async {
    await widget.alarmService.fireMissedNotification(widget.ringingSettings);
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
                  const GlowDot(),

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

                  if (_commitmentText.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    // The task's "why it matters" text — the user's own
                    // written reason, shown back to them while the alarm
                    // rings. Styled softer than the label/time so it
                    // supports the moment rather than competing with it.
                    Icon(
                      Icons.format_quote_rounded,
                      size: 18,
                      color: Colors.white.withValues(alpha: 0.4),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _commitmentText,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 17,
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
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
                  GlassButton(
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
                        ? GlassButton(
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

