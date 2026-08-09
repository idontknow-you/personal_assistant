import 'package:flutter/material.dart';
import 'tasks/task_list_page.dart';
import 'alarms/alarm_list_screen.dart';
import 'habits/habit_list_page.dart';
import '../main.dart' show alarmService;
import '../services/habits/habit_service.dart';

class HomeShell extends StatefulWidget {
  final String uid;
  const HomeShell({super.key, required this.uid});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final HabitService _habitService;

  @override
  void initState() {
    super.initState();
    // Deliberately NOT creating a local AlarmService() here — this app has
    // exactly one shared AlarmService instance (main.dart's global
    // `alarmService`), which AlarmRingListener also runs against. A second
    // independent instance here would let the in-app alarm list/task
    // reminders drift out of sync with what the ring listener actually
    // sees (e.g. an alarm saved through this screen not being visible to
    // the listener, or vice versa), since each instance would maintain
    // its own view of alarm state.
    _habitService = HabitService(widget.uid);
  }

  @override
  Widget build(BuildContext context) {
    // Settings lives only in TaskListPage's AppBar now, not as its own
    // bottom nav destination — see HomeShell history for why (three
    // frequently-switched sections deserve the nav bar; Settings is
    // occasional and reachable fine from an AppBar icon instead).
    final pages = [
      TaskListPage(uid: widget.uid, alarmService: alarmService),
      AlarmListScreen(alarmService: alarmService),
      HabitListPage(habitService: _habitService),
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
        ],
      ),
    );
  }
}