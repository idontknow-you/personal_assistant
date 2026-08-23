import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'today/today_screen.dart';
import 'tasks/task_list_page.dart';
import 'alarms/alarm_list_screen.dart';
import 'habits/habit_list_page.dart';
import 'notes/note_list_page.dart';
import 'notes/brain_dump_page.dart';
import 'notes/future_letter_list_page.dart';
import 'settings/settings_screen.dart';
import 'dsa/dsa_screen.dart';
import 'chat/chat_screen.dart';
import 'people/people_screen.dart';
import 'doom_scroll/doom_scroll_settings_screen.dart';
import 'doom_scroll/doom_scroll_interrupt_screen.dart';
import 'app_lock/app_lock_screen.dart';
import 'search/semantic_search_screen.dart';
import 'update/update_dialog.dart';
import '../services/update/update_service.dart';
import '../services/people/people_service.dart';
import '../services/doom_scroll/doom_scroll_service.dart';
import '../services/app_lock/app_lock_service.dart';
import '../main.dart' show alarmService;
import '../services/habits/habit_service.dart';
import '../services/notes/note_service.dart';
import '../services/notes/future_letter_service.dart';
import '../services/notes/brain_dump_service.dart';
import '../services/profile_service.dart';
import '../services/tags/tag_service.dart';
import '../services/dsa/dsa_problem_service.dart';

enum _NavTab { today, tasks, brainDump, chat }

enum _DrawerPage { alarms, habits, diary, dsa, letters, people, search, doomScroll, settings }

class HomeShell extends StatefulWidget {
  final String uid;
  const HomeShell({super.key, required this.uid});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  _NavTab _navTab = _NavTab.today;
  final _drawerKey = GlobalKey<ScaffoldState>();

  late final HabitService _habitService;
  late final NoteService _noteService;
  late final FutureLetterService _futureLetterService;
  late final BrainDumpService _brainDumpService;
  late final ProfileService _profileService;
  late final TagService _tagService;
  late final DSAProblemService _dsaService;
  bool _namePrompted = false;
  bool _interruptShown = false;
  DateTime? _interruptSnoozedUntil;
  bool _locked = true; // start locked until check completes
  bool _lockEnabled = false; // cached from _checkAppLock
  DateTime _lastActivity = DateTime.now();
  Timer? _inactivityTimer;

  @override
  void initState() {
    super.initState();
    _habitService = HabitService(widget.uid);
    _noteService = NoteService(widget.uid);
    _futureLetterService = FutureLetterService(widget.uid);
    _brainDumpService = BrainDumpService(widget.uid);
    _profileService = ProfileService(widget.uid);
    _tagService = TagService(widget.uid);
    _dsaService = DSAProblemService(widget.uid);
    WidgetsBinding.instance.addObserver(this);
    _checkAppLock();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    // Wait a bit for app to fully load
    await Future.delayed(const Duration(seconds: 5));
    if (!mounted) return;
    final update = await UpdateService.checkForUpdate();
    if (update != null && mounted) {
      UpdateDialog.show(context, update);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // Lock immediately on background/phone lock
      if (!_locked && _lockEnabled) {
        setState(() => _locked = true);
      }
    } else if (state == AppLifecycleState.resumed) {
      _lastActivity = DateTime.now();
      _checkInactivity();
    }
  }

  void _checkInactivity() {
    _inactivityTimer?.cancel();
    if (!_lockEnabled) return;
    _inactivityTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_locked && DateTime.now().difference(_lastActivity).inMinutes >= 5) {
        setState(() => _locked = true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _doomScrollTimer?.cancel();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkAppLock() async {
    final locked = await AppLockService.isEnabled();
    _lockEnabled = locked;
    if (!mounted) return;
    setState(() => _locked = locked);
    if (!locked) {
      _onUnlocked(); // no lock — proceed with normal init
    }
  }

  void _onUnlocked() {
    // Only run once
    if (!_locked && _namePrompted) return;
    _locked = false;
    _promptNameIfNeeded();
    _checkDueLetters();
    _startDoomScrollMonitor();
  }

  Timer? _doomScrollTimer;

  void _startDoomScrollMonitor() {
    Future.delayed(const Duration(seconds: 10), _checkDoomScrollLimits);
    _doomScrollTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) => _checkDoomScrollLimits(),
    );
  }

