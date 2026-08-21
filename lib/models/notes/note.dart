import 'package:cloud_firestore/cloud_firestore.dart';

/// Mood tags for diary entries — each has an emoji and associated color.
enum Mood {
  happy('😊', 0xFFFFCA28),    // amber
  sad('😢', 0xFF42A5F5),      // blue
  neutral('😐', 0xFFBDBDBD),  // grey
  anxious('😰', 0xFFFF7043),  // deep orange
  excited('🎉', 0xFFAB47BC),  // purple
  calm('😌', 0xFF66BB6A),     // green
  angry('😠', 0xFFEF5350),    // red
  grateful('🙏', 0xFF8D6E63); // brown

  const Mood(this.emoji, this.colorValue);
  final String emoji;
  final int colorValue;
}

class Note {
  final String id;
  final String title;
  final String content;
  final Mood? mood;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const Note({
    required this.id,
    required this.title,
    this.content = '',
    this.mood,
    this.createdAt,
    this.updatedAt,
  });

  factory Note.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Note(
      id: doc.id,
      title: data['title'] as String? ?? '',
      content: data['content'] as String? ?? '',
      mood: data['mood'] != null
          ? Mood.values.firstWhere(
              (m) => m.name == data['mood'],
              orElse: () => Mood.neutral,
            )
          : null,
      createdAt: data['createdAt'] as Timestamp?,
      updatedAt: data['updatedAt'] as Timestamp?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'content': content,
      'mood': mood?.name,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Note copyWith({
    String? title,
    String? content,
    Mood? mood,
    bool clearMood = false,
  }) {
    return Note(
      id: id,
      title: title ?? this.title,
      content: content ?? this.content,
      mood: clearMood ? null : (mood ?? this.mood),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
