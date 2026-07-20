import 'package:flutter/services.dart';

/// Thin bridge to small native (Kotlin) helpers that Flutter has no
/// built-in equivalent for. Currently just exposes moveTaskToBack.
class NativeBridge {
  static const _channel = MethodChannel('com.example.personal_os/lockscreen');

  /// Sends the app to the background (like pressing Home), letting the
  /// lock screen reassert itself instead of staying visible underneath
  /// whatever screen gets revealed next after an alarm is stopped/snoozed.
  static Future<void> moveTaskToBack() async {
    try {
      await _channel.invokeMethod('moveTaskToBack');
    } catch (_) {
      // Non-fatal — worst case the app just stays visible.
    }
  }
}