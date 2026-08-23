import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/notes/brain_dump.dart';
import '../../utils/sanitizer.dart';

class BrainDumpService {
  final String uid;

  BrainDumpService(this.uid);

  CollectionReference<Map<String, dynamic>> get _ref =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('braindump');

  /// Streams all brain dump entries, newest first.
  Stream<List<BrainDump>> watchEntries() {
    return _ref
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => BrainDump.fromFirestore(doc)).toList(),
        );
  }

  /// Adds a new brain dump entry and returns its Firestore id.
  Future<String> addEntry(String rawText) async {
    final text = Sanitizer.sanitize(rawText);
    if (text.isEmpty) return '';
    final doc = await _ref.add({
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Deletes a brain dump entry.
  Future<void> deleteEntry(String entryId) async {
    await _ref.doc(entryId).delete();
  }
}
