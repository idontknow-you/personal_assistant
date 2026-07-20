import 'package:cloud_firestore/cloud_firestore.dart';

enum SoundSource { deviceDefault, bundled, deviceFile }

enum AlarmType { oneTime, repeating }

class AlarmModel {
  final int id;
  final String label;
  final int hour;
  final int minute;
  final AlarmType type;
  final Set<int> repeatDays;
  final DateTime? oneTimeDate;
  final bool isEnabled;
  final SoundSource soundSource;
  final String? soundPath;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Firestore doc id of the Task this alarm was created for, if any.
  /// Null for standalone alarms (the normal case).
  final String? linkedTaskId;

  const AlarmModel({
    required this.id,
    required this.label,
    required this.hour,
    required this.minute,
    required this.type,
    this.repeatDays = const {},
    this.oneTimeDate,
    this.isEnabled = true,
    this.soundSource = SoundSource.deviceDefault,
    this.soundPath,
    required this.createdAt,
    required this.updatedAt,
    this.linkedTaskId,
  }) : assert(
         type != AlarmType.oneTime || oneTimeDate != null,
         'AlarmType.oneTime requires oneTimeDate to be set',
       );

  AlarmModel copyWith({
    String? label,
    int? hour,
    int? minute,
    AlarmType? type,
    Set<int>? repeatDays,
    DateTime? oneTimeDate,
    bool clearOneTimeDate = false,
    bool? isEnabled,
    SoundSource? soundSource,
    String? soundPath,
    bool clearSoundPath = false,
    DateTime? updatedAt,
    String? linkedTaskId,
    bool clearLinkedTaskId = false,
  }) {
    assert(
      !(oneTimeDate != null && clearOneTimeDate),
      'Pass either oneTimeDate or clearOneTimeDate: true, not both',
    );
    assert(
      !(soundPath != null && clearSoundPath),
      'Pass either soundPath or clearSoundPath: true, not both',
    );
    assert(
      !(linkedTaskId != null && clearLinkedTaskId),
      'Pass either linkedTaskId or clearLinkedTaskId: true, not both',
    );

    return AlarmModel(
      id: id,
      label: label ?? this.label,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      type: type ?? this.type,
      repeatDays: repeatDays ?? this.repeatDays,
      oneTimeDate:
          clearOneTimeDate ? null : (oneTimeDate ?? this.oneTimeDate),
      isEnabled: isEnabled ?? this.isEnabled,
      soundSource: soundSource ?? this.soundSource,
      soundPath: clearSoundPath ? null : (soundPath ?? this.soundPath),
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      linkedTaskId:
          clearLinkedTaskId ? null : (linkedTaskId ?? this.linkedTaskId),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'label': label,
      'hour': hour,
      'minute': minute,
      'type': type.name,
      'repeatDays': repeatDays.toList(),
      'oneTimeDate':
          oneTimeDate == null ? null : Timestamp.fromDate(oneTimeDate!),
      'isEnabled': isEnabled,
      'soundSource': soundSource.name,
      'soundPath': soundPath,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'linkedTaskId': linkedTaskId,
    };
  }

  factory AlarmModel.fromMap(Map<String, dynamic> map) {
    return AlarmModel(
      id: map['id'] as int,
      label: map['label'] as String,
      hour: map['hour'] as int,
      minute: map['minute'] as int,
      type: AlarmType.values.byName(map['type'] as String),
      repeatDays: Set<int>.from(map['repeatDays'] as List? ?? []),
      oneTimeDate: (map['oneTimeDate'] as Timestamp?)?.toDate(),
      isEnabled: map['isEnabled'] as bool? ?? true,
      soundSource: SoundSource.values.byName(
        map['soundSource'] as String? ?? SoundSource.deviceDefault.name,
      ),
      soundPath: map['soundPath'] as String?,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: (map['updatedAt'] as Timestamp).toDate(),
      linkedTaskId: map['linkedTaskId'] as String?,
    );
  }

  factory AlarmModel.fromDoc(DocumentSnapshot doc) {
    return AlarmModel.fromMap(doc.data() as Map<String, dynamic>);
  }
}