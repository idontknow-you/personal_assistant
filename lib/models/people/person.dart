import 'package:cloud_firestore/cloud_firestore.dart';

/// A person the user wants to analyze — tracks patterns, red flags,
/// and communication style over time.
class Person {
  final String id;
  final String name;
  final List<String> tags; // e.g. ["colleague", "family", "friend"]
  final Timestamp createdAt;

  Person({
    required this.id,
    required this.name,
    this.tags = const [],
    Timestamp? createdAt,
  }) : createdAt = createdAt ?? Timestamp.now();

  factory Person.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Person(
      id: doc.id,
      name: data['name'] ?? '',
      tags: List<String>.from(data['tags'] ?? []),
      createdAt: data['createdAt'] ?? Timestamp.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'tags': tags,
        'createdAt': createdAt,
      };

  Person copyWith({
    String? name,
    List<String>? tags,
  }) =>
      Person(
        id: id,
        name: name ?? this.name,
        tags: tags ?? this.tags,
        createdAt: createdAt,
      );
}
