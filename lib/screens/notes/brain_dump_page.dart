import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/notes/brain_dump.dart';
import '../../models/tasks/task.dart';
import '../../models/alarms/alarm.dart' as alarm_model;
import '../../services/notes/brain_dump_service.dart';
import '../../services/notes/note_service.dart';
import '../../services/tasks/task_service.dart';
import '../../services/dsa/dsa_problem_service.dart';
import '../../services/api/api_service.dart';
import '../../main.dart' show alarmService;
import 'brain_dump_capture_sheet.dart';

/// Standalone brain dump page — lives in its own bottom nav tab.
class BrainDumpPage extends StatefulWidget {
  final BrainDumpService brainDumpService;
  final VoidCallback? onMenuPressed;

  const BrainDumpPage({super.key, required this.brainDumpService, this.onMenuPressed});

  @override
  State<BrainDumpPage> createState() => _BrainDumpPageState();
}

class _BrainDumpPageState extends State<BrainDumpPage> {
  bool _autoSorting = false;

  Future<void> _confirmDeleteDump(BrainDump entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This brain dump entry will be permanently deleted.'),
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
      await widget.brainDumpService.deleteEntry(entry.id);
    }
  }

  Future<void> _applyAutoSort(
      List<Map<String, dynamic>> results, List<BrainDump> entries) async {
    final uid = widget.brainDumpService.uid;
    // Pass alarmService through so a task created here can get a real,
    // scheduled linked alarm — not just a Firestore field.
    final taskService = TaskService(uid, alarmService: alarmService);
    final noteService = NoteService(uid);
    final dsaService = DSAProblemService(uid);

    int created = 0;
    for (final r in results) {
      final category = r['category'] as String? ?? 'braindump';
      final title = r['title'] as String? ?? '';
      final text = r['text'] as String? ?? '';
      final extraNotes = (r['notes'] as String?)?.trim() ?? '';
      final dueDateStr = r['dueDate'] as String?;
      final alarmHour = r['alarmHour'] as int?;
      final alarmMinute = r['alarmMinute'] as int?;
      final subtaskTitles = (r['subtasks'] as List<dynamic>?)
              ?.map((s) => s.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList() ??
          const <String>[];

      final dueDate =
          (dueDateStr != null && dueDateStr.isNotEmpty)
              ? DateTime.tryParse(dueDateStr)
              : null;

      switch (category) {
        case 'task':
          final taskTitle = title.isNotEmpty ? title : text;
          final subtasks = subtaskTitles
              .map((s) => Subtask(
                    id: '${DateTime.now().microsecondsSinceEpoch}_${s.hashCode}',
                    title: s,
                  ))
              .toList();

          final taskId = await taskService.addTask(
            taskTitle,
            dueDate: dueDate != null ? Timestamp.fromDate(dueDate) : null,
            subtasks: subtasks,
            // If nothing extra was extracted and it wasn't split into
            // subtasks, keep the original dump text as the task's notes
            // so no detail from a longer entry gets lost.
            notes: extraNotes.isNotEmpty
                ? extraNotes
                : (subtasks.isEmpty ? text : ''),
          );

          // A time was extracted ("...9pm") — create a real linked alarm,
          // the same way the task form screen does, so it actually rings.
          if (alarmHour != null &&
              alarmMinute != null &&
              taskId.isNotEmpty) {
            final alarmDay = dueDate ?? DateTime.now();
            final now = DateTime.now();
            final alarmId = now.millisecondsSinceEpoch ~/ 1000;
            final alarm = alarm_model.AlarmModel(
              id: alarmId,
              label: taskTitle,
              hour: alarmHour,
              minute: alarmMinute,
              type: alarm_model.AlarmType.oneTime,
              oneTimeDate:
                  DateTime(alarmDay.year, alarmDay.month, alarmDay.day),
              isEnabled: true,
              createdAt: now,
              updatedAt: now,
              linkedTaskId: taskId,
            );
            await alarmService.saveAlarm(alarm);
            await taskService.setLinkedAlarm(taskId, alarmId);
          }
          created++;
          break;
        case 'note':
        case 'diary':
          await noteService.addNote(
            title: title.isNotEmpty ? title : text,
            // Prefer the model's full extracted body over the raw text
            // when it gave us one, so nothing from a long dump is lost.
            content: extraNotes.isNotEmpty ? extraNotes : text,
          );
          created++;
          break;
        case 'dsa':
          await dsaService.addProblem(name: title.isNotEmpty ? title : text);
          created++;
          break;
        default:
          // braindump and people stay as brain dump entries
          break;
      }
    }

    // Delete all original brain dump entries
    for (final entry in entries) {
      await widget.brainDumpService.deleteEntry(entry.id);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sorted! Created $created items, cleared ${entries.length} brain dumps.'),
        ),
      );
    }
  }

  Future<void> _autoSortEntries() async {
    final entries = await widget.brainDumpService.watchEntries().first;
    if (entries.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No brain dump entries to sort.')),
        );
      }
      return;
    }

    setState(() => _autoSorting = true);

    try {
      final texts = entries.map((e) => e.text).toList();
      final results = await ApiService.autoSort(texts);

      if (!mounted) return;

      if (results == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Auto-sort failed. Check your internet connection and try again.')),
        );
        return;
      }

      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Auto-sort Results'),
          content: SizedBox(
            width: double.maxFinite,
            height: MediaQuery.of(ctx).size.height * 0.5,
            child: ListView.builder(
              itemCount: results.length,
              itemBuilder: (ctx, i) {
                final r = results[i];
                final category = r['category'] ?? 'braindump';
                final title = r['title'] ?? r['text']?.toString().substring(0, 60) ?? '';
                final categoryIcons = {
                  'task': Icons.check_circle_outline,
                  'note': Icons.note_outlined,
                  'diary': Icons.book_outlined,
                  'dsa': Icons.school_outlined,
                  'people': Icons.person_outline,
                  'braindump': Icons.psychology_outlined,
                };

                // Build a short "what we extracted" line so the user can
                // sanity-check the AI's parse before accepting.
                final details = <String>[category.toString().toUpperCase()];
                final dueDateStr = r['dueDate'] as String?;
                if (dueDateStr != null && dueDateStr.isNotEmpty) {
                  final parsed = DateTime.tryParse(dueDateStr);
                  if (parsed != null) {
                    details.add('Due ${DateFormat.MMMd().format(parsed)}');
                  }
                }
                final alarmHour = r['alarmHour'] as int?;
                final alarmMinute = r['alarmMinute'] as int?;
                if (alarmHour != null && alarmMinute != null) {
                  final t = TimeOfDay(hour: alarmHour, minute: alarmMinute);
                  details.add('Alarm ${t.format(ctx)}');
                }
                final subtaskCount =
                    (r['subtasks'] as List<dynamic>?)?.length ?? 0;
                if (subtaskCount > 0) {
                  details.add('$subtaskCount subtasks');
                }

                return ListTile(
                  leading: Icon(categoryIcons[category] ?? Icons.help_outline),
                  title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    details.join(' · '),
                    style: Theme.of(ctx).textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep in Dump'),
            ),
            FilledButton(                  onPressed: () async {
                Navigator.pop(ctx);
                await _applyAutoSort(results, entries);
              },
              child: const Text('Accept & Clear'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Something went wrong with auto-sort. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _autoSorting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onMenuPressed != null
            ? IconButton(
                icon: const Icon(Icons.menu),
                tooltip: 'Menu',
                onPressed: widget.onMenuPressed,
              )
            : null,
        title: const Text('Brain Dump'),
        actions: [
          if (_autoSorting)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.auto_fix_high),
              tooltip: 'Auto-sort with AI',
              onPressed: _autoSortEntries,
            ),
        ],
      ),
      body: StreamBuilder<List<BrainDump>>(
        stream: widget.brainDumpService.watchEntries(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final entries = snapshot.data ?? [];

          if (entries.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.psychology_outlined,
                        size: 56,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      'Nothing here yet.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Tap the button below to dump\na thought, idea, or reminder.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 96,
            ),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final dateStr =
                  DateFormat.yMMMd().add_jm().format(entry.createdAt.toDate());

              return Dismissible(
                key: ValueKey(entry.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Theme.of(context).colorScheme.errorContainer,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Icon(
                    Icons.delete_outline,
                    color:
                        Theme.of(context).colorScheme.onErrorContainer,
                  ),
                ),
                confirmDismiss: (_) async {
                  await _confirmDeleteDump(entry);
                  return false;
                },
                child: ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: Text(
                    entry.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    dateStr,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showBrainDumpSheet(context, widget.brainDumpService),
        tooltip: 'Brain dump',
        icon: const Icon(Icons.psychology),
        label: const Text('Dump'),
      ),
    );
  }
}