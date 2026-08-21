import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:alarm/alarm.dart' as alarm_pkg;
import '../../models/alarms/alarm.dart';

/// Markers used in a re-ring alarm's notification body so the ring screen
/// can tell what KIND of ring this is, without needing any extra fields
/// on AlarmSettings itself:
///  - missedRetry: the automatic 5-minute retry after a standalone alarm
///    ring timed out unanswered (see AlarmService.scheduleMissedRetry).
///  - escalated(n): rung n of a task-linked reminder's escalating ladder
///    (see AlarmService.scheduleEscalatedRetry). n is 0-based.
///  - snoozed(n): the user tapped Snooze; n is how many times they've
///    snoozed THIS ring cycle so far, so the ring screen can cap it.
/// These are mutually exclusive markers, all stored in the same body
/// field the ring screen doesn't otherwise display.
class AlarmRingMarkers {
  static const missedRetry = '__missed_retry__';

  static const _snoozedPrefix = '__snoozed__:';
  static const _escalatedPrefix = '__escalated__:';

  static String snoozed(int count) => '$_snoozedPrefix$count';

  /// Returns the snooze count encoded in [body], or 0 if this ring isn't
  /// a snoozed one (fresh ring, or a missed-retry/escalated ring).
  static int snoozeCountFrom(String body) {
    if (!body.startsWith(_snoozedPrefix)) return 0;
    return int.tryParse(body.substring(_snoozedPrefix.length)) ?? 0;
  }

  /// Stage marker for a task-linked reminder's escalating retry. Stage 0
  /// is the first rung; the last rung's timeout means "give up".
  static String escalated(int stage) => '$_escalatedPrefix$stage';

  /// Returns the escalation stage encoded in [body], or -1 if this ring
  /// isn't an escalated task-linked retry.
  static int escalationStageFrom(String body) {
    if (!body.startsWith(_escalatedPrefix)) return -1;
    return int.tryParse(body.substring(_escalatedPrefix.length)) ?? -1;
  }
}

