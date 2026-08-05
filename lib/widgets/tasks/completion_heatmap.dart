import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/date_utils.dart';
import '../../utils/task_stats.dart';

/// GitHub-style contribution heatmap. Weeks run left (oldest) to right
/// (most recent), Monday at the top of each column. Cell color intensity
/// = fraction of tracked tasks completed that day (DayStat.rate).
///
/// NOTE: a day with zero tracked tasks and a day where everything was
/// tracked-but-missed both render as the lightest shade — there's no
/// separate "no data" color yet. Fine for now; revisit if it's confusing
/// once there's real history to look at.
class CompletionHeatmap extends StatelessWidget {
  const CompletionHeatmap({super.key, required this.byDate, this.days = 84});

  final Map<String, DayStat> byDate;
  final int days;

  static const _cellSize = 12.0;
  static const _cellGap = 3.0;

  Color _colorFor(DayStat? stat) {
    if (stat == null || stat.loggedCount == 0) return AppColors.heatmapScale[0];
    final index = (stat.rate * (AppColors.heatmapScale.length - 1)).round();
    return AppColors.heatmapScale[index.clamp(0, AppColors.heatmapScale.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    final today = startOfDay(DateTime.now());
    final ascendingDays = List.generate(
      days,
      (i) => today.subtract(Duration(days: days - 1 - i)),
    );

    // Pad the front so the first real day lands on its correct weekday row
    // (Monday = row 0 ... Sunday = row 6), same convention as
    // Task.repeatDays / AlarmModel.repeatDays.
    final padding = ascendingDays.first.weekday - 1;
    final paddedDays = <DateTime?>[
      for (int i = 0; i < padding; i++) null,
      ...ascendingDays,
    ];

    final weeks = <List<DateTime?>>[];
    for (int i = 0; i < paddedDays.length; i += 7) {
      final end = (i + 7 > paddedDays.length) ? paddedDays.length : i + 7;
      weeks.add(paddedDays.sublist(i, end));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true, // start scrolled to the most recent week
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: weeks.map((week) {
              return Padding(
                padding: const EdgeInsets.only(right: _cellGap),
                child: Column(
                  children: List.generate(7, (rowIndex) {
                    final day = rowIndex < week.length ? week[rowIndex] : null;
                    final stat = day == null ? null : byDate[dateKey(day)];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: _cellGap),
                      child: Tooltip(
                        message: day == null
                            ? ''
                            : '${day.day}/${day.month}: '
                                '${stat?.completedCount ?? 0}/${stat?.loggedCount ?? 0} done',
                        child: Container(
                          width: _cellSize,
                          height: _cellSize,
                          decoration: BoxDecoration(
                            color: day == null ? Colors.transparent : _colorFor(stat),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Less', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 4),
            ...AppColors.heatmapScale.map(
              (c) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: _cellSize,
                  height: _cellSize,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text('More', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ],
    );
  }
}