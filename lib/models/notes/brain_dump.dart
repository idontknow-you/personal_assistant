import 'package:cloud_firestore/cloud_firestore.dart';

/// A raw, uncategorized thought captured in the brain dump inbox.
/// Phase 4 will add AI auto-sort into tasks/notes/people/DSA. For now it's a
/// simple text + timestamp store.
class BrainDump {
  final String id;
  final String text;
  final Timestamp createdAt;

  const BrainDump({
    required this.id,
    required this.text,
    required this.createdAt,
  });

  factory BrainDump.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return BrainDump(
      id: doc.id,
      text: data['text'] as String? ?? '',
      createdAt: data['createdAt'] as Timestamp? ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