/// Bridges an [AlarmModel] (our Firestore-backed data) to the native
/// `alarm` package (actual scheduling/ringing) and keeps Firestore in sync.
class AlarmService {
  /// Alarms live under users/{uid}/alarms — NOT a flat top-level
  /// collection. This matters for two reasons: (1) it's the actual
  /// per-user data isolation fix, and (2) a flat collection was almost
  /// certainly why saves silently failed to "stick" (toggle reverting) —
  /// if Firestore rules only match scoped paths like users/{uid}/*, a
  /// write to a flat `alarms/{id}` path matches no rule and gets denied,
  /// which saveAlarm() was swallowing silently via catchError.
  CollectionReference<Map<String, dynamic>> get _alarmsCollection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      throw StateError('AlarmService used before a user is signed in');
    }
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('alarms');
  }

  /// Call once at app startup, before any scheduling happens.
  Future<void> init() => alarm_pkg.Alarm.init();

  // ---------------- Firestore CRUD ----------------

  /// Persists the alarm to Firestore AND (re)schedules it with the native
  /// plugin, so this is always the single call site that keeps both sides
  /// in sync — callers never need to remember to call scheduleAlarm too.
  Future<void> saveAlarm(AlarmModel alarm) async {
    // .set() updates local cache synchronously; the returned Future only
    // resolves after a server round-trip, which is what was causing the
    // multi-second hang on save. We don't need to wait for that here —
    // listeners (watchAlarms) already see the change from local cache.
    final writeFuture = _alarmsCollection.doc(alarm.id.toString()).set(alarm.toMap());
    writeFuture.catchError((e) {
      // Write failed to eventually sync (e.g. permanently offline, or a
      // rules mismatch). No UI surface for this yet — worth adding a
      // retry/error indicator later if it becomes a real problem. If you
      // see toggles silently reverting again after this change, this is
      // the first place to add a debugPrint(e) to check.
    });

    // This has to be awaited: it's the native scheduling call that actually
    // makes the alarm ring, and it's local (no network), so it's fast.
    await scheduleAlarm(alarm);
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
  /// NOTE: for one-time alarms this just reflects whatever date is
  /// currently stored — it does NOT check if that's in the past. That
  /// check/correction happens in [scheduleAlarm] instead, since only
  /// scheduling (not e.g. display) should mutate the stored date.
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

    var effectiveAlarm = alarm;

    // One-time alarms have no "next occurrence" concept like repeating
    // ones do. If the stored date/time has already passed — e.g. the user
    // re-enables an alarm that already rang, or the app was closed past
    // the trigger time — silently rolling forward to tomorrow (same
    // hour/minute) is safer than handing the native plugin a past
    // DateTime, which can fire immediately or behave unpredictably.
    if (alarm.type == AlarmType.oneTime) {
      final trigger = _nextTriggerDate(alarm);
      if (trigger.isBefore(DateTime.now())) {
        final rolledDate = alarm.oneTimeDate!.add(const Duration(days: 1));
        effectiveAlarm = alarm.copyWith(oneTimeDate: rolledDate);
        // Persist the corrected date directly on the doc (not via
        // saveAlarm, which would call back into scheduleAlarm and recurse).
        //
        // IMPORTANT: use set(..., merge: true) here, NOT update(). The
        // caller (saveAlarm) fires off its own .set() write WITHOUT
        // awaiting it (intentionally, to avoid a multi-second hang), then
        // immediately calls scheduleAlarm — which means this write can
        // reach Firestore before that first .set() has landed. update()
        // requires the document to already exist and throws
        // cloud_firestore/not-found if it doesn't yet; set(merge: true)
        // creates the doc if missing and merges fields if it's already
        // there, so it can't lose this race.
        final updatedMap = effectiveAlarm.toMap();
        await _alarmsCollection.doc(alarm.id.toString()).set(
          {'oneTimeDate': updatedMap['oneTimeDate']},
          SetOptions(merge: true),
        );
      }
    }

    final settings = alarm_pkg.AlarmSettings(
      id: effectiveAlarm.id,
      dateTime: _nextTriggerDate(effectiveAlarm),
      assetAudioPath: _resolveAssetPath(effectiveAlarm),
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
        title: effectiveAlarm.label.isEmpty ? 'Alarm' : effectiveAlarm.label,
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
  }

  // ---------------- Missed-alarm auto-retry ----------------

  /// Escalating reminder ladder for TASK-LINKED reminders only: retries
  /// at 5 min → 15 min → 1 hr, giving up only after the final rung times
  /// out unanswered. Standalone alarms deliberately do NOT use this —
  /// they keep the single 5-minute retry via [scheduleMissedRetry]. The
  /// ring screen picks the path by checking the alarm's linkedTaskId.
  static const escalationIntervals = [
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(hours: 1),
  ];

  /// Schedules rung [stage] (0-based, indexes [escalationIntervals]) of a
  /// task-linked reminder's escalating retry, tagged with
  /// [AlarmRingMarkers.escalated] so the ring screen knows to advance to
  /// the next rung on timeout — or give up if this was the last one.
  Future<void> scheduleEscalatedRetry(
    alarm_pkg.AlarmSettings original,
    int stage,
  ) async {
    final retrySettings = original.copyWith(
      dateTime: DateTime.now().add(escalationIntervals[stage]),
      notificationSettings: alarm_pkg.NotificationSettings(
        title: original.notificationSettings.title,
        body: AlarmRingMarkers.escalated(stage),
        stopButton: original.notificationSettings.stopButton,
      ),
    );
    await alarm_pkg.Alarm.set(alarmSettings: retrySettings);
  }

  /// Called by the ring screen when a STANDALONE alarm (not linked to a
  /// task) has been ringing for the full timeout window with no user
  /// response. Reschedules a one-shot retry 5 minutes later, tagged with
  /// [AlarmRingMarkers.missedRetry] so the ring screen knows to give up
  /// (instead of retrying forever) if this one also times out.
  Future<void> scheduleMissedRetry(alarm_pkg.AlarmSettings original) async {
    final retrySettings = original.copyWith(
      dateTime: DateTime.now().add(const Duration(minutes: 5)),
      notificationSettings: alarm_pkg.NotificationSettings(
        title: original.notificationSettings.title,
        body: AlarmRingMarkers.missedRetry,
        stopButton: original.notificationSettings.stopButton,
      ),
    );
    await alarm_pkg.Alarm.set(alarmSettings: retrySettings);
  }

  /// Fires a short, silent, non-full-screen "you missed this" notification
  /// after both the original ring and its retry have timed out unanswered.
  /// Reuses the same plugin (no extra notification dependency needed) —
  /// it's scheduled ~1s out, doesn't loop, doesn't take over the screen,
  /// and auto-stops itself a few seconds later so it just leaves a
  /// notification behind rather than actually ringing again.
  Future<void> fireMissedNotification(alarm_pkg.AlarmSettings original) async {
    // Offset well clear of any real alarm id range to avoid collisions.
    final missedId = original.id + 900000000;
    await alarm_pkg.Alarm.set(
      alarmSettings: original.copyWith(
        id: missedId,
        dateTime: DateTime.now().add(const Duration(seconds: 1)),
        loopAudio: false,
        vibrate: false,
        androidFullScreenIntent: false,
        volumeSettings: alarm_pkg.VolumeSettings.fixed(volume: 0.0),
        notificationSettings: alarm_pkg.NotificationSettings(
          title: original.notificationSettings.title.isEmpty
              ? 'Missed alarm'
              : 'Missed: ${original.notificationSettings.title}',
          body: "You didn't respond in time.",
          stopButton: 'Dismiss',
        ),
      ),
    );
    Future.delayed(
      const Duration(seconds: 3),
      () => alarm_pkg.Alarm.stop(missedId),
    );
  }
}