import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:alarm/alarm.dart' as alarm_pkg;
import '../models/alarm.dart';

/// Bridges an [AlarmModel] (our Firestore-backed data) to the native
/// `alarm` package (actual scheduling/ringing) and keeps Firestore in sync.
class AlarmService {
  final CollectionReference<Map<String, dynamic>> _alarmsCollection =
      FirebaseFirestore.instance.collection('alarms');

  /// Call once at app startup, before any scheduling happens.
  Future<void> init() => alarm_pkg.Alarm.init();

  // ---------------- Firestore CRUD ----------------

  Future<void> saveAlarm(AlarmModel alarm) async {
    await _alarmsCollection.doc(alarm.id.toString()).set(alarm.toMap());
  }

  Future<void> deleteAlarm(int id) async {
    await alarm_pkg.Alarm.stop(id);
    await _alarmsCollection.doc(id.toString()).delete();
  }

  Stream<List<AlarmModel>> watchAlarms() {
    return _alarmsCollection.snapshots().map(
          (snap) =>
              snap.docs.map((doc) => AlarmModel.fromMap(doc.data())).toList(),
        );
  }

  // ---------------- Scheduling ----------------

  /// Bundled fallback used for [SoundSource.deviceDefault], since the
  /// `alarm` package has no concept of "the phone's built-in alarm tone" —
  /// it only plays an asset/file path, or nothing (silent + vibrate).
  /// TODO: if you later want the *actual* OS default ringtone, that needs
  /// a platform-channel package on top of this one — `alarm` can't do it.
  static const _bundledDefaultSound = 'assets/sounds/default.mp3';

  String? _resolveAssetPath(AlarmModel alarm) {
    switch (alarm.soundSource) {
      case SoundSource.deviceDefault:
        return _bundledDefaultSound;
      case SoundSource.bundled:
      case SoundSource.deviceFile:
        return alarm.soundPath;
    }
  }

  /// Computes the next real DateTime this alarm should fire at.
  DateTime _nextTriggerDate(AlarmModel alarm) {
    final now = DateTime.now();

    if (alarm.type == AlarmType.oneTime) {
      final date = alarm.oneTimeDate!;
      return DateTime(
        date.year, date.month, date.day,
        alarm.hour, alarm.minute,
      );
    }

    // Repeating: walk forward day-by-day (today included) and take the
    // first day that's both in repeatDays AND still in the future.
    if (alarm.repeatDays.isEmpty) {
      throw StateError(
        'Repeating alarm ${alarm.id} has no repeatDays set',
      );
    }

    for (int offset = 0; offset < 7; offset++) {
      final day = now.add(Duration(days: offset));
      final candidate = DateTime(
        day.year, day.month, day.day,
        alarm.hour, alarm.minute,
      );
      if (alarm.repeatDays.contains(candidate.weekday) &&
          candidate.isAfter(now)) {
        return candidate;
      }
    }
    // Unreachable given the isEmpty check above, but keeps the analyzer happy.
    throw StateError('Could not compute next trigger for alarm ${alarm.id}');
  }

  /// Schedules (or reschedules) this alarm with the native plugin.
  /// If the alarm is disabled, it just makes sure nothing's pending instead.
  Future<void> scheduleAlarm(AlarmModel alarm) async {
    if (!alarm.isEnabled) {
      await alarm_pkg.Alarm.stop(alarm.id);
      return;
    }

    final settings = alarm_pkg.AlarmSettings(
      id: alarm.id,
      dateTime: _nextTriggerDate(alarm),
      assetAudioPath: _resolveAssetPath(alarm),
      loopAudio: true,
      vibrate: true,
      warningNotificationOnKill: true,
      androidFullScreenIntent: true,
      volumeSettings: alarm_pkg.VolumeSettings.fade(
        volume: 0.8,
        fadeDuration: const Duration(seconds: 5),
        volumeEnforced: true,
      ),
      notificationSettings: alarm_pkg.NotificationSettings(
        title: alarm.label.isEmpty ? 'Alarm' : alarm.label,
        body: 'Tap to open',
        stopButton: 'Stop',
      ),
    );

    await alarm_pkg.Alarm.set(alarmSettings: settings);
  }

  Future<AlarmModel?> getAlarm(int id) async {
    final doc = await _alarmsCollection.doc(id.toString()).get();
    if (!doc.exists) return null;
    return AlarmModel.fromMap(doc.data()!);
  }

  /// Call this from wherever you handle the ring event (e.g. after
  /// navigating to the ringing screen and the user dismisses it), for
  /// repeating alarms only — one-time alarms should just get disabled
  /// instead, since there's no "next" occurrence.
  Future<void> rescheduleAfterRing(AlarmModel alarm) async {
    if (alarm.type == AlarmType.repeating && alarm.isEnabled) {
      await scheduleAlarm(alarm);
    }
  }

  Future<void> cancelAlarm(int id) => alarm_pkg.Alarm.stop(id);

  /// Convenience: flips isEnabled, persists it, and schedules/cancels
  /// the native alarm to match in one call.
  Future<void> setEnabled(AlarmModel alarm, bool enabled) async {
    final updated = alarm.copyWith(isEnabled: enabled);
    await saveAlarm(updated);
    await scheduleAlarm(updated);
  }
}