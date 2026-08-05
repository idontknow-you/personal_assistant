import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-day status for a habit's log entry, keyed by dateKey().
/// - done: completed that day, counts toward streak.
/// - skipped: intentionally not done (e.g. sick, travel) — carries the
///   streak forward instead of breaking it.
/// - missed: not done, no excuse — breaks the streak.
enum HabitDayStatus { done, skipped, missed }

class Habit {
  final String id;
  final String name;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  /// Weekdays (1 = Monday ... 7 = Sunday) this habit is expected on.
  /// Empty set = expected every day. Same weekday convention as
  /// Task.repeatDays / AlarmModel.repeatDays.
  final Set<int> frequency;

  /// Weekdays explicitly treated as rest days — excluded from streak
  /// calculation entirely (not expected, not counted as missed) even if
  /// they'd otherwise match [frequency]. Lets you e.g. do a habit daily
  /// but always take Sundays off without it looking like a miss.
  final Set<int> restDays;

  /// Per-day log, keyed by "yyyy-MM-dd" (dateKey()), values are
  /// HabitDayStatus.name strings ('done' / 'skipped' / 'missed').
  /// A day with no entry at all is "unmarked" — only treated as a miss
  /// once it's in the past.
  final Map<String, String> log;

  final int currentStreak;
  final int bestStreak;

  Habit({
    required this.id,
    required this.name,
    this.createdAt,
    this.updatedAt,
    this.frequency = const {},
    this.restDays = const {},
    this.log = const {},
    this.currentStreak = 0,
    this.bestStreak = 0,
  });

  /// Convenience getter for a given day's status, null if unmarked.
  HabitDayStatus? statusOn(String key) {
    final raw = log[key];
    if (raw == null) return null;
    return HabitDayStatus.values.firstWhere(
      (s) => s.name == raw,
      orElse: () => HabitDayStatus.missed,
    );
  }

  bool isExpectedOn(int weekday) {
    if (restDays.contains(weekday)) return false;
    if (frequency.isEmpty) return true;
    return frequency.contains(weekday);
  }

  factory Habit.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Habit(
      id: doc.id,
      name: data['name'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
      frequency: Set<int>.from(data['frequency'] as List? ?? []),
      restDays: Set<int>.from(data['restDays'] as List? ?? []),
      log: Map<String, String>.from(
        (data['log'] as Map<dynamic, dynamic>? ?? {}),
      ),
      currentStreak: data['currentStreak'] as int? ?? 0,
      bestStreak: data['bestStreak'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'frequency': frequency.toList(),
      'restDays': restDays.toList(),
      'log': log,
      'currentStreak': currentStreak,
      'bestStreak': bestStreak,
    };
  }

  Habit copyWith({
    String? name,
    Set<int>? frequency,
    Set<int>? restDays,
    Map<String, String>? log,
    int? currentStreak,
    int? bestStreak,
  }) {
    return Habit(
      id: id,
      name: name ?? this.name,
      createdAt: createdAt,
      updatedAt: updatedAt,
      frequency: frequency ?? this.frequency,
      restDays: restDays ?? this.restDays,
      log: log ?? this.log,
      currentStreak: currentStreak ?? this.currentStreak,
      bestStreak: bestStreak ?? this.bestStreak,
    );
  }
}