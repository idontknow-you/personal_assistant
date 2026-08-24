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
          final totalTasks = tasks.length;
          final completedTasks = stats.totalCompleted;
          final pendingTasks = stats.totalPending;
          final overallRate = totalTasks == 0 ? 0.0 : completedTasks / totalTasks;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _SummaryHero(
                total: totalTasks, completed: completedTasks,
                pending: pendingTasks, overallRate: overallRate,
              ),
              const SizedBox(height: 20),
              Text('Completion Rate', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _RateCard(label: 'Last 7 days', rate: stats.last7DaysRate, icon: Icons.wb_sunny_outlined)),
                  const SizedBox(width: 12),
                  Expanded(child: _RateCard(label: 'Last 30 days', rate: stats.last30DaysRate, icon: Icons.date_range_outlined)),
                ],
              ),
              const SizedBox(height: 24),
              Text('Activity', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Card(child: Padding(padding: const EdgeInsets.all(16), child: CompletionHeatmap(byDate: stats.byDate))),
              const SizedBox(height: 24),
              Text('Pending by Priority', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _PriorityRow(label: 'High', count: stats.pendingHigh, total: stats.totalPending, color: AppColors.priorityHigh, icon: Icons.flag),
                      const SizedBox(height: 12),
                      _PriorityRow(label: 'Medium', count: stats.pendingMedium, total: stats.totalPending, color: AppColors.priorityMedium, icon: Icons.flag_outlined),
                      const SizedBox(height: 12),
                      _PriorityRow(label: 'Low', count: stats.pendingLow, total: stats.totalPending, color: AppColors.priorityLow, icon: Icons.outlined_flag),
                    ],
                  ),
                ),
              ),
              if (stats.pendingByTag.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Pending by Tag', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: StreamBuilder<List<Tag>>(
                      stream: tagService.watchTags(),
                      builder: (context, tagSnapshot) {
                        final tags = tagSnapshot.data ?? [];
                        final tagsById = {for (final t in tags) t.id: t};
                        final tagColor = Theme.of(context).colorScheme.primary;
                        final entries = stats.pendingByTag.entries.toList()
                          ..sort((a, b) {
                            if (a.key.isEmpty) return 1;
                            if (b.key.isEmpty) return -1;
                            return b.value.compareTo(a.value);
                          });
                        return Column(
                          children: [
                            for (int i = 0; i < entries.length; i++) ...[
                              if (i > 0) const SizedBox(height: 12),
                              _PriorityRow(
                                label: entries[i].key.isEmpty ? 'No tag' : (tagsById[entries[i].key]?.name ?? 'Deleted'),
                                count: entries[i].value, total: stats.totalPending,
                                color: entries[i].key.isEmpty ? AppColors.skip : tagColor,
                                icon: entries[i].key.isEmpty ? Icons.label_off_outlined : Icons.label_outlined,
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

class _SummaryHero extends StatelessWidget {
  const _SummaryHero({required this.total, required this.completed, required this.pending, required this.overallRate});
  final int total, completed, pending;
  final double overallRate;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pct = (overallRate * 100).round();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [cs.primaryContainer, cs.primaryContainer.withValues(alpha: 0.5)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              SizedBox(
                width: 80, height: 80,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(width: 80, height: 80, child: CircularProgressIndicator(value: overallRate, strokeWidth: 8, backgroundColor: cs.onPrimaryContainer.withValues(alpha: 0.12), valueColor: AlwaysStoppedAnimation(cs.primary))),
                    Text('$pct%', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Overall Completion', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onPrimaryContainer.withValues(alpha: 0.7))),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _MiniStat(label: 'Total', value: '$total', color: cs.onPrimaryContainer),
                        const SizedBox(width: 16),
                        _MiniStat(label: 'Done', value: '$completed', color: Colors.green.shade700),
                        const SizedBox(width: 16),
                        _MiniStat(label: 'Pending', value: '$pending', color: Colors.orange.shade700),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, required this.color});
  final String label, value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: color)),
        Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: color.withValues(alpha: 0.7))),
      ],
    );
  }
}

class _RateCard extends StatelessWidget {
  const _RateCard({required this.label, required this.rate, required this.icon});
  final String label;
  final double rate;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pct = (rate * 100).round();
    final Color c = rate >= 0.8 ? Colors.green : rate >= 0.5 ? Colors.orange : cs.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              Icon(icon, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: 56, height: 56,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(width: 56, height: 56, child: CircularProgressIndicator(value: rate, strokeWidth: 6, backgroundColor: c.withValues(alpha: 0.12), valueColor: AlwaysStoppedAnimation(c))),
                  Text('$pct%', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: c)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({required this.label, required this.count, required this.total, required this.color, required this.icon});
  final String label;
  final int count, total;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final f = total == 0 ? 0.0 : count / total;
    final t = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        SizedBox(width: 72, child: Text(label, overflow: TextOverflow.ellipsis, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500))),
        const SizedBox(width: 8),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: f, minHeight: 10, backgroundColor: color.withValues(alpha: 0.12), valueColor: AlwaysStoppedAnimation(color)))),
        const SizedBox(width: 12),
        SizedBox(width: 28, child: Text('$count', textAlign: TextAlign.right, style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
      ],
    );
  }
}