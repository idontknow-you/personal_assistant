import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskRepeatType { none, daily, weekly }

class Task {
  final String id;
  final String title;
  final bool completed;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  /// For non-repeating tasks: the one-off due date.
  /// For repeating tasks: the due date of the *current* period only —
  /// this gets advanced forward each time TaskService.runDailyRollover()
  /// processes it, rather than a new Task doc being created per occurrence.
  final Timestamp? dueDate;

  final TaskRepeatType repeatType;

  /// Only meaningful when repeatType == weekly. Uses DateTime weekday
  /// values: 1 = Monday ... 7 = Sunday. Same convention as
  /// AlarmModel.repeatDays, so the two can share a set directly when a
  /// repeating task's linked alarm is created.
  final Set<int> repeatDays;

  /// Native alarm id (int, matches AlarmModel.id) of the reminder alarm
  /// linked to this task, if the user set one. Null = no reminder.
  final int? linkedAlarmId;

  Task({
    required this.id,
    required this.title,
    required this.completed,
    this.createdAt,
    this.updatedAt,
    this.dueDate,
    this.repeatType = TaskRepeatType.none,
    this.repeatDays = const {},
    this.linkedAlarmId,
  });

  factory Task.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Task(
      id: doc.id,
      title: data['title'] as String? ?? '',
      completed: data['completed'] as bool? ?? false,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
      dueDate: data['dueDate'] as Timestamp?,
      repeatType: TaskRepeatType.values.byName(
        data['repeatType'] as String? ?? TaskRepeatType.none.name,
      ),
      repeatDays: Set<int>.from(data['repeatDays'] as List? ?? []),
      linkedAlarmId: data['linkedAlarmId'] as int?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'completed': completed,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'dueDate': dueDate,
      'repeatType': repeatType.name,
      'repeatDays': repeatDays.toList(),
      'linkedAlarmId': linkedAlarmId,
    };
  }

  /// Note on nullable-field clearing: [dueDate] and [linkedAlarmId] can't be
  /// cleared via `dueDate: null` / `linkedAlarmId: null` — same reasoning as
  /// AlarmModel.copyWith. Use the `clear*` flags to actually null them out.
  Task copyWith({
    String? title,
    bool? completed,
    Timestamp? dueDate,
    bool clearDueDate = false,
    TaskRepeatType? repeatType,
    Set<int>? repeatDays,
    int? linkedAlarmId,
    bool clearLinkedAlarmId = false,
  }) {
    assert(
      !(dueDate != null && clearDueDate),
      'Pass either dueDate or clearDueDate: true, not both',
    );
    assert(
      !(linkedAlarmId != null && clearLinkedAlarmId),
      'Pass either linkedAlarmId or clearLinkedAlarmId: true, not both',
    );

    return Task(
      id: id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
      createdAt: createdAt,
      updatedAt: updatedAt,
      dueDate: clearDueDate ? null : (dueDate ?? this.dueDate),
      repeatType: repeatType ?? this.repeatType,
      repeatDays: repeatDays ?? this.repeatDays,
      linkedAlarmId:
          clearLinkedAlarmId ? null : (linkedAlarmId ?? this.linkedAlarmId),
    );
  }
}