  Future<void> _checkDoomScrollLimits() async {
    if (!mounted || _interruptShown) return;
    if (_interruptSnoozedUntil != null &&
        DateTime.now().isBefore(_interruptSnoozedUntil!)) {
      return;
    }

    try {
      final exceeded = await DoomScrollService.checkLimits();
      if (exceeded.isNotEmpty && mounted) {
        _interruptShown = true;
        await Navigator.of(context).push(
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => DoomScrollInterruptScreen(
              uid: widget.uid,
              exceededApps: exceeded,
              onDismiss: () {
                _interruptShown = false;
                _interruptSnoozedUntil =
                    DateTime.now().add(const Duration(minutes: 15));
              },
            ),
          ),
        );
      }
    } catch (_) {}
  }



  void _checkDueLetters() async {
    try {
      final dueLetters = await _futureLetterService.getDueLetters();
      if (dueLetters.isNotEmpty && mounted) {
        await Future.delayed(const Duration(milliseconds: 1200));
        if (!mounted) return;
        final count = dueLetters.length;
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '$count future letter${count == 1 ? '' : 's'} ${count == 1 ? 'is' : 'are'} ready to open.',
              ),
              action: SnackBarAction(
                label: 'View',
                onPressed: () => _openDrawerPage(_DrawerPage.letters),
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (_) {}
  }

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
                    : "Got it — we'll call you \"$result\".",
              ),
            ),
          );
        }
      }
    } catch (_) {}
  }

  void _openDrawerPage(_DrawerPage page) {
    Navigator.pop(context); // close drawer
    Widget screen;
    switch (page) {
      case _DrawerPage.alarms:
        screen = AlarmListScreen(alarmService: alarmService);
        break;
      case _DrawerPage.habits:
        screen = HabitListPage(habitService: _habitService);
        break;
      case _DrawerPage.diary:
        screen = NoteListPage(noteService: _noteService);
        break;
      case _DrawerPage.letters:
        screen = FutureLetterListPage(letterService: _futureLetterService);
        break;
      case _DrawerPage.dsa:
        screen = DSAScreen(problemService: _dsaService);
        break;
      case _DrawerPage.people:
        screen = PeopleScreen(peopleService: PeopleService(widget.uid));
        break;
      case _DrawerPage.search:
        screen = SemanticSearchScreen(
          uid: widget.uid,
          noteService: _noteService,
          brainDumpService: _brainDumpService,
        );
        break;
      case _DrawerPage.doomScroll:
        screen = const DoomScrollSettingsScreen();
        break;
      case _DrawerPage.settings:
        screen = SettingsScreen(tagService: _tagService);
        break;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    // Show lock screen if app lock is enabled
    if (_locked) {
      return AppLockScreen(
        isSetup: false,
        onUnlocked: () {
          setState(() => _locked = false);
          _onUnlocked();
        },
      );
    }

    void openDrawer() => _drawerKey.currentState?.openDrawer();

    final bottomPages = [
      TodayScreen(
        uid: widget.uid,
        alarmService: alarmService,
        onMenuPressed: openDrawer,
      ),
      TaskListPage(
        uid: widget.uid,
        alarmService: alarmService,
        onMenuPressed: openDrawer,
      ),
      BrainDumpPage(
        brainDumpService: _brainDumpService,
        onMenuPressed: openDrawer,
      ),
      ChatScreen(onMenuPressed: openDrawer),
    ];

    return Scaffold(
      key: _drawerKey,
      drawer: _buildDrawer(context),
      body: GestureDetector(
        onTap: () => _lastActivity = DateTime.now(),
        onPanUpdate: (_) => _lastActivity = DateTime.now(),
        child: bottomPages[_navTab.index],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navTab.index,
        onDestinationSelected: (i) =>
            setState(() => _navTab = _NavTab.values[i]),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.wb_sunny_outlined), label: 'Today'),
          NavigationDestination(
              icon: Icon(Icons.checklist), label: 'Tasks'),
          NavigationDestination(
              icon: Icon(Icons.psychology_outlined), label: 'Dump'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline), label: 'Chat'),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context) {
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: StreamBuilder<String>(
                stream: _profileService.watchName(),
                builder: (context, snapshot) {
                  final name = snapshot.data ?? '';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name.isNotEmpty ? name : 'Personal OS',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        name.isNotEmpty ? 'Personal OS' : 'Your assistant',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.alarm),
              title: const Text('Alarms'),
              onTap: () => _openDrawerPage(_DrawerPage.alarms),
            ),
            ListTile(
              leading: const Icon(Icons.local_fire_department),
              title: const Text('Habits'),
              onTap: () => _openDrawerPage(_DrawerPage.habits),
            ),
            ListTile(
              leading: const Icon(Icons.book_outlined),
              title: const Text('Diary'),
              onTap: () => _openDrawerPage(_DrawerPage.diary),
            ),
            ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('DSA Spaced Repetition'),
              onTap: () => _openDrawerPage(_DrawerPage.dsa),
            ),
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('Letters to Future Me'),
              onTap: () => _openDrawerPage(_DrawerPage.letters),
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('People'),
              onTap: () => _openDrawerPage(_DrawerPage.people),
            ),
            ListTile(
              leading: const Icon(Icons.search),
              title: const Text('Search'),
              onTap: () => _openDrawerPage(_DrawerPage.search),
            ),
            ListTile(
              leading: const Icon(Icons.screen_lock_portrait),
              title: const Text('Anti-Doom-Scroll'),
              onTap: () => _openDrawerPage(_DrawerPage.doomScroll),
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () => _openDrawerPage(_DrawerPage.settings),
            ),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
}
