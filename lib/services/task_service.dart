import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/task.dart';

class TaskService {
  final String uid;
  TaskService(this.uid);

  CollectionReference<Map<String, dynamic>> get _tasksRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('tasks');

  Stream<List<Task>> watchTasks() {
    return _tasksRef
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Task.fromFirestore).toList());
  }

  Future<void> addTask(String title) async {
    if (title.trim().isEmpty) return;
    await _tasksRef.add({
      'title': title.trim(),
      'completed': false,
      'createdAt': FieldValue.serverTimestamp(),
      'dueDate': null,
      'streak': 0,
    });
  }

  Future<void> toggleComplete(String taskId, bool current) async {
    await _tasksRef.doc(taskId).update({'completed': !current});
  }

  Future<void> deleteTask(String taskId) async {
    await _tasksRef.doc(taskId).delete();
  }
}