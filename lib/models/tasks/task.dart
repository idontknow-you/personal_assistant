import 'package:cloud_firestore/cloud_firestore.dart';

enum TaskRepeatType { none, daily, weekly }

enum Priority { low, medium, high }

class Subtask {
  final String id;
  final String title;
  final bool isCompleted;

  Subtask({
    required this.id,
    required this.title,
    this.isCompleted = false,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'isCompleted': isCompleted,
      };

  factory Subtask.fromMap(Map<String, dynamic> map) => Subtask(
        id: map['id'] as String? ?? '',
        title: map['title'] as String? ?? '',
        isCompleted: map['isCompleted'] as bool? ?? false,
      );

  Subtask copyWith({String? title, bool? isCompleted}) => Subtask(
        id: id,
        title: title ?? this.title,
        isCompleted: isCompleted ?? this.isCompleted,
      );
}

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

  final Priority priority;

  final List<Subtask> subtasks;

  /// Free-text notes about the task. Optional — defaults to empty string,
  /// not null, so UI code can bind it straight to a TextEditingController
  /// without null-checking everywhere.
  final String notes;

  /// Per-day completion history, keyed by "yyyy-MM-dd" (see date_utils.dart).
  /// This is the source of truth for streaks/heatmap/stats — [completed]
  /// only reflects the *current* period and gets reset by rollover, but
  /// entries here persist. Also what makes backdating possible: marking a
  /// past date done writes here without touching [completed] or [dueDate]
  /// unless that date is the task's current active period.
  final Map<String, bool> completionLog;

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
    this.priority = Priority.low,
    this.subtasks = const [],
    this.notes = '',
    this.completionLog = const {},
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
      // Defensive: old docs written before this field existed won't have
      // it, so fall back to low rather than throwing on an unknown name.
      priority: Priority.values.firstWhere(
        (p) => p.name == data['priority'],
        orElse: () => Priority.low,
      ),
      subtasks: (data['subtasks'] as List<dynamic>? ?? [])
          .map((s) => Subtask.fromMap(Map<String, dynamic>.from(s as Map)))
          .toList(),
      // Defensive default for old docs written before this field existed.
      notes: data['notes'] as String? ?? '',
      completionLog: Map<String, bool>.from(
        (data['completionLog'] as Map<dynamic, dynamic>? ?? {}),
      ),
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
      'priority': priority.name,
      'subtasks': subtasks.map((s) => s.toMap()).toList(),
      'notes': notes,
      'completionLog': completionLog,
    };
  }

  /// Note on nullable-field clearing: [dueDate] and [linkedAlarmId] can't be
  /// cleared via `dueDate: null` / `linkedAlarmId: null` — same reasoning as
  /// AlarmModel.copyWith. Use the `clear*` flags to actually null them out.
  /// [notes] doesn't need a clear flag since it's a non-nullable String —
  /// pass `notes: ''` to clear it.
  Task copyWith({
    String? title,
    bool? completed,
    Timestamp? dueDate,
    bool clearDueDate = false,
    TaskRepeatType? repeatType,
    Set<int>? repeatDays,
    int? linkedAlarmId,
    bool clearLinkedAlarmId = false,
    Priority? priority,
    List<Subtask>? subtasks,
    String? notes,
    Map<String, bool>? completionLog,
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
      priority: priority ?? this.priority,
      subtasks: subtasks ?? this.subtasks,
      notes: notes ?? this.notes,
      completionLog: completionLog ?? this.completionLog,
    );
  }
}