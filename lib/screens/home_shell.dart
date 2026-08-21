import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'tasks/task_list_page.dart';
import 'alarms/alarm_list_screen.dart';
import 'habits/habit_list_page.dart';
import 'notes/note_list_page.dart';
import '../main.dart' show alarmService;
import '../services/habits/habit_service.dart';
import '../services/notes/note_service.dart';
import '../services/profile_service.dart';

class HomeShell extends StatefulWidget {
  final String uid;
  const HomeShell({super.key, required this.uid});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  late final HabitService _habitService;
  late final NoteService _noteService;
  late final ProfileService _profileService;
  bool _namePrompted = false;

  @override
  void initState() {
    super.initState();
    _habitService = HabitService(widget.uid);
    _noteService = NoteService(widget.uid);
    _profileService = ProfileService(widget.uid);
    _promptNameIfNeeded();
  }

  /// Shows the "What should we call you?" dialog on first launch if the
  /// user hasn't set a name yet. Uses [_namePrompted] so it only fires
  /// once per session (not on every rebuild / hot reload).
  void _promptNameIfNeeded() async {
    if (_namePrompted) return;
    _namePrompted = true;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('meta')
          .doc('profile')
          .get();
      final name = (doc.data()?['name'] as String?) ?? '';
      if (name.isNotEmpty || !mounted) return;

      // Small delay so the UI has time to build first.
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;

      final controller = TextEditingController();
      final result = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('What should we call you?'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 30,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'Your name',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Skip for now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );

      if (result != null && mounted) {
        await _profileService.setName(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                result.isEmpty
                    ? 'Name cleared.'
                    : 'Got it — we\'ll call you "$result".',
              ),
            ),
          );
        }
      }
    } catch (_) {
      // Don't crash on profile check failure — the user can always
      // set their name later from Settings.
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TaskListPage(uid: widget.uid, alarmService: alarmService),
      AlarmListScreen(alarmService: alarmService),
      HabitListPage(habitService: _habitService),
      NoteListPage(noteService: _noteService, uid: widget.uid),
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
          NavigationDestination(icon: Icon(Icons.book_outlined), label: 'Diary'),
        ],
      ),
    );
  }
}