import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'package:alarm/alarm.dart';
import 'services/alarms/alarm_service.dart';
import 'services/alarms/alarm_ring_listener.dart';

/// Global theme state — read/written from anywhere via themeNotifier / setThemeMode()
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

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

  runApp(const PersonalOSApp());
}

class PersonalOSApp extends StatelessWidget {
  const PersonalOSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          navigatorKey: navigatorKey, // added — required for AlarmRingListener
          title: 'Personal OS',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.deepPurple,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          themeMode: currentMode,
          home: const AuthGate(),
        );
      },
    );
  }
}