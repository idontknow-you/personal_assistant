import 'package:cloud_firestore/cloud_firestore.dart';

class Task {
  final String id;
  final String title;
  final bool completed;
  final Timestamp? createdAt;
  final Timestamp? dueDate;
  final int streak;

  Task({
    required this.id,
    required this.title,
    required this.completed,
    this.createdAt,
    this.dueDate,
    this.streak = 0,
  });

  factory Task.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Task(
      id: doc.id,
      title: data['title'] as String? ?? '',
      completed: data['completed'] as bool? ?? false,
      createdAt: data['createdAt'] as Timestamp?,
      dueDate: data['dueDate'] as Timestamp?,
      streak: data['streak'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'completed': completed,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'dueDate': dueDate,
      'streak': streak,
    };
  }
}