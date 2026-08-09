import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/tags/tag.dart';
import '../../theme/app_theme.dart';

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

  /// A new tag's color is derived deterministically from its name (hashed
  /// into AppColors.tagPalette) rather than tracked/incremented via an
  /// extra read, so tag creation stays a single write. Sourced from the
  /// app's own palette (theme/app_theme.dart) rather than a list defined
  /// here, so tag colors are drawn from the same brand hues as the rest
  /// of the app instead of an unrelated rainbow.
  String _colorForName(String name) {
    final palette = AppColors.tagPalette;
    final index = name.trim().toLowerCase().hashCode.abs() % palette.length;
    final color = palette[index];
    final hex = color.value.toRadixString(16).padLeft(8, '0');
    return '#${hex.substring(2).toUpperCase()}';
  }

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

    final doc = await _tagsRef.add({
      'name': trimmed,
      'colorHex': _colorForName(trimmed),
    });
    return doc.id;
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
