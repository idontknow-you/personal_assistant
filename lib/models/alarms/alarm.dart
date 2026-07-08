import 'package:cloud_firestore/cloud_firestore.dart';

/// Where an alarm's sound comes from.
/// - [deviceDefault]: use the phone's built-in default alarm sound (soundPath is null)
/// - [bundled]: one of the sounds shipped inside the app (soundPath is an asset path,
///   e.g. 'assets/sounds/classic.mp3')
/// - [deviceFile]: a file the user picked from their phone (soundPath is an absolute
///   file path, e.g. '/storage/emulated/0/Download/wake_up.mp3')
enum SoundSource { deviceDefault, bundled, deviceFile }

enum AlarmType { oneTime, repeating }

class AlarmModel {
  /// Used both as the Firestore document ID and the native alarm ID
  /// passed to the `alarm` package. Must be a positive int (package requirement).
  final int id;

  final String label;

  /// 24-hour time. We store hour/minute separately (not a full DateTime)
  /// because repeating alarms recompute their next actual trigger date
  /// each time they're (re)scheduled.
  final int hour;
  final int minute;

  final AlarmType type;

  /// Only meaningful when [type] is [AlarmType.repeating].
  /// Uses DateTime weekday values: 1 = Monday ... 7 = Sunday.
  final Set<int> repeatDays;

  /// Only meaningful when [type] is [AlarmType.oneTime]. The specific
  /// calendar date this alarm should fire on (combined with [hour]/[minute]).
  /// Required for one-time alarms since "7:00 AM" alone doesn't say *which*
  /// day — only repeating alarms can rely on hour/minute + weekday alone.
  ///
  /// NOTE: this field only carries the year/month/day. Time-of-day always
  /// comes from [hour]/[minute] — if [oneTimeDate] happens to have a
  /// non-midnight time component (e.g. from DateTime.now()), it should be
  /// ignored by any code that builds the actual trigger DateTime. Consider
  /// only ever constructing this with DateTime(year, month, day) at call
  /// sites to avoid ambiguity.
  final DateTime? oneTimeDate;

  final bool isEnabled;

  final SoundSource soundSource;

  /// See [SoundSource] docs above for what this holds in each case.
  /// Null when [soundSource] is [SoundSource.deviceDefault].
  final String? soundPath;

  final DateTime createdAt;
  final DateTime updatedAt;

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
  }) : assert(
         type != AlarmType.oneTime || oneTimeDate != null,
         'AlarmType.oneTime requires oneTimeDate to be set',
       );

  /// Note on nullable-field clearing: [oneTimeDate] and [soundPath] can't be
  /// cleared via `oneTimeDate: null` / `soundPath: null` — Dart can't tell
  /// "pass null" apart from "didn't pass anything" through a normal named
  /// param, so `?? this.field` would just keep the old value either way.
  /// Use [clearOneTimeDate] / [clearSoundPath] instead when you need to
  /// actually null them out (e.g. switching type from oneTime -> repeating,
  /// or switching soundSource to deviceDefault).
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
  }) {
    assert(
      !(oneTimeDate != null && clearOneTimeDate),
      'Pass either oneTimeDate or clearOneTimeDate: true, not both',
    );
    assert(
      !(soundPath != null && clearSoundPath),
      'Pass either soundPath or clearSoundPath: true, not both',
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
    );
  }

  factory AlarmModel.fromDoc(DocumentSnapshot doc) {
    return AlarmModel.fromMap(doc.data() as Map<String, dynamic>);
  }
}