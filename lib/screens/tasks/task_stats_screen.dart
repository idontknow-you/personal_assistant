import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';
import '../../models/tags/tag.dart';
import '../../services/tasks/task_service.dart';
import '../../services/tags/tag_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/task_stats.dart';
import '../../widgets/tasks/completion_heatmap.dart';

class TaskStatsScreen extends StatelessWidget {
  const TaskStatsScreen({
    super.key,
    required this.taskService,
    required this.tagService,
  });

  final TaskService taskService;
  final TagService tagService;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: StreamBuilder<List<Task>>(
        stream: taskService.watchTasks(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final tasks = snapshot.data ?? [];
          final stats = TaskStats.compute(tasks);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _RateCard(label: 'Last 7 days', rate: stats.last7DaysRate),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _RateCard(label: 'Last 30 days', rate: stats.last30DaysRate),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Activity', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CompletionHeatmap(byDate: stats.byDate),
                ),
              ),
              const SizedBox(height: 24),
              Text('Pending by priority', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _StatBarRow(
                        label: 'High',
                        count: stats.pendingHigh,
                        total: stats.totalPending,
                        color: AppColors.priorityHigh,
                      ),
                      const SizedBox(height: 8),
                      _StatBarRow(
                        label: 'Medium',
                        count: stats.pendingMedium,
                        total: stats.totalPending,
                        color: AppColors.priorityMedium,
                      ),
                      const SizedBox(height: 8),
                      _StatBarRow(
                        label: 'Low',
                        count: stats.pendingLow,
                        total: stats.totalPending,
                        color: AppColors.priorityLow,
                      ),
                    ],
                  ),
                ),
              ),
              // Only shown once there's at least one pending tagged (or
              // untagged) task to report — an empty section here would
              // just be dead space for anyone who hasn't used tags yet.
              if (stats.pendingByTag.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Pending by tag', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: StreamBuilder<List<Tag>>(
                      stream: tagService.watchTags(),
                      builder: (context, tagSnapshot) {
                        final tags = tagSnapshot.data ?? [];
                        final tagsById = {for (final t in tags) t.id: t};

                        // Sorted by count descending so the busiest tags
                        // surface first; untagged ('') always sorts last
                        // regardless of count, since it's the "leftover"
                        // bucket rather than a real tag someone chose.
                        final entries = stats.pendingByTag.entries.toList()
                          ..sort((a, b) {
                            if (a.key.isEmpty) return 1;
                            if (b.key.isEmpty) return -1;
                            return b.value.compareTo(a.value);
                          });

                        return Column(
                          children: [
                            for (int i = 0; i < entries.length; i++) ...[
                              if (i > 0) const SizedBox(height: 8),
                              _StatBarRow(
                                label: entries[i].key.isEmpty
                                    ? 'No tag'
                                    : (tagsById[entries[i].key]?.name ??
                                        'Deleted tag'),
                                count: entries[i].value,
                                total: stats.totalPending,
                                color: entries[i].key.isEmpty
                                    ? AppColors.skip
                                    : (tagsById[entries[i].key]?.color ??
                                        AppColors.skip),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({required this.label, required this.rate});

  final String label;
  final double rate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
            const SizedBox(height: 4),
            Text(
              '${(rate * 100).round()}%',
              style: theme.textTheme.headlineMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// A single labeled progress bar with a trailing count — used for both
/// the priority breakdown and the tag breakdown, since the two are
/// visually identical aside from label/color/count. Was named
/// _PriorityRow before tags existed; renamed since it's genuinely generic.
class _StatBarRow extends StatelessWidget {
  const _StatBarRow({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : count / total;
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.15),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 24,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}