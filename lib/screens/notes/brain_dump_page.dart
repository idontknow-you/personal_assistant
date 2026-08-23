import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/notes/brain_dump.dart';
import '../../services/notes/brain_dump_service.dart';
import '../../services/api/api_service.dart';
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
                return ListTile(
                  leading: Icon(categoryIcons[category] ?? Icons.help_outline),
                  title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(category.toUpperCase(),
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
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                for (final entry in entries) {
                  await widget.brainDumpService.deleteEntry(entry.id);
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('${results.length} entries sorted and cleared.'),
                    ),
                  );
                }
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
