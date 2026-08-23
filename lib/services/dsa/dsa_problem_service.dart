import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/dsa/dsa_problem.dart';

class DSAProblemService {
  final String uid;

  DSAProblemService(this.uid);

  CollectionReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('dsa_problems');

  /// Streams all problems, sorted by next review date (most overdue first).
  Stream<List<DSAProblem>> watchProblems() {
    return _ref
        .orderBy('nextReviewDate', descending: false)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => DSAProblem.fromFirestore(doc)).toList(),
        );
  }

  /// Returns problems that are due for review now.
  Future<List<DSAProblem>> getDueProblems() async {
    final now = Timestamp.now();
    final snap = await _ref
        .where('nextReviewDate', isLessThanOrEqualTo: now)
        .orderBy('nextReviewDate', descending: false)
        .get();
    return snap.docs.map((doc) => DSAProblem.fromFirestore(doc)).toList();
  }

  /// Adds a new DSA problem. solvedDate defaults to now.
  Future<String> addProblem({
    required String name,
    String? link,
    DateTime? solvedDate,
  }) async {
    final solved = solvedDate ?? DateTime.now();
    final doc = await _ref.add({
      'name': name,
      'link': link,
      'solvedDate': Timestamp.fromDate(solved),
      'nextReviewDate': Timestamp.fromDate(solved.add(const Duration(days: 1))),
      'intervalDays': 1,
      'easeFactor': 2.5,
      'reviewCount': 0,
    });
    return doc.id;
  }

  /// Records a review and updates the SM-2 schedule.
  Future<void> reviewProblem(DSAProblem problem, int quality) async {
    final updated = problem.review(quality);
    await _ref.doc(problem.id).update(updated.toMap());
  }

  /// Updates problem details (name, link).
  Future<void> updateProblem(DSAProblem problem) async {
    await _ref.doc(problem.id).update(problem.toMap());
  }

  /// Deletes a problem.
  Future<void> deleteProblem(String problemId) async {
    await _ref.doc(problemId).delete();
  }
}
