import 'package:flutter/material.dart';
import 'tasks/task_list_page.dart';
import 'alarms/alarm_list_screen.dart';
import 'habits/habit_list_page.dart';
import 'settings/settings_screen.dart';
import '../services/alarms/alarm_service.dart';
import '../services/habits/habit_service.dart';

class HomeShell extends StatefulWidget {
  final String uid;
  const HomeShell({super.key, required this.uid});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final AlarmService _alarmService;
  late final HabitService _habitService;

  @override
  void initState() {
    super.initState();
    _alarmService = AlarmService();
    _habitService = HabitService(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TaskListPage(uid: widget.uid, alarmService: _alarmService),
      AlarmListScreen(alarmService: _alarmService),
      HabitListPage(habitService: _habitService),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.alarm), label: 'Alarms'),
          NavigationDestination(icon: Icon(Icons.local_fire_department), label: 'Habits'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}