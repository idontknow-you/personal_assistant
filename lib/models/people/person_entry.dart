import 'package:cloud_firestore/cloud_firestore.dart';

/// A raw input about a person — diary entry, pasted chat, social content, etc.
/// After AI analysis, the analysis fields are populated.
class PersonEntry {
  final String id;
  final String personId;
  final String text;
  final String sourceType; // "diary", "chat", "social", "manual"
  final Timestamp createdAt;

  // AI-generated fields (populated after analysis)
  final String? patterns;
  final String? redFlags;
  final String? emotionalReflection;
  final String? communicationStyle;
  final bool analyzed;

  PersonEntry({
    required this.id,
    required this.personId,
    required this.text,
    this.sourceType = 'manual',
    Timestamp? createdAt,
    this.patterns,
    this.redFlags,
    this.emotionalReflection,
    this.communicationStyle,
    this.analyzed = false,
  }) : createdAt = createdAt ?? Timestamp.now();

  factory PersonEntry.fromDoc(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PersonEntry(
      id: doc.id,
      personId: data['personId'] ?? '',
      text: data['text'] ?? '',
      sourceType: data['sourceType'] ?? 'manual',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      patterns: data['patterns'],
      redFlags: data['redFlags'],
      emotionalReflection: data['emotionalReflection'],
      communicationStyle: data['communicationStyle'],
      analyzed: data['analyzed'] ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'personId': personId,
        'text': text,
        'sourceType': sourceType,
        'createdAt': createdAt,
        'patterns': patterns,
        'redFlags': redFlags,
        'emotionalReflection': emotionalReflection,
        'communicationStyle': communicationStyle,
        'analyzed': analyzed,
      };

  PersonEntry copyWith({
    String? text,
    String? sourceType,
    String? patterns,
    String? redFlags,
    String? emotionalReflection,
    String? communicationStyle,
    bool? analyzed,
  }) =>
      PersonEntry(
        id: id,
        personId: personId,
        text: text ?? this.text,
        sourceType: sourceType ?? this.sourceType,
        createdAt: createdAt,
        patterns: patterns ?? this.patterns,
        redFlags: redFlags ?? this.redFlags,
        emotionalReflection: emotionalReflection ?? this.emotionalReflection,
        communicationStyle: communicationStyle ?? this.communicationStyle,
        analyzed: analyzed ?? this.analyzed,
      );
}
