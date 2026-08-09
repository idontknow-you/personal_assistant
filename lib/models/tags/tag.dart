import 'package:cloud_firestore/cloud_firestore.dart';

/// A single reusable tag a task can be assigned to. Tasks hold at most one
/// tag (Task.tagId) — tags themselves are a flat list the user builds up
/// over time via TaskFormScreen's inline "+ new tag", not a per-task
/// nested structure.
///
/// Tags no longer carry their own color — since a task can only ever have
/// one tag at a time, per-tag colors added visual noise without conveying
/// real information. Anywhere a tag needs a color in the UI, it uses the
/// active ThemePalette's primary color instead (via
/// Theme.of(context).colorScheme.primary), so tags automatically match
/// whichever preset the user has selected.
class Tag {
  final String id;
  final String name;

  Tag({
    required this.id,
    required this.name,
  });

  factory Tag.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Tag(
      id: doc.id,
      name: data['name'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
      };
}