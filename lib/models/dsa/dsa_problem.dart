import 'package:cloud_firestore/cloud_firestore.dart';

/// SM-2 spaced repetition for DSA problems. Tracks when a problem was solved,
/// how well it's remembered, and when it should next be reviewed.
class DSAProblem {
  final String id;
  final String name;
  final String? link; // optional LeetCode/URL
  final Timestamp solvedDate;
  final Timestamp nextReviewDate;
  final int intervalDays; // current interval in days
  final double easeFactor; // SM-2 ease factor (default 2.5)
  final int reviewCount; // how many times reviewed

  const DSAProblem({
    required this.id,
    required this.name,
    this.link,
    required this.solvedDate,
    required this.nextReviewDate,
    this.intervalDays = 1,
    this.easeFactor = 2.5,
    this.reviewCount = 0,
  });

  factory DSAProblem.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return DSAProblem(
      id: doc.id,
      name: data['name'] as String? ?? '',
      link: data['link'] as String?,
      solvedDate: data['solvedDate'] as Timestamp? ?? Timestamp.now(),
      nextReviewDate: data['nextReviewDate'] as Timestamp? ?? Timestamp.now(),
      intervalDays: data['intervalDays'] as int? ?? 1,
      easeFactor: (data['easeFactor'] as num?)?.toDouble() ?? 2.5,
      reviewCount: data['reviewCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'link': link,
      'solvedDate': solvedDate,
      'nextReviewDate': nextReviewDate,
      'intervalDays': intervalDays,
      'easeFactor': easeFactor,
      'reviewCount': reviewCount,
    };
  }

  /// Whether this problem is due for review now.
  bool get isDue => nextReviewDate.toDate().isBefore(DateTime.now());

  /// How many days until next review (negative = overdue).
  int get daysUntilReview {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final review = nextReviewDate.toDate();
    final reviewDay = DateTime(review.year, review.month, review.day);
    return reviewDay.difference(today).inDays;
  }

  /// Apply SM-2 algorithm after a review. [quality] is 0-5:
  /// 0 = complete blackout, 1 = wrong, 2 = wrong but remembered after hint,
  /// 3 = correct with difficulty, 4 = correct with hesitation, 5 = perfect.
  DSAProblem review(int quality) {
    assert(quality >= 0 && quality <= 5);

    double ef = easeFactor + (0.1 - (5 - quality) * (0.08 + (5 - quality) * 0.02));
    if (ef < 1.3) ef = 1.3;

    int newInterval;
    if (quality < 3) {
      // Failed — reset to 1 day
      newInterval = 1;
    } else {
      if (reviewCount == 0) {
        newInterval = 1;
      } else if (reviewCount == 1) {
        newInterval = 3;
      } else {
        newInterval = (intervalDays * ef).round();
      }
    }

    final nextDate = DateTime.now().add(Duration(days: newInterval));

    return DSAProblem(
      id: id,
      name: name,
      link: link,
      solvedDate: solvedDate,
      nextReviewDate: Timestamp.fromDate(nextDate),
      intervalDays: newInterval,
      easeFactor: ef,
      reviewCount: reviewCount + 1,
    );
  }

  DSAProblem copyWith({
    String? name,
    String? link,
    bool clearLink = false,
  }) {
    return DSAProblem(
      id: id,
      name: name ?? this.name,
      link: clearLink ? null : (link ?? this.link),
      solvedDate: solvedDate,
      nextReviewDate: nextReviewDate,
      intervalDays: intervalDays,
      easeFactor: easeFactor,
      reviewCount: reviewCount,
    );
  }
}
