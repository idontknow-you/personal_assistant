import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/alarms/alarm_service.dart';
import 'services/alarms/alarm_ring_listener.dart';
import 'theme/app_theme.dart';

/// Global theme mode state (light/dark/system) — local, via SharedPreferences.
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

/// Global color palette state — per-user, via Firestore.
final ValueNotifier<ThemePalette> paletteNotifier =
    ValueNotifier(AppThemePresets.aurora);

/// Global navigator key so AlarmRingListener can push the ring screen
/// from outside the widget tree (it has no BuildContext of its own).
final navigatorKey = GlobalKey<NavigatorState>();

/// Single shared instance — reuse this everywhere instead of creating
/// new AlarmService()s (screens, listener, etc. should all take this
/// one via constructor param).
final alarmService = AlarmService();

Future<void> setThemeMode(ThemeMode mode) async {
  themeNotifier.value = mode;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('themeMode', mode.name);
}

Future<void> setThemePreset(String key) async {
  paletteNotifier.value = AppThemePresets.byKey(key);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('meta')
      .doc('settings')
      .set({'themePreset': key}, SetOptions(merge: true));
}

/// Loads the saved palette whenever a user becomes available (anon sign-in
/// happens inside AuthGate, so this fires once that resolves).
void _listenForThemePreset() {
  FirebaseAuth.instance.authStateChanges().listen((user) async {
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('meta')
          .doc('settings')
          .get();
      final key = doc.data()?['themePreset'] as String?;
      if (key != null) {
        paletteNotifier.value = AppThemePresets.byKey(key);
      }
    } catch (_) {
      // keep default palette on failure
    }
  });
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await alarmService.init(); // was: await Alarm.init();

  AlarmRingListener(
    navigatorKey: navigatorKey,
    alarmService: alarmService,
  ).start();

  final prefs = await SharedPreferences.getInstance();
  switch (prefs.getString('themeMode')) {
    case 'light':
      themeNotifier.value = ThemeMode.light;
      break;
    case 'system':
      themeNotifier.value = ThemeMode.system;
      break;
    default:
      themeNotifier.value = ThemeMode.dark;
  }

  _listenForThemePreset();

  runApp(const PersonalOSApp());
}

class PersonalOSApp extends StatelessWidget {
  const PersonalOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return ValueListenableBuilder<ThemePalette>(
          valueListenable: paletteNotifier,
          builder: (context, palette, _) {
            return MaterialApp(
              navigatorKey: navigatorKey,
              title: 'Personal OS',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(palette),
              darkTheme: AppTheme.dark(palette),
              themeMode: currentMode,
              home: const AuthGate(),
            );
          },
        );
      },
    );
  }
}