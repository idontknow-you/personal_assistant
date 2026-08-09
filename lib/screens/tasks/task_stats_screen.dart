import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';
import '../../services/tasks/task_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/task_stats.dart';
import '../../widgets/tasks/completion_heatmap.dart';

class TaskStatsScreen extends StatelessWidget {
  const TaskStatsScreen({super.key, required this.taskService});

  final TaskService taskService;

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
                      _PriorityRow(
                        label: 'High',
                        count: stats.pendingHigh,
                        total: stats.totalPending,
                        color: AppColors.priorityHigh,
                      ),
                      const SizedBox(height: 8),
                      _PriorityRow(
                        label: 'Medium',
                        count: stats.pendingMedium,
                        total: stats.totalPending,
                        color: AppColors.priorityMedium,
                      ),
                      const SizedBox(height: 8),
                      _PriorityRow(
                        label: 'Low',
                        count: stats.pendingLow,
                        total: stats.totalPending,
                        color: AppColors.priorityLow,
                      ),
                    ],
                  ),
                ),
              ),
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

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({
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
          width: 60,
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
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