import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/habits/habit.dart';
import '../../utils/date_utils.dart';

class HabitService {
  final String uid;

  HabitService(this.uid);

  CollectionReference<Map<String, dynamic>> get _habitsRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('habits');

  Stream<List<Habit>> watchHabits() {
    return _habitsRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Habit.fromFirestore).toList());
  }

  Future<String> addHabit(
    String name, {
    Set<int> frequency = const {},
    Set<int> restDays = const {},
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';
    final doc = await _habitsRef.add({
      'name': trimmed,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'frequency': frequency.toList(),
      'restDays': restDays.toList(),
      'log': <String, String>{},
      'currentStreak': 0,
      'bestStreak': 0,
    });
    return doc.id;
  }

  Future<void> updateHabit(Habit habit) async {
    await _habitsRef.doc(habit.id).update(habit.toMap());
  }

  Future<void> deleteHabit(Habit habit) async {
    await _habitsRef.doc(habit.id).delete();
  }

  /// Sets (or clears, if [status] is null) the log entry for [date] and
  /// recomputes both streak fields off the updated log. This is what tile
  /// tap-to-cycle and any backdating UI should call — streaks never drift
  /// out of sync with the log because they're always derived fresh here
  /// rather than incremented/decremented by hand.
  Future<void> setStatusForDate(
    Habit habit,
    DateTime date,
    HabitDayStatus? status,
  ) async {
    final key = dateKey(date);
    final updatedLog = {...habit.log};
    if (status == null) {
      updatedLog.remove(key);
    } else {
      updatedLog[key] = status.name;
    }

    final updatedHabit = habit.copyWith(log: updatedLog);
    final newCurrent = _computeCurrentStreak(updatedHabit);
    final newBest = newCurrent > habit.bestStreak ? newCurrent : habit.bestStreak;

    await _habitsRef.doc(habit.id).update({
      'log': updatedLog,
      'currentStreak': newCurrent,
      'bestStreak': newBest,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Cycles a day's status in the order: unmarked -> done -> skipped ->
  /// missed -> unmarked. Used by HabitTile's tap-to-cycle dots.
  Future<void> cycleStatus(Habit habit, DateTime date) async {
    final key = dateKey(date);
    final current = habit.statusOn(key);
    HabitDayStatus? next;
    if (current == null) {
      next = HabitDayStatus.done;
    } else if (current == HabitDayStatus.done) {
      next = HabitDayStatus.skipped;
    } else if (current == HabitDayStatus.skipped) {
      next = HabitDayStatus.missed;
    } else {
      next = null; // missed -> back to unmarked
    }
    await setStatusForDate(habit, date, next);
  }

  /// Walks backward day-by-day from today, computing the current streak:
  /// - Rest days and days outside [Habit.frequency] are skipped over
  ///   entirely — they neither count nor break anything.
  /// - 'done' increments the streak.
  /// - 'skipped' carries the streak forward unchanged (doesn't increment,
  ///   doesn't break).
  /// - 'missed', or an unmarked day that's strictly in the past, breaks
  ///   the streak and stops the walk. An unmarked *today* is left as
  ///   still-in-progress and doesn't break anything, since the day isn't
  ///   over yet.
  /// - The walk stops at (and doesn't go earlier than) the habit's
  ///   createdAt date, so streaks never look backward past when the habit
  ///   started.
  int _computeCurrentStreak(Habit habit) {
    int streak = 0;
    final today = startOfDay(DateTime.now());
    DateTime day = today;
    final createdDay =
        habit.createdAt != null ? startOfDay(habit.createdAt!.toDate()) : null;

    while (createdDay == null || !day.isBefore(createdDay)) {
      if (!habit.isExpectedOn(day.weekday)) {
        day = day.subtract(const Duration(days: 1));
        continue;
      }

      final status = habit.statusOn(dateKey(day));

      if (status == HabitDayStatus.done) {
        streak++;
      } else if (status == HabitDayStatus.skipped) {
        // carries forward — no increment, no break
      } else if (status == HabitDayStatus.missed) {
        break;
      } else {
        // unmarked
        if (!isSameDay(day, today)) break;
        // today, unmarked: still in progress, don't break, don't count
      }

      day = day.subtract(const Duration(days: 1));
    }

    return streak;
  }
}