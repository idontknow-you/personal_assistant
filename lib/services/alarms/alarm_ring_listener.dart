import 'dart:async';
import 'package:flutter/material.dart';
import 'package:alarm/alarm.dart' as alarm_pkg;
import '../../screens/alarms/alarm_ring_screen.dart';
import 'alarm_service.dart';

/// Listens for ringing alarms globally and pushes the ring screen.
/// Call `.start()` once in main.dart, after `alarmService.init()`.
/// Nothing else in the app needs to know this exists.
class AlarmRingListener with WidgetsBindingObserver {
  AlarmRingListener({
    required this.navigatorKey,
    required this.alarmService,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final AlarmService alarmService;

  StreamSubscription<alarm_pkg.AlarmSettings>? _subscription;
  Timer? _retryTimer;

  /// Tracks the currently-pushed ring route (if any) so we can defensively
  /// remove it if a new ring event comes in before the old one was
  /// properly cleaned up (guards against stale ring screens surviving
  /// across app launches after a botched pop/background race).
  Route<void>? _activeRingRoute;

  /// id of the alarm currently shown/being pushed. Used to dedupe: the
  /// normal ringStream event and the "already ringing" safety check can
  /// both fire for the same alarm around the same moment (cold start, or
  /// app resume via notification tap). Without this guard, both paths can
  /// try to push a ring screen independently and collide mid-transition,
  /// leaving a non-interactive screen behind (Stop/Snooze taps go
  /// nowhere) until something eventually resolves on its own.
  int? _activeRingAlarmId;

  void start() {
    // ringStream is deprecated; Alarm.ringing emits the full set of
    // currently-ringing alarms on every change (an alarm is added when it
    // starts ringing and removed when it stops). .expand() flattens each
    // set into individual AlarmSettings events, and _onRing dedupes by id,
    // so repeat emissions for the same alarm are safe to ignore.
    _subscription = alarm_pkg.Alarm.ringing
        .expand((ringingSet) => ringingSet.alarms)
        .listen(_onRing);
    WidgetsBinding.instance.addObserver(this);

    // Cold-start guard: if an alarm was already ringing when the process
    // launched (native side fired before our Dart listener/navigator was
    // ready), check once we're up so we don't silently miss it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAlreadyRinging());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Safety net for a known upstream plugin issue: tapping the alarm
    // notification while the app is backgrounded sometimes doesn't fire
    // ringStream at all. Re-checking on every resume catches that case
    // via a direct isRinging() query instead of relying solely on the
    // stream event.
    if (state == AppLifecycleState.resumed) {
      _checkAlreadyRinging();
    }
  }

  Future<void> _checkAlreadyRinging() async {
    try {
      final alarms = await alarm_pkg.Alarm.getAlarms();
      for (final a in alarms) {
        if (_activeRingAlarmId == a.id) continue; // already being shown
        if (await alarm_pkg.Alarm.isRinging(a.id)) {
          _onRing(a);
          return;
        }
      }
    } catch (_) {
      // If getAlarms()/isRinging() aren't available in this plugin version,
      // this just silently skips the extra safety check.
    }
  }

  void _onRing(alarm_pkg.AlarmSettings ringingSettings) {
    if (_activeRingAlarmId == ringingSettings.id) return; // dedupe
    _pushRingScreen(ringingSettings);
  }

  void _pushRingScreen(alarm_pkg.AlarmSettings ringingSettings, [int attempt = 0]) {
    final navigator = navigatorKey.currentState;

    if (navigator == null) {
      // Navigator not attached yet (cold-start race). Retry briefly
      // instead of dropping the event. Give up after ~5s.
      if (attempt >= 25) return;
      _retryTimer?.cancel();
      _retryTimer = Timer(
        const Duration(milliseconds: 200),
        () => _pushRingScreen(ringingSettings, attempt + 1),
      );
      return;
    }

    // Defensive: if a previous ring screen never got cleaned up (e.g. a
    // pop/background race left it stuck), remove it before showing a new
    // one so stale ring screens can't stack up across launches.
    if (_activeRingRoute != null) {
      try {
        navigator.removeRoute(_activeRingRoute!);
      } catch (_) {
        // Route may already be gone; ignore.
      }
      _activeRingRoute = null;
    }

    _activeRingAlarmId = ringingSettings.id;

    // Zero-duration transition: this route slides in/out instantly rather
    // than animating, so when we pop it after Stop/Snooze there's no
    // multi-frame reveal of whatever's underneath before we background
    // the task — minimizes the visible "flash" to a single frame.
    final route = PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => AlarmRingScreen(
        ringingSettings: ringingSettings,
        alarmService: alarmService,
      ),
    );
    _activeRingRoute = route;

    navigator.push(route).then((_) {
      if (identical(_activeRingRoute, route)) {
        _activeRingRoute = null;
        _activeRingAlarmId = null;
      }
    });
  }

  void dispose() {
    _subscription?.cancel();
    _retryTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}