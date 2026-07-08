import 'package:flutter/material.dart';
import 'tasks/task_list_page.dart';
import 'alarms/alarm_list_screen.dart';

/// Minimal bottom-nav shell for Phase 1 — switches between Tasks and Alarms.
/// Extend `pages` / `destinations` together as Phase 2+ screens are added
/// (notes/diary, doom-scroll blocker, etc).
class HomeShell extends StatefulWidget {
  final String uid;
  const HomeShell({super.key, required this.uid});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      TaskListPage(uid: widget.uid),
      const AlarmListScreen(),
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