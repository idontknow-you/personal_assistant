import 'package:cloud_firestore/cloud_firestore.dart';

/// Stores and streams the user's preferred name ("what should we call
/// you?"), scoped to their account at users/{uid}/meta/profile — so it's
/// tied to whichever auth method they use (email, Google, anonymous).
class ProfileService {
  final String uid;

  ProfileService(this.uid);

  DocumentReference<Map<String, dynamic>> get _profileDoc =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('meta')
          .doc('profile');

  /// Streams the stored name, emitting '' when unset. Empty on error too,
  /// so UI can bind it straight to a TextField/Text without null checks.
  Stream<String> watchName() {
    return _profileDoc.snapshots().map(
          (doc) => ((doc.data()?['name'] as String?) ?? '').trim(),
        );
  }

  /// One-shot read of the stored name. Returns '' on error or if unset.
  Future<String> getName() async {
    try {
      final doc = await _profileDoc.get();
      return ((doc.data()?['name'] as String?) ?? '').trim();
    } catch (_) {
      return '';
    }
  }

  /// Saves the preferred name. Empty input effectively clears it.
  Future<void> setName(String name) async {
    await _profileDoc.set(
      {
        'name': name.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
