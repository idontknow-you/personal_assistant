import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/dsa/dsa_problem.dart';
import '../../services/dsa/dsa_problem_service.dart';

class DSAScreen extends StatefulWidget {
  final DSAProblemService problemService;

  const DSAScreen({super.key, required this.problemService});

  @override
  State<DSAScreen> createState() => _DSAScreenState();
}

class _DSAScreenState extends State<DSAScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openAddForm() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _AddProblemScreen(service: widget.problemService)),
    );
  }

  void _startReview(List<DSAProblem> dueProblems) {
    if (dueProblems.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ReviewScreen(
          service: widget.problemService,
          problems: dueProblems,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('DSA Spaced Repetition'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Due for Review'),
            Tab(text: 'All Problems'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _DueTab(
            service: widget.problemService,
            onReview: _startReview,
          ),
          _AllProblemsTab(service: widget.problemService),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddForm,
        tooltip: 'Add problem',
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Due for Review tab
// ---------------------------------------------------------------------------
class _DueTab extends StatelessWidget {
  final DSAProblemService service;
  final void Function(List<DSAProblem>) onReview;

  const _DueTab({required this.service, required this.onReview});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DSAProblem>>(
      stream: service.watchProblems(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final allProblems = snapshot.data ?? [];
        final dueProblems = allProblems.where((p) => p.isDue).toList();

        if (dueProblems.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    'All caught up!',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No problems due for review right now.\nCome back later or add new problems.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return Column(
          children: [
            // Review button banner
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: FilledButton.icon(
                onPressed: () => onReview(dueProblems),
                icon: const Icon(Icons.play_arrow),
                label: Text('Review ${dueProblems.length} problem${dueProblems.length == 1 ? '' : 's'}'),
              ),
            ),
            // Due list
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(top: 8, bottom: 100),
                itemCount: dueProblems.length,
                itemBuilder: (context, index) {
                  final p = dueProblems[index];
                  final overdue = p.daysUntilReview < 0;
                  return ListTile(
                    leading: Icon(
                      Icons.replay,
                      color: overdue
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(
                      p.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      overdue
                          ? '${-p.daysUntilReview} day${-p.daysUntilReview == 1 ? '' : 's'} overdue'
                          : 'Due today',
                      style: TextStyle(
                        color: overdue
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: overdue ? FontWeight.w600 : null,
                      ),
                    ),
                    trailing: p.link != null
                        ? IconButton(
                            icon: const Icon(Icons.open_in_new, size: 20),
                            tooltip: 'Open link',
                            onPressed: () async {
                              final url = Uri.parse(p.link!);
                              if (await canLaunchUrl(url)) {
                                await launchUrl(url, mode: LaunchMode.externalApplication);
                              }
                            },
                          )
                        : null,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// All Problems tab
// ---------------------------------------------------------------------------
class _AllProblemsTab extends StatelessWidget {
  final DSAProblemService service;

  const _AllProblemsTab({required this.service});

  Future<void> _confirmDelete(BuildContext context, DSAProblem problem) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete problem?'),
        content: Text('"${problem.name}" will be permanently deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await service.deleteProblem(problem.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DSAProblem>>(
      stream: service.watchProblems(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final problems = snapshot.data ?? [];
        if (problems.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.school_outlined,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 16),
                  Text(
                    'No problems yet.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Add DSA problems you\'ve solved and\nthe app will resurface them for review.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 100),
          itemCount: problems.length,
          itemBuilder: (context, index) {
            final p = problems[index];
            final nextReview = DateFormat.yMMMd().format(p.nextReviewDate.toDate());
            final isDue = p.isDue;

            return Dismissible(
              key: ValueKey(p.id),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Theme.of(context).colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.onErrorContainer),
              ),
              confirmDismiss: (_) async {
                await _confirmDelete(context, p);
                return false;
              },
              child: ListTile(
                leading: Icon(
                  isDue ? Icons.replay : Icons.check_circle_outline,
                  color: isDue
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.outline,
                ),
                title: Text(
                  p.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Row(
                  children: [
                    Text(
                      isDue ? 'Due now' : 'Next: $nextReview',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDue
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: isDue ? FontWeight.w600 : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '·',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${p.intervalDays}d interval',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (p.reviewCount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '·',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'reviewed ${p.reviewCount}x',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
                trailing: p.link != null
                    ? IconButton(
                        icon: const Icon(Icons.open_in_new, size: 20),
                        tooltip: 'Open link',
                        onPressed: () async {
                          final url = Uri.parse(p.link!);
                          if (await canLaunchUrl(url)) {
                            await launchUrl(url, mode: LaunchMode.externalApplication);
                          }
                        },
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Add Problem form
// ---------------------------------------------------------------------------
class _AddProblemScreen extends StatefulWidget {
  final DSAProblemService service;

  const _AddProblemScreen({required this.service});

  @override
  State<_AddProblemScreen> createState() => _AddProblemScreenState();
}

class _AddProblemScreenState extends State<_AddProblemScreen> {
  final _nameController = TextEditingController();
  final _linkController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  bool get _canSave => _nameController.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (_saving || !_canSave) return;
    HapticFeedback.lightImpact();
    setState(() => _saving = true);

    try {
      await widget.service.addProblem(
        name: _nameController.text.trim(),
        link: _linkController.text.trim().isEmpty
            ? null
            : _linkController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add DSA Problem')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Problem name',
              hintText: 'e.g. Two Sum, LRU Cache',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _linkController,
            decoration: const InputDecoration(
              labelText: 'Link (optional)',
              hintText: 'https://leetcode.com/problems/...',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'The problem will be scheduled for review tomorrow using SM-2 spaced repetition (like Anki).',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _canSave && !_saving ? _save : null,
            child: _saving
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(
                        Theme.of(context).colorScheme.onPrimary,
                      ),
                    ),
                  )
                : const Text('Add Problem'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Review mode — show one problem at a time, rate recall quality
// ---------------------------------------------------------------------------
class _ReviewScreen extends StatefulWidget {
  final DSAProblemService service;
  final List<DSAProblem> problems;

  const _ReviewScreen({required this.service, required this.problems});

  @override
  State<_ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<_ReviewScreen> {
  late final List<DSAProblem> _remaining;
  int _currentIndex = 0;
  bool _showAnswer = false;
  int _reviewed = 0;

  @override
  void initState() {
    super.initState();
    _remaining = List.from(widget.problems);
  }

  void _rate(int quality) async {
    final problem = _remaining[_currentIndex];
    await widget.service.reviewProblem(problem, quality);

    setState(() {
      _reviewed++;
      _remaining.removeAt(_currentIndex);
      _showAnswer = false;
      if (_currentIndex >= _remaining.length && _remaining.isNotEmpty) {
        _currentIndex = _remaining.length - 1;
      }
    });

    if (_remaining.isEmpty && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Done!'),
          content: Text('You reviewed $_reviewed problem${_reviewed == 1 ? '' : 's'}. Great work!'),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx); // close dialog
                Navigator.pop(context); // close review screen
              },
              child: const Text('Back'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_remaining.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final problem = _remaining[_currentIndex];
    final progress = _reviewed / widget.problems.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('${_currentIndex + 1} / ${_remaining.length}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(value: progress),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Problem name
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.school,
                        size: 40,
                        color: Theme.of(context).colorScheme.primary),
                    const SizedBox(height: 16),
                    Text(
                      problem.name,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    if (problem.link != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        problem.link!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      'Solved ${DateFormat.yMMMd().format(problem.solvedDate.toDate())} · '
                      'Interval: ${problem.intervalDays} days · '
                      'Reviewed ${problem.reviewCount}x',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Show answer / rate buttons
            if (!_showAnswer) ...[
              Text(
                'How well do you remember the approach?',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Try to recall the solution pattern before tapping "Show Answer".',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const Spacer(),
              FilledButton(
                onPressed: () => setState(() => _showAnswer = true),
                child: const Text('Show Answer'),
              ),
            ] else ...[
              Text(
                'How did you do?',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // Quality buttons
              _QualityButton(
                label: 'Again',
                subtitle: 'Complete blackout',
                color: Theme.of(context).colorScheme.error,
                icon: Icons.close,
                onTap: () => _rate(0),
              ),
              const SizedBox(height: 8),
              _QualityButton(
                label: 'Hard',
                subtitle: 'Wrong, but remembered after hint',
                color: const Color(0xFFFF6D00),
                icon: Icons.warning_amber,
                onTap: () => _rate(2),
              ),
              const SizedBox(height: 8),
              _QualityButton(
                label: 'Good',
                subtitle: 'Correct with some difficulty',
                color: Theme.of(context).colorScheme.primary,
                icon: Icons.thumb_up,
                onTap: () => _rate(3),
              ),
              const SizedBox(height: 8),
              _QualityButton(
                label: 'Easy',
                subtitle: 'Perfect recall, no hesitation',
                color: Theme.of(context).colorScheme.tertiary,
                icon: Icons.bolt,
                onTap: () => _rate(5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QualityButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;

  const _QualityButton({
    required this.label,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
