import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/tasks/task.dart';
import '../alarms/alarm_service.dart';

class TaskService {
  final String uid;

  /// Optional — needed to cancel/re-arm a task's linked alarm on
  /// complete/uncomplete, cascade-cancel it on delete, and re-arm it during
  /// daily rollover. Pass it in wherever TaskService is constructed
  /// alongside AlarmService.
  final AlarmService? alarmService;

  TaskService(this.uid, {this.alarmService});

  CollectionReference<Map<String, dynamic>> get _tasksRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('tasks');

  DocumentReference<Map<String, dynamic>> get _streakDocRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('meta')
      .doc('streak');

  Stream<List<Task>> watchTasks() {
    return _tasksRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Task.fromFirestore).toList());
  }

  /// Streams the global streak doc — {currentStreak, bestStreak,
  /// lastCheckedDate}. Not consumed by any UI yet; wired up so a streak
  /// display can be added later without touching this layer again.
  Stream<Map<String, dynamic>> watchStreak() {
    return _streakDocRef.snapshots().map(
          (doc) => doc.data() ?? {'currentStreak': 0, 'bestStreak': 0},
        );
  }

  /// Returns the new task's Firestore doc id, so callers (e.g. the task
  /// form, when also creating a linked alarm) can reference it immediately
  /// without a round-trip re-read.
  Future<String> addTask(
    String title, {
    Timestamp? dueDate,
    TaskRepeatType repeatType = TaskRepeatType.none,
    Set<int> repeatDays = const {},
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '';
    final doc = await _tasksRef.add({
      'title': trimmed,
      'completed': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'dueDate': dueDate,
      'repeatType': repeatType.name,
      'repeatDays': repeatDays.toList(),
      'linkedAlarmId': null,
    });
    return doc.id;
  }

  Future<void> updateTask(Task task) async {
    await _tasksRef.doc(task.id).update(task.toMap());
  }

  /// Patches only linkedAlarmId — used right after creating a brand-new
  /// task's linked alarm, where we don't have the full Task object with all
  /// its other fields intact to safely round-trip through updateTask.
  Future<void> setLinkedAlarm(String taskId, int alarmId) async {
    await _tasksRef.doc(taskId).update({'linkedAlarmId': alarmId});
  }

  /// Clears linkedAlarmId on a task without touching anything else — used
  /// when the alarm itself is deleted from the Alarms tab.
  Future<void> clearLinkedAlarm(String taskId) async {
    await _tasksRef.doc(taskId).update({'linkedAlarmId': null});
  }

  Future<Task?> getTask(String taskId) async {
    final doc = await _tasksRef.doc(taskId).get();
    if (!doc.exists) return null;
    return Task.fromFirestore(doc);
  }

  /// Toggles completion AND silences/re-arms the linked alarm to match —
  /// takes the full [Task] (not just id/bool) since we need linkedAlarmId.
  /// Completing early silences the reminder (isEnabled: false) rather than
  /// deleting it, since a repeating task's alarm needs to still exist for
  /// its *next* occurrence. Un-completing re-arms it. Rollover (below) also
  /// re-arms it when a repeating task's period resets, in case it's still
  /// silenced from an earlier completion.
  Future<void> toggleComplete(Task task) async {
    final newCompleted = !task.completed;
    await _tasksRef.doc(task.id).update({
      'completed': newCompleted,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (task.linkedAlarmId == null || alarmService == null) return;

    final alarm = await alarmService!.getAlarm(task.linkedAlarmId!);
    if (alarm == null) return;

    if (newCompleted && alarm.isEnabled) {
      await alarmService!.saveAlarm(alarm.copyWith(isEnabled: false));
    } else if (!newCompleted && !alarm.isEnabled) {
      await alarmService!.saveAlarm(alarm.copyWith(isEnabled: true));
    }
  }

  /// Takes the full [Task] (not just its id) so a linked alarm can be
  /// cancelled and removed at the same time — deleting a task shouldn't
  /// leave an orphaned alarm still ringing later.
  Future<void> deleteTask(Task task) async {
    if (task.linkedAlarmId != null && alarmService != null) {
      await alarmService!.deleteAlarm(task.linkedAlarmId!);
    }
    await _tasksRef.doc(task.id).delete();
  }

  // ---------------- Daily rollover + streak ----------------

  /// Call once when the app opens (e.g. from TaskListPage.initState).
  /// Does two things in one pass over "tasks due yesterday":
  ///   1. Updates the global day-level streak: if every task due yesterday
  ///      was completed, streak++; if any were missed, streak resets to 0.
  ///      If nothing was due yesterday, the streak is untouched either way.
  ///   2. Rolls forward any *repeating* tasks in that set: resets
  ///      completed to false and advances dueDate to the next occurrence.
  ///      Non-repeating tasks due yesterday are left as-is (still shown as
  ///      overdue/incomplete) — nothing here deletes or clears them.
  ///
  /// LIMITATION: this only ever checks "yesterday relative to today," once
  /// per calendar day the app is opened. If the app isn't opened for
  /// several days in a row, only the most recent missed day is evaluated —
  /// earlier gaps are silently skipped rather than retroactively breaking
  /// the streak multiple times. Good enough for now; a more thorough
  /// version would walk every day between lastCheckedDate and today.
  Future<void> runDailyRollover() async {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));

    final streakSnap = await _streakDocRef.get();
    final streakData = streakSnap.data();
    final lastChecked = (streakData?['lastCheckedDate'] as Timestamp?)?.toDate();

    if (lastChecked != null &&
        lastChecked.year == todayStart.year &&
        lastChecked.month == todayStart.month &&
        lastChecked.day == todayStart.day) {
      return; // already ran today
    }

    final snap = await _tasksRef
        .where('dueDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(yesterdayStart))
        .where('dueDate', isLessThan: Timestamp.fromDate(todayStart))
        .get();

    final tasksDueYesterday = snap.docs.map(Task.fromFirestore).toList();

    if (tasksDueYesterday.isNotEmpty) {
      final allCompleted = tasksDueYesterday.every((t) => t.completed);
      final currentStreak = (streakData?['currentStreak'] as int?) ?? 0;
      final bestStreak = (streakData?['bestStreak'] as int?) ?? 0;
      final newStreak = allCompleted ? currentStreak + 1 : 0;

      await _streakDocRef.set({
        'currentStreak': newStreak,
        'bestStreak': newStreak > bestStreak ? newStreak : bestStreak,
        'lastCheckedDate': Timestamp.fromDate(todayStart),
      }, SetOptions(merge: true));
    } else {
      // Nothing was due yesterday — neither builds nor breaks the streak.
      // Still record that today's check ran, so it doesn't re-run
      // repeatedly within the same day.
      await _streakDocRef.set({
        'lastCheckedDate': Timestamp.fromDate(todayStart),
      }, SetOptions(merge: true));
    }

    for (final task in tasksDueYesterday) {
      if (task.repeatType == TaskRepeatType.none) continue;

      final nextDue = _nextOccurrence(task, from: todayStart);
      await _tasksRef.doc(task.id).update({
        'completed': false,
        'dueDate': Timestamp.fromDate(nextDue),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (task.linkedAlarmId != null && alarmService != null) {
        final alarm = await alarmService!.getAlarm(task.linkedAlarmId!);
        if (alarm != null && !alarm.isEnabled) {
          await alarmService!.saveAlarm(alarm.copyWith(isEnabled: true));
        }
      }
    }
  }

  DateTime _nextOccurrence(Task task, {required DateTime from}) {
    if (task.repeatType == TaskRepeatType.daily) {
      return from; // due again today
    }
    // Weekly: walk forward from `from` (inclusive) to the next matching day.
    for (int offset = 0; offset < 7; offset++) {
      final day = from.add(Duration(days: offset));
      if (task.repeatDays.contains(day.weekday)) {
        return DateTime(day.year, day.month, day.day);
      }
    }
    // Unreachable if repeatDays is non-empty, but keeps the analyzer happy.
    return from;
  }
}