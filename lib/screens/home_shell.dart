import 'package:flutter/material.dart';
import 'tasks/task_list_page.dart';
import 'alarms/alarm_list_screen.dart';
import '../services/alarms/alarm_service.dart';

class HomeShell extends StatefulWidget {
  final String uid;
  const HomeShell({super.key, required this.uid});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final AlarmService _alarmService;

  @override
  void initState() {
    super.initState();
    _alarmService = AlarmService();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TaskListPage(uid: widget.uid, alarmService: _alarmService),
      AlarmListScreen(alarmService: _alarmService),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.checklist), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.alarm), label: 'Alarms'),
        ],
      ),
    );
  }
}