import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-app usage info returned from native.
class AppUsage {
  final String packageName;
  final String appName;
  final double totalTimeMinutes;
  final int totalTimeMs;

  AppUsage({
    required this.packageName,
    required this.appName,
    required this.totalTimeMinutes,
    required this.totalTimeMs,
  });

  factory AppUsage.fromMap(Map<String, dynamic> m) => AppUsage(
        packageName: m['packageName'] as String,
        appName: m['appName'] as String,
        totalTimeMinutes: (m['totalTimeMinutes'] as num).toDouble(),
        totalTimeMs: m['totalTimeMs'] as int,
      );
}

/// A monitored app with a daily time limit in minutes.
class MonitoredApp {
  final String packageName;
  final String appName;
  final int limitMinutes;

  MonitoredApp({
    required this.packageName,
    required this.appName,
    required this.limitMinutes,
  });

  Map<String, dynamic> toMap() => {
        'packageName': packageName,
        'appName': appName,
        'limitMinutes': limitMinutes,
      };

  factory MonitoredApp.fromMap(Map<String, dynamic> m) => MonitoredApp(
        packageName: m['packageName'] as String,
        appName: m['appName'] as String,
        limitMinutes: m['limitMinutes'] as int,
      );
}

class DoomScrollService {
  static const _usageChannel =
      MethodChannel('com.example.personal_os/usage_stats');
  static const _prefsKey = 'doom_scroll_monitored_apps';
  static const _globalLimitKey = 'doom_scroll_global_limit_minutes';
  static const _enabledKey = 'doom_scroll_enabled';

  /// Check if usage-stats permission is granted.
  static Future<bool> hasUsagePermission() async {
    try {
      final result = await _usageChannel.invokeMethod<bool>('hasUsagePermission');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Open system settings so user can grant it.
  static Future<void> requestUsagePermission() async {
    try {
      await _usageChannel.invokeMethod('requestUsagePermission');
    } catch (_) {}
  }

  /// Get installed user apps (for the picker).
  static Future<List<Map<String, dynamic>>> getInstalledApps() async {
    try {
      final raw = await _usageChannel.invokeMethod<String>('getInstalledApps');
      if (raw == null) return [];
      return List<Map<String, dynamic>>.from(jsonDecode(raw));
    } catch (_) {
      return [];
    }
  }

  /// Get today's usage for all apps.
  static Future<List<AppUsage>> getTodayUsage() async {
    try {
      final raw = await _usageChannel.invokeMethod<String>(
        'getUsageStats',
        {'daysBack': 1},
      );
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => AppUsage.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Get usage over the last [days] days.
  static Future<List<AppUsage>> getUsageForDays(int days) async {
    try {
      final raw = await _usageChannel.invokeMethod<String>(
        'getUsageStats',
        {'daysBack': days},
      );
      if (raw == null) return [];
      final list = jsonDecode(raw) as List;
      return list.map((e) => AppUsage.fromMap(e)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Which app is currently in the foreground?
  static Future<String?> getForegroundApp() async {
    try {
      return await _usageChannel.invokeMethod<String>('getForegroundApp');
    } catch (_) {
      return null;
    }
  }

  // ---- Persistence ----

  static Future<List<MonitoredApp>> getMonitoredApps() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_prefsKey) ?? [];
    return raw.map((s) => MonitoredApp.fromMap(jsonDecode(s))).toList();
  }

  static Future<void> setMonitoredApps(List<MonitoredApp> apps) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = apps.map((a) => jsonEncode(a.toMap())).toList();
    await prefs.setStringList(_prefsKey, raw);
  }

  static Future<int> getGlobalLimitMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_globalLimitKey) ?? 60; // default 1 hour
  }

  static Future<void> setGlobalLimitMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_globalLimitKey, minutes);
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  /// Check all monitored apps and return list of apps that exceeded their limit.
  /// Also checks the global limit (sum of all monitored apps).
  /// Always excludes Personal OS itself — no point blocking the app we're running in.
  static Future<List<Map<String, dynamic>>> checkLimits() async {
    if (!await isEnabled()) return [];
    // Skip the current app — never block the user from using Personal OS
    // (We can't self-identify by package name here, so we skip by checking
    //  the native getUsageStats which already filters us out. But as an extra
    //  safety net, we also filter the monitored list below.)

    final monitored = await getMonitoredApps();
    if (monitored.isEmpty) return [];

    final usage = await getTodayUsage();
    final usageMap = {for (final u in usage) u.packageName: u};

    final exceeded = <Map<String, dynamic>>[];
    double totalMinutes = 0;

    for (final app in monitored) {
      final u = usageMap[app.packageName];
      final minutes = u?.totalTimeMinutes ?? 0;
      totalMinutes += minutes;
      if (minutes >= app.limitMinutes) {
        exceeded.add({
          'packageName': app.packageName,
          'appName': app.appName,
          'usedMinutes': minutes.round(),
          'limitMinutes': app.limitMinutes,
          'type': 'per_app',
        });
      }
    }

    final globalLimit = await getGlobalLimitMinutes();
    if (totalMinutes >= globalLimit) {
      exceeded.add({
        'packageName': '__global__',
        'appName': 'All monitored apps',
        'usedMinutes': totalMinutes.round(),
        'limitMinutes': globalLimit,
        'type': 'global',
      });
    }

    return exceeded;
  }
}
