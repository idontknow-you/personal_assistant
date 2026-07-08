import 'dart:async';
import 'package:flutter/material.dart';
import 'package:alarm/alarm.dart' as alarm_pkg;
import '../../screens/alarms/alarm_ring_screen.dart';
import 'alarm_service.dart';

/// Listens for ringing alarms globally and pushes the ring screen.
/// Call `.start()` once in main.dart, after `Alarm.init()`. Nothing
/// else in the app needs to know this exists.
class AlarmRingListener {
  AlarmRingListener({
    required this.navigatorKey,
    required this.alarmService,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final AlarmService alarmService;

  StreamSubscription<alarm_pkg.AlarmSettings>? _subscription;

  void start() {
    _subscription = alarm_pkg.Alarm.ringStream.stream.listen(_onRing);
  }

  void _onRing(alarm_pkg.AlarmSettings ringingSettings) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AlarmRingScreen(
          ringingSettings: ringingSettings,
          alarmService: alarmService,
        ),
      ),
    );
  }

  void dispose() => _subscription?.cancel();
}