import 'package:cloud_firestore/cloud_firestore.dart';

/// A letter written to your future self. It stores the original text, when it
/// was written, when it should resurface, and an optional follow-through
/// reflection that gets filled in once the letter is delivered.
class FutureLetter {
  final String id;
  final String content;
  final Timestamp writtenDate;
  final Timestamp resurfaceDate;
  final String reflection;
  final bool reflected;

  const FutureLetter({
    required this.id,
    required this.content,
    required this.writtenDate,
    required this.resurfaceDate,
    this.reflection = '',
    this.reflected = false,
  });

  factory FutureLetter.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return FutureLetter(
      id: doc.id,
      content: data['content'] as String? ?? '',
      writtenDate: data['writtenDate'] as Timestamp? ?? Timestamp.now(),
      resurfaceDate: data['resurfaceDate'] as Timestamp? ?? Timestamp.now(),
      reflection: data['reflection'] as String? ?? '',
      reflected: data['reflected'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'content': content,
      'writtenDate': writtenDate,
      'resurfaceDate': resurfaceDate,
      'reflection': reflection,
      'reflected': reflected,
    };
  }

  /// Whether the resurface date has passed.
  bool get isReady => !reflected && resurfaceDate.toDate().isBefore(DateTime.now());

  /// Whether the letter has been reflected on.
  bool get isReflected => reflected;

  FutureLetter copyWith({
    String? content,
    Timestamp? resurfaceDate,
    String? reflection,
    bool? reflected,
  }) {
    return FutureLetter(
      id: id,
      content: content ?? this.content,
      writtenDate: writtenDate,
      resurfaceDate: resurfaceDate ?? this.resurfaceDate,
      reflection: reflection ?? this.reflection,
      reflected: reflected ?? this.reflected,
    );
  }
}
