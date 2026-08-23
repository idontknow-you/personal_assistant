import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:alarm/alarm.dart' as alarm_pkg;
import '../../models/notes/future_letter.dart';

class FutureLetterService {
  final String uid;

  FutureLetterService(this.uid);

  CollectionReference<Map<String, dynamic>> get _lettersRef =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('future_letters');

  /// Streams all future letters, newest written first.
  Stream<List<FutureLetter>> watchLetters() {
    return _lettersRef
        .orderBy('writtenDate', descending: true)
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => FutureLetter.fromFirestore(doc)).toList(),
        );
  }

  /// Returns letters whose resurface date has passed and haven't been
  /// reflected on yet — i.e. letters that are "ready to open."
  Future<List<FutureLetter>> getDueLetters() async {
    final now = Timestamp.now();
    final snap = await _lettersRef
        .where('reflected', isEqualTo: false)
        .where('resurfaceDate', isLessThanOrEqualTo: now)
        .orderBy('resurfaceDate', descending: false)
        .get();
    return snap.docs.map((doc) => FutureLetter.fromFirestore(doc)).toList();
  }

  /// Adds a new future letter, schedules a notification, and returns its
  /// Firestore id.
  Future<String> addLetter({
    required String content,
    required DateTime resurfaceDate,
  }) async {
    final doc = await _lettersRef.add({
      'content': content,
      'writtenDate': FieldValue.serverTimestamp(),
      'resurfaceDate': Timestamp.fromDate(resurfaceDate),
      'reflection': '',
      'reflected': false,
    });

    // Schedule a local notification for the resurface date
    await _scheduleNotification(doc.id, content, resurfaceDate);

    return doc.id;
  }

  /// Saves the follow-through reflection and marks the letter as reflected.
  /// Also cancels any pending notification.
  Future<void> addReflection(String letterId, String reflection) async {
    await _lettersRef.doc(letterId).update({
      'reflection': reflection,
      'reflected': true,
    });
    await _cancelNotification(letterId);
  }

  /// Deletes a future letter and cancels its notification.
  Future<void> deleteLetter(String letterId) async {
    await _lettersRef.doc(letterId).delete();
    await _cancelNotification(letterId);
  }

  // --- Notification scheduling ---

  /// Generate a stable notification ID from a letter ID.
  /// Uses a hash so different letters always get different IDs.
  int _notificationId(String letterId) {
    // Use a simple hash — abs(hashCode) to ensure positive,
    // mod by 900M to avoid collision with alarm IDs (which use small ints).
    return letterId.hashCode.abs() % 900000000 + 100000000;
  }

  /// Schedule a notification when the letter should resurface.
  Future<void> _scheduleNotification(
    String letterId,
    String content,
    DateTime resurfaceDate,
  ) async {
    // Don't schedule if the date is in the past
    if (resurfaceDate.isBefore(DateTime.now())) return;

    final id = _notificationId(letterId);

    // Truncate content for the notification body
    final preview = content.length > 80
        ? '${content.substring(0, 80)}...'
        : content;

    await alarm_pkg.Alarm.set(
      alarmSettings: alarm_pkg.AlarmSettings(
        id: id,
        dateTime: resurfaceDate,
        assetAudioPath: 'assets/sounds/default.mp3',
        loopAudio: false,
        vibrate: true,
        warningNotificationOnKill: true,
        androidFullScreenIntent: false,
        volumeSettings: alarm_pkg.VolumeSettings.fixed(volume: 0.7),
        notificationSettings: alarm_pkg.NotificationSettings(
          title: '📬 Letter from Past You',
          body: preview,
          stopButton: 'Open',
        ),
      ),
    );
  }

  /// Cancel a scheduled notification for a letter.
  Future<void> _cancelNotification(String letterId) async {
    final id = _notificationId(letterId);
    await alarm_pkg.Alarm.stop(id);
  }
}
