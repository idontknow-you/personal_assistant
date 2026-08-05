import '../models/tasks/task.dart';
import 'date_utils.dart';

/// Aggregated completion result for a single calendar day, across ALL
/// tasks — used to color one cell of the heatmap.
class DayStat {
  final DateTime date;
  final int completedCount;

  /// How many tasks had ANY completionLog entry for this day (done or not).
  /// A day with loggedCount == 0 means no task was tracked that day —
  /// distinct from a day where everything was tracked and missed.
  final int loggedCount;

  DayStat({
    required this.date,
    required this.completedCount,
    required this.loggedCount,
  });

  double get rate => loggedCount == 0 ? 0 : completedCount / loggedCount;
}

class TaskStats {
  final Map<String, DayStat> byDate;
  final double last7DaysRate;
  final double last30DaysRate;
  final int pendingLow;
  final int pendingMedium;
  final int pendingHigh;
  final int totalPending;
  final int totalCompleted;

  TaskStats({
    required this.byDate,
    required this.last7DaysRate,
    required this.last30DaysRate,
    required this.pendingLow,
    required this.pendingMedium,
    required this.pendingHigh,
    required this.totalPending,
    required this.totalCompleted,
  });

  static TaskStats compute(List<Task> tasks, {int heatmapDays = 84}) {
    final today = startOfDay(DateTime.now());
    final byDate = <String, DayStat>{};

    for (int i = 0; i < heatmapDays; i++) {
      final day = today.subtract(Duration(days: i));
      final key = dateKey(day);
      int completed = 0;
      int logged = 0;
      for (final task in tasks) {
        if (task.completionLog.containsKey(key)) {
          logged++;
          if (task.completionLog[key] == true) completed++;
        }
      }
      byDate[key] = DayStat(date: day, completedCount: completed, loggedCount: logged);
    }

    double rateOver(int days) {
      final relevant = byDate.values.where(
        (d) => today.difference(d.date).inDays < days && d.loggedCount > 0,
      );
      if (relevant.isEmpty) return 0;
      final totalCompleted = relevant.fold<int>(0, (sum, d) => sum + d.completedCount);
      final totalLogged = relevant.fold<int>(0, (sum, d) => sum + d.loggedCount);
      return totalLogged == 0 ? 0 : totalCompleted / totalLogged;
    }

    int low = 0, medium = 0, high = 0, totalCompleted = 0;
    for (final task in tasks) {
      if (task.completed) {
        totalCompleted++;
      } else {
        switch (task.priority) {
          case Priority.low:
            low++;
            break;
          case Priority.medium:
            medium++;
            break;
          case Priority.high:
            high++;
            break;
        }
      }
    }

    return TaskStats(
      byDate: byDate,
      last7DaysRate: rateOver(7),
      last30DaysRate: rateOver(30),
      pendingLow: low,
      pendingMedium: medium,
      pendingHigh: high,
      totalPending: low + medium + high,
      totalCompleted: totalCompleted,
    );
  }
}