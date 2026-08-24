import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Executes function calls from the AI chat in local Firestore.
///
/// When Gemini responds with `functionCalls`, the chat screen passes them
/// here. Each call writes directly to the user's Firestore collections,
/// then returns the result so Gemini can confirm naturally.
class ChatActionHandler {
  static String get _uid => FirebaseAuth.instance.currentUser!.uid;

  static CollectionReference<Map<String, dynamic>> _col(String name) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection(name);

  /// Execute a list of function calls and return results for each.
  static Future<List<Map<String, dynamic>>> executeAll(
      List<Map<String, dynamic>> calls) async {
    final results = <Map<String, dynamic>>[];
    for (final call in calls) {
      final name = call['name'] as String;
      final args = (call['args'] as Map<String, dynamic>?) ?? {};
      final result = await _execute(name, args);
      results.add({'name': name, 'result': result});
    }
    return results;
  }

  static Future<Map<String, dynamic>> _execute(
      String name, Map<String, dynamic> args) async {
    switch (name) {
      case 'create_task':
        return _createTask(args);
      case 'complete_task':
        return _completeTask(args);
      case 'create_alarm':
        return _createAlarm(args);
      case 'create_habit':
        return _createHabit(args);
      case 'add_note':
        return _addNote(args);
      case 'add_braindump':
        return _addBraindump(args);
      case 'add_dsa_problem':
        return _addDsaProblem(args);
      case 'list_tasks':
        return _listTasks();
      case 'list_habits':
        return _listHabits();
      case 'list_alarms':
        return _listAlarms();
      case 'list_notes':
        return _listNotes(args);
      case 'list_braindump':
        return _listBraindump(args);
      case 'list_dsa_problems':
        return _listDsaProblems();
      default:
        return {'error': 'Unknown function: $name'};
    }
  }

  // ---------------------------------------------------------------------------
  // Task functions
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _createTask(
      Map<String, dynamic> args) async {
    final title = args['title'] as String? ?? '';
    if (title.isEmpty) return {'error': 'title is required'};

    final now = DateTime.now();
    DateTime? dueDate;
    if (args['due_date'] != null) {
      dueDate = DateTime.tryParse(args['due_date'].toString());
    }
    dueDate ??= now;

    final repeat = args['repeat'] as String? ?? 'none';
    final priority = args['priority'] as String? ?? 'low';
    final notes = args['notes'] as String? ?? '';

    final doc = await _col('tasks').add({
      'title': title,
      'completed': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'dueDate': Timestamp.fromDate(dueDate),
      'repeatType': repeat,
      'repeatDays': <int>[],
      'linkedAlarmId': null,
      'priority': priority,
      'subtasks': <Map<String, dynamic>>[],
      'notes': notes,
      'commitmentText': '',
      'tagId': null,
      'completionLog': <String, bool>{},
    });

    return {
      'success': true,
      'taskId': doc.id,
      'title': title,
      'dueDate': dueDate.toIso8601String(),
      'priority': priority,
    };
  }

