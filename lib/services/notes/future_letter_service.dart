import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/notes/future_letter.dart';

class FutureLetterService {
  final String uid;

  FutureLetterService(this.uid);

  CollectionReference<Map<String, dynamic>> get _lettersRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('future_letters');

  /// Streams all future letters, newest written first.
  Stream<List<FutureLetter>> watchLetters() {
    return _lettersRef
        .orderBy('writtenDate', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => FutureLetter.fromFirestore(doc)).toList(),
        );
  }

  /// Returns letters whose resurface date has passed and haven't been
  /// reflected on yet — i.e. letters that are "ready to open."
  Future<List<FutureLetter>> getDueLetters() async {
    final now = Timestamp.now();
    final snap = await _lettersRef
        .where('reflected', isEqualTo: false)
        .where('resurfaceDate', isLessThanOrEqualTo: now)
        .orderBy('resurfaceDate', descending: false)
        .get();
    return snap.docs.map((doc) => FutureLetter.fromFirestore(doc)).toList();
  }

  /// Adds a new future letter and returns its Firestore id.
  Future<String> addLetter({
    required String content,
    required DateTime resurfaceDate,
  }) async {
    final doc = await _lettersRef.add({
      'content': content,
      'writtenDate': FieldValue.serverTimestamp(),
      'resurfaceDate': Timestamp.fromDate(resurfaceDate),
      'reflection': '',
      'reflected': false,
    });
    return doc.id;
  }

  /// Saves the follow-through reflection and marks the letter as reflected.
  Future<void> addReflection(String letterId, String reflection) async {
    await _lettersRef.doc(letterId).update({
      'reflection': reflection,
      'reflected': true,
    });
  }

  /// Deletes a future letter.
  Future<void> deleteLetter(String letterId) async {
    await _lettersRef.doc(letterId).delete();
  }
}
