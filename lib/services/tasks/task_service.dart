import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/tasks/task.dart';
import '../../utils/date_utils.dart';
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
  /// lastCheckedDate}.
  Stream<Map<String, dynamic>> watchStreak() {
    return _streakDocRef.snapshots().map(
          (doc) => doc.data() ?? {'currentStreak': 0, 'bestStreak': 0},
        );
  }

  Future<String> addTask(
    String title, {
    Timestamp? dueDate,
    TaskRepeatType repeatType = TaskRepeatType.none,
    Set<int> repeatDays = const {},
    Priority priority = Priority.low,
    List<Subtask> subtasks = const [],
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
      'priority': priority.name,
      'subtasks': subtasks.map((s) => s.toMap()).toList(),
      'completionLog': <String, bool>{},
    });
    return doc.id;
  }

  Future<void> updateTask(Task task) async {
    await _tasksRef.doc(task.id).update(task.toMap());
  }

  Future<void> setLinkedAlarm(String taskId, int alarmId) async {
    await _tasksRef.doc(taskId).update({'linkedAlarmId': alarmId});
  }

  Future<void> clearLinkedAlarm(String taskId) async {
    await _tasksRef.doc(taskId).update({'linkedAlarmId': null});
  }

  Future<Task?> getTask(String taskId) async {
    final doc = await _tasksRef.doc(taskId).get();
    if (!doc.exists) return null;
    return Task.fromFirestore(doc);
  }

  Future<void> toggleSubtask(
    String taskId,
    String subtaskId,
    bool isCompleted,
  ) async {
    final task = await getTask(taskId);
    if (task == null) return;

    final updatedSubtasks = task.subtasks
        .map((s) =>
            s.id == subtaskId ? s.copyWith(isCompleted: isCompleted) : s)
        .toList();

    await _tasksRef.doc(taskId).update({
      'subtasks': updatedSubtasks.map((s) => s.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Toggles completion for the task's *current* active period (its
  /// dueDate, or today if no dueDate is set) and silences/re-arms the
  /// linked alarm to match. Also writes the same result into
  /// [Task.completionLog] under that date's key, so history/streak/heatmap
  /// stay consistent with what the checkbox shows without a separate write.
  Future<void> toggleComplete(Task task) async {
    final newCompleted = !task.completed;
    final logDate = task.dueDate?.toDate() ?? DateTime.now();
    final key = dateKey(logDate);
    final updatedLog = {...task.completionLog, key: newCompleted};

    await _tasksRef.doc(task.id).update({
      'completed': newCompleted,
      'completionLog': updatedLog,
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

  /// Marks (or unmarks) completion for an ARBITRARY date — past, present,
  /// or future — without requiring that date to be the task's current
  /// active period. This is what fixes backdating: e.g. you forgot to
  /// check off a daily task three days ago, rollover already advanced past
  /// it, but you can still open its history and mark that day done.
  ///
  /// Only writes into [completionLog]. If [date] happens to equal the
  /// task's current active period, it ALSO updates the live `completed`
  /// field (and alarm silencing) so the checkbox on the Tasks screen tile
  /// stays in sync — otherwise the two would visibly disagree. Backdated
  /// entries for any other date only affect history/streak, never the
  /// live checkbox.
  ///
  /// "Current active period" uses the exact same fallback as
  /// toggleComplete: task.dueDate if set, otherwise today. Previously this
  /// only checked task.dueDate directly, so for any task with no due date
  /// set, marking *today* complete from the calendar would update
  /// completionLog (correctly) but never touch `completed` — meaning the
  /// Tasks screen checkbox (which reads `completed`, not completionLog)
  /// silently fell out of sync with what the calendar showed. Matching
  /// the fallback here fixes that for both marking and unmarking.
  Future<void> setCompletionForDate(
    Task task,
    DateTime date,
    bool completed,
  ) async {
    final key = dateKey(date);
    final effectiveActiveDate = task.dueDate?.toDate() ?? DateTime.now();
    final isActivePeriod = isSameDay(effectiveActiveDate, date);

    final updatedLog = {...task.completionLog};
    if (!completed && !isActivePeriod) {
      // Unmarking a BACKDATED day that ISN'T the task's current active
      // period: delete the entry entirely rather than storing `false`.
      // The calendar screen treats any key present in completionLog as
      // "this task is tied to this date" so it can surface backdated
      // entries that fall outside the task's normal repeat pattern.
      // Previously unmarking such a day still wrote `false`, which left
      // that key behind — so the task stayed glued to that date on the
      // calendar (just shown unchecked) even after you'd explicitly
      // undone it. Deleting the key makes an unmarked backdated day
      // disappear from the calendar entirely, unless it's also part of
      // the task's actual due date/repeat pattern, in which case it'll
      // still show via the pattern itself, just correctly unchecked.
      updatedLog.remove(key);
    } else {
      updatedLog[key] = completed;
    }

    final update = <String, dynamic>{
      'completionLog': updatedLog,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (isActivePeriod) {
      update['completed'] = completed;
    }

    await _tasksRef.doc(task.id).update(update);

    if (!isActivePeriod || task.linkedAlarmId == null || alarmService == null) {
      return;
    }
    final alarm = await alarmService!.getAlarm(task.linkedAlarmId!);
    if (alarm == null) return;
    if (completed && alarm.isEnabled) {
      await alarmService!.saveAlarm(alarm.copyWith(isEnabled: false));
    } else if (!completed && !alarm.isEnabled) {
      await alarmService!.saveAlarm(alarm.copyWith(isEnabled: true));
    }
  }

  Future<void> deleteTask(Task task) async {
    if (task.linkedAlarmId != null && alarmService != null) {
      await alarmService!.deleteAlarm(task.linkedAlarmId!);
    }
    await _tasksRef.doc(task.id).delete();
  }

  // ---------------- Daily rollover + streak ----------------

  /// Call once when the app opens. Two things in one pass over "tasks due
  /// yesterday":
  ///   1. Updates the global day-level streak — now reads
  ///      [Task.completionLog] for yesterday's key rather than the live
  ///      `completed` field, falling back to `completed` if the log has no
  ///      entry yet (covers tasks toggled before this field existed). This
  ///      is what makes a backdated completion actually count toward the
  ///      streak even if it's logged after rollover already ran once.
  ///   2. Rolls forward repeating tasks: resets completed to false and
  ///      advances dueDate to the next occurrence, but first makes sure
  ///      yesterday's result is captured in completionLog before it resets.
  ///
  /// IMPORTANT: this only finds tasks via a query on `dueDate`, so a
  /// repeating task with no `dueDate` set is invisible to it and will
  /// never roll over. TaskFormScreen now guarantees repeating tasks always
  /// get a dueDate (defaulting to today) at creation/edit time specifically
  /// so they stay visible to this query — if that ever changes, rollover
  /// needs a different way to find repeating tasks.
  ///
  /// LIMITATION: only ever checks "yesterday relative to today," once per
  /// calendar day the app is opened — a multi-day gap only evaluates the
  /// most recent missed day for streak purposes. completionLog itself has
  /// no such gap since it's written directly by toggleComplete /
  /// setCompletionForDate regardless of rollover.
  Future<void> runDailyRollover() async {
    final now = DateTime.now();
    final todayStart = startOfDay(now);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayKey = dateKey(yesterdayStart);

    final streakSnap = await _streakDocRef.get();
    final streakData = streakSnap.data();
    final lastChecked = (streakData?['lastCheckedDate'] as Timestamp?)?.toDate();

    if (lastChecked != null && isSameDay(lastChecked, todayStart)) {
      return; // already ran today
    }

    final snap = await _tasksRef
        .where('dueDate',
            isGreaterThanOrEqualTo: Timestamp.fromDate(yesterdayStart))
        .where('dueDate', isLessThan: Timestamp.fromDate(todayStart))
        .get();

    final tasksDueYesterday = snap.docs.map(Task.fromFirestore).toList();

    if (tasksDueYesterday.isNotEmpty) {
      final allCompleted = tasksDueYesterday.every(
        (t) => t.completionLog[yesterdayKey] ?? t.completed,
      );
      final currentStreak = (streakData?['currentStreak'] as int?) ?? 0;
      final bestStreak = (streakData?['bestStreak'] as int?) ?? 0;
      final newStreak = allCompleted ? currentStreak + 1 : 0;

      await _streakDocRef.set({
        'currentStreak': newStreak,
        'bestStreak': newStreak > bestStreak ? newStreak : bestStreak,
        'lastCheckedDate': Timestamp.fromDate(todayStart),
      }, SetOptions(merge: true));
    } else {
      await _streakDocRef.set({
        'lastCheckedDate': Timestamp.fromDate(todayStart),
      }, SetOptions(merge: true));
    }

    for (final task in tasksDueYesterday) {
      if (task.repeatType == TaskRepeatType.none) continue;

      // Make sure yesterday's result is captured before it resets — if
      // toggleComplete already logged it this is a no-op overwrite with
      // the same value; if it wasn't toggled at all, this records a miss.
      final updatedLog = {
        ...task.completionLog,
        yesterdayKey: task.completionLog[yesterdayKey] ?? task.completed,
      };

      final nextDue = _nextOccurrence(task, from: todayStart);
      await _tasksRef.doc(task.id).update({
        'completed': false,
        'dueDate': Timestamp.fromDate(nextDue),
        'completionLog': updatedLog,
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
      return from;
    }
    for (int offset = 0; offset < 7; offset++) {
      final day = from.add(Duration(days: offset));
      if (task.repeatDays.contains(day.weekday)) {
        return DateTime(day.year, day.month, day.day);
      }
    }
    return from;
  }
}