  static Future<Map<String, dynamic>> _completeTask(
      Map<String, dynamic> args) async {
    final taskId = args['task_id'] as String? ?? '';
    final completed = args['completed'] as bool? ?? true;

    if (taskId.isEmpty) return {'error': 'task_id is required'};

    await _col('tasks').doc(taskId).update({
      'completed': completed,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return {'success': true, 'taskId': taskId, 'completed': completed};
  }

  // ---------------------------------------------------------------------------
  // Alarm functions
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _createAlarm(
      Map<String, dynamic> args) async {
    final label = args['label'] as String? ?? 'Alarm';
    final hour = args['hour'] as int? ?? 8;
    final minute = args['minute'] as int? ?? 0;
    final repeatDaysRaw = args['repeat_days'] as List<dynamic>? ?? [];
    final repeatDays = repeatDaysRaw.map((e) => e as int).toList();

    final isOneTime = repeatDays.isEmpty;
    final now = DateTime.now();

    // Generate a unique ID based on timestamp
    final id = DateTime.now().millisecondsSinceEpoch % 2147483647;

    final alarmData = <String, dynamic>{
      'id': id,
      'label': label,
      'hour': hour,
      'minute': minute,
      'isEnabled': true,
      'type': isOneTime ? 'oneTime' : 'repeating',
      'repeatDays': repeatDays,
      'tone': 'default',
      'soundSource': 'deviceDefault',
      'soundPath': null,
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (isOneTime) {
      // Default to today, or the provided date
      DateTime date = now;
      if (args['one_time_date'] != null) {
        date = DateTime.tryParse(args['one_time_date'].toString()) ?? now;
      }
      alarmData['oneTimeDate'] = Timestamp.fromDate(
        DateTime(date.year, date.month, date.day),
      );
    } else {
      alarmData['oneTimeDate'] = null;
    }

    await _col('alarms').doc(id.toString()).set(alarmData);

    return {
      'success': true,
      'alarmId': id,
      'label': label,
      'hour': hour,
      'minute': minute,
      'type': isOneTime ? 'one-time' : 'repeating',
    };
  }

  // ---------------------------------------------------------------------------
  // Habit functions
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _createHabit(
      Map<String, dynamic> args) async {
    final name = args['name'] as String? ?? '';
    if (name.isEmpty) return {'error': 'name is required'};

    final frequencyRaw = args['frequency'] as List<dynamic>? ?? [];
    final frequency = frequencyRaw.map((e) => e as int).toList();

    final doc = await _col('habits').add({
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'frequency': frequency,
      'restDays': <int>[],
      'log': <String, String>{},
      'currentStreak': 0,
      'bestStreak': 0,
    });

    return {
      'success': true,
      'habitId': doc.id,
      'name': name,
      'frequency': frequency,
    };
  }

  // ---------------------------------------------------------------------------
  // Note functions
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _addNote(
      Map<String, dynamic> args) async {
    final title = args['title'] as String? ?? '';
    final content = args['content'] as String? ?? '';
    if (title.isEmpty) return {'error': 'title is required'};

    final doc = await _col('notes').add({
      'title': title,
      'content': content,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'mood': null,
      'tags': <String>[],
    });

    return {
      'success': true,
      'noteId': doc.id,
      'title': title,
    };
  }

  // ---------------------------------------------------------------------------
  // Brain dump
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _addBraindump(
      Map<String, dynamic> args) async {
    final text = args['text'] as String? ?? '';
    if (text.isEmpty) return {'error': 'text is required'};

    final doc = await _col('braindump').add({
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });

    return {
      'success': true,
      'entryId': doc.id,
      'text': text.length > 60 ? '${text.substring(0, 60)}...' : text,
    };
  }

  // ---------------------------------------------------------------------------
  // DSA problems
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _addDsaProblem(
      Map<String, dynamic> args) async {
    final name = args['name'] as String? ?? '';
    if (name.isEmpty) return {'error': 'name is required'};

    final link = args['link'] as String?;
    final now = DateTime.now();
    final nextReview = now.add(const Duration(days: 1));

    final doc = await _col('dsa_problems').add({
      'name': name,
      'link': link,
      'solvedDate': Timestamp.fromDate(now),
      'nextReviewDate': Timestamp.fromDate(nextReview),
      'intervalDays': 1,
      'easeFactor': 2.5,
      'reviewCount': 0,
    });

    return {
      'success': true,
      'problemId': doc.id,
      'name': name,
    };
  }

  // ---------------------------------------------------------------------------
  // List functions
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _listTasks() async {
    final snap = await _col('tasks')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    final tasks = snap.docs.map((doc) {
      final d = doc.data();
      return {
        'id': doc.id,
        'title': d['title'],
        'completed': d['completed'],
        'dueDate': (d['dueDate'] as Timestamp?)?.toDate().toIso8601String(),
        'priority': d['priority'],
      };
    }).toList();
    return {'tasks': tasks, 'count': tasks.length};
  }

  static Future<Map<String, dynamic>> _listHabits() async {
    final snap = await _col('habits')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    final habits = snap.docs.map((doc) {
      final d = doc.data();
      return {
        'id': doc.id,
        'name': d['name'],
        'currentStreak': d['currentStreak'],
        'bestStreak': d['bestStreak'],
      };
    }).toList();
    return {'habits': habits, 'count': habits.length};
  }

  static Future<Map<String, dynamic>> _listAlarms() async {
    final snap = await _col('alarms')
        .orderBy('createdAt', descending: true)
        .limit(20)
        .get();
    final alarms = snap.docs.map((doc) {
      final d = doc.data();
      return {
        'id': d['id'],
        'label': d['label'],
        'hour': d['hour'],
        'minute': d['minute'],
        'isEnabled': d['isEnabled'],
        'type': d['type'],
      };
    }).toList();
    return {'alarms': alarms, 'count': alarms.length};
  }

  // ---------------------------------------------------------------------------
  // Note / Brain dump / DSA list functions
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> _listNotes(
      Map<String, dynamic> args) async {
    final limit = (args['limit'] as int?) ?? 10;
    final snap = await _col('notes')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    final notes = snap.docs.map((doc) {
      final d = doc.data();
      final content = d['content'] as String? ?? '';
      return {
        'id': doc.id,
        'title': d['title'],
        'mood': d['mood'],
        'content': content.length > 200 ? '${content.substring(0, 200)}...' : content,
        'date': (d['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
      };
    }).toList();
    return {'notes': notes, 'count': notes.length};
  }

  static Future<Map<String, dynamic>> _listBraindump(
      Map<String, dynamic> args) async {
    final limit = (args['limit'] as int?) ?? 10;
    final snap = await _col('braindump')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    final entries = snap.docs.map((doc) {
      final d = doc.data();
      return {
        'id': doc.id,
        'text': d['text'],
        'category': d['category'],
        'date': (d['createdAt'] as Timestamp?)?.toDate().toIso8601String(),
      };
    }).toList();
    return {'entries': entries, 'count': entries.length};
  }

  static Future<Map<String, dynamic>> _listDsaProblems() async {
    final snap = await _col('dsa_problems')
        .orderBy('nextReviewDate', descending: false)
        .limit(20)
        .get();
    final problems = snap.docs.map((doc) {
      final d = doc.data();
      final nextReview = (d['nextReviewDate'] as Timestamp?)?.toDate();
      final isDue = nextReview != null && nextReview.isBefore(DateTime.now());
      return {
        'id': doc.id,
        'name': d['name'],
        'reviewCount': d['reviewCount'],
        'intervalDays': d['intervalDays'],
        'nextReview': nextReview?.toIso8601String(),
        'isDueForReview': isDue,
      };
    }).toList();
    return {'problems': problems, 'count': problems.length};
  }
}
