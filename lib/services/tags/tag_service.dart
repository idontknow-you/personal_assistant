import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/tags/tag.dart';

class TagService {
  final String uid;

  TagService(this.uid);

  CollectionReference<Map<String, dynamic>> get _tagsRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('tags');

  CollectionReference<Map<String, dynamic>> get _tasksRef => FirebaseFirestore
      .instance
      .collection('users')
      .doc(uid)
      .collection('tasks');

  Stream<List<Tag>> watchTags() {
    return _tagsRef
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs.map(Tag.fromFirestore).toList());
  }

  /// Creates a new tag, or returns the id of an existing one if [name]
  /// already matches (case-insensitive) — so the inline "+ new tag" flow
  /// in TaskFormScreen can't create duplicate tags if the user types a
  /// name that's already in the list. [existingTags] is passed in rather
  /// than queried here since the caller already has it from watchTags().
  Future<String> addTag(String name, List<Tag> existingTags) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '';

    final match = existingTags.where(
      (t) => t.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (match.isNotEmpty) return match.first.id;

    final doc = await _tagsRef.add({'name': trimmed});
    return doc.id;
  }

  /// Renames an existing tag. Same duplicate-name guard as addTag: if
  /// [newName] already matches another existing tag (case-insensitive),
  /// this is a no-op rather than creating a naming collision.
  /// [existingTags] is passed in the same way as addTag, for the same
  /// reason.
  Future<void> updateTagName(
    String tagId,
    String newName,
    List<Tag> existingTags,
  ) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return;

    final collision = existingTags.any(
      (t) => t.id != tagId && t.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (collision) return;

    await _tagsRef.doc(tagId).update({'name': trimmed});
  }

  /// Deletes the tag and unassigns it (Task.tagId -> null) from every
  /// task currently using it. Deliberately never touches the tasks
  /// themselves beyond that one field — cleaning up your tag list should
  /// never delete or hide a task, only clear the now-dangling reference.
  Future<void> deleteTag(String tagId) async {
    final snap = await _tasksRef.where('tagId', isEqualTo: tagId).get();
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'tagId': null});
    }
    batch.delete(_tagsRef.doc(tagId));
    await batch.commit();
  }
}