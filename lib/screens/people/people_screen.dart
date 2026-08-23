import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/people/person.dart';
import '../../models/people/person_entry.dart';
import '../../services/people/people_service.dart';
import '../../services/api/api_service.dart';

class PeopleScreen extends StatefulWidget {
  final PeopleService peopleService;

  const PeopleScreen({super.key, required this.peopleService});

  @override
  State<PeopleScreen> createState() => _PeopleScreenState();
}

class _PeopleScreenState extends State<PeopleScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('People')),
      body: StreamBuilder<List<Person>>(
        stream: widget.peopleService.watchPeople(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final people = snapshot.data ?? [];

          if (people.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text('No people yet',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'Add someone you want to understand better.\n'
                      'Feed in diary entries, chat logs, or notes about them.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 80),
            itemCount: people.length,
            itemBuilder: (context, index) {
              final person = people[index];
              return ListTile(
                leading: CircleAvatar(
                  child: Text(
                    person.name.isNotEmpty ? person.name[0].toUpperCase() : '?',
                  ),
                ),
                title: Text(person.name),
                subtitle: person.tags.isNotEmpty
                    ? Text(person.tags.join(', '))
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openPersonDetail(person),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddPersonDialog,
        tooltip: 'Add person',
        child: const Icon(Icons.person_add),
      ),
    );
  }

  void _showAddPersonDialog() {
    final nameController = TextEditingController();
    final tagsController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Person'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: tagsController,
              decoration: const InputDecoration(
                labelText: 'Tags (comma-separated)',
                hintText: 'e.g. colleague, family',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = nameController.text.trim();
              if (name.isEmpty) return;
              final tags = tagsController.text
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty)
                  .toList();
              await widget.peopleService.addPerson(name, tags: tags);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _openPersonDetail(Person person) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _PersonDetailScreen(
        person: person,
        peopleService: widget.peopleService,
      ),
    ));
  }
}

// ── Person Detail Screen ──

class _PersonDetailScreen extends StatefulWidget {
  final Person person;
  final PeopleService peopleService;

  const _PersonDetailScreen({
    required this.person,
    required this.peopleService,
  });

  @override
  State<_PersonDetailScreen> createState() => _PersonDetailScreenState();
}

class _PersonDetailScreenState extends State<_PersonDetailScreen> {
  bool _analyzing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.person.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete person',
            onPressed: _confirmDeletePerson,
          ),
        ],
      ),
      body: Column(
        children: [
          // Tags
          if (widget.person.tags.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Wrap(
                spacing: 8,
                children: widget.person.tags
                    .map((t) => Chip(label: Text(t)))
                    .toList(),
              ),
            ),

          // Entries list
          Expanded(
            child: StreamBuilder<List<PersonEntry>>(
              stream: widget.peopleService
                  .watchEntries(widget.person.id),
              builder: (context, snapshot) {
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
                          Icon(Icons.notes,
                              size: 48,
                              color: Theme.of(context).colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            'No entries yet.\nAdd diary entries, chat logs, or notes about this person.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 160),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return _EntryTile(
                      entry: entry,
                      onDelete: () => widget.peopleService.deleteEntry(
                          widget.person.id, entry.id),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_analyzing)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Analyzing...',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      )),
                ],
              ),
            ),
          FloatingActionButton.extended(
            onPressed: _analyzing ? null : _showAddEntrySheet,
            tooltip: 'Add entry',
            icon: const Icon(Icons.add),
            label: const Text('Add Entry'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            onPressed: _analyzing ? null : _analyzeEntries,
            tooltip: 'Analyze with AI',
            backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
            icon: _analyzing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_fix_high),
            label: Text(_analyzing ? 'Analyzing...' : 'Analyze'),
          ),
        ],
      ),
    );
  }

  void _showAddEntrySheet() {
    final controller = TextEditingController();
    String sourceType = 'manual';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Add entry about ${widget.person.name}',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              // Source type selector
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'manual', label: Text('Note')),
                  ButtonSegment(value: 'diary', label: Text('Diary')),
                  ButtonSegment(value: 'chat', label: Text('Chat')),
                  ButtonSegment(value: 'social', label: Text('Social')),
                ],
                selected: {sourceType},
                onSelectionChanged: (sel) =>
                    setSheetState(() => sourceType = sel.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                minLines: 4,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText:
                      'Paste a conversation, write about this person, or describe a situation...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () async {
                      final text = controller.text.trim();
                      if (text.isEmpty) return;
                      await widget.peopleService.addEntry(
                        widget.person.id,
                        text,
                        sourceType: sourceType,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _analyzeEntries() async {
    setState(() => _analyzing = true);

    try {
      final entries = await widget.peopleService
          .watchEntries(widget.person.id)
          .first;

      final unanalyzed = entries.where((e) => !e.analyzed).toList();

      if (unanalyzed.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All entries already analyzed.')),
          );
          setState(() => _analyzing = false);
        }
        return;
      }

      final entryMaps = unanalyzed
          .map((e) => {'text': e.text, 'sourceType': e.sourceType})
          .toList();

      final result = await ApiService.analyzePerson(entryMaps);

      if (!mounted) return;

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Analysis failed. Is the backend running?')),
        );
        setState(() => _analyzing = false);
        return;
      }

      // Save analysis back to each analyzed entry
      for (final entry in unanalyzed) {
        await widget.peopleService.updateEntryAnalysis(
          widget.person.id,
          entry.id,
          patterns: result['patterns'],
          redFlags: result['redFlags'],
          emotionalReflection: result['emotionalReflection'],
          communicationStyle: result['communicationStyle'],
        );
      }

      if (mounted) {
        setState(() => _analyzing = false);
        _showAnalysisResults(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _analyzing = false);
      }
    }
  }

  void _showAnalysisResults(Map<String, String> result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Analysis — ${widget.person.name}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _AnalysisSection(
                title: 'Patterns',
                icon: Icons.pattern,
                text: result['patterns'] ?? '',
              ),
              const SizedBox(height: 16),
              _AnalysisSection(
                title: 'Red Flags',
                icon: Icons.flag_outlined,
                text: result['redFlags'] ?? '',
                isWarning: true,
              ),
              const SizedBox(height: 16),
              _AnalysisSection(
                title: 'Emotional Reflection',
                icon: Icons.favorite_outline,
                text: result['emotionalReflection'] ?? '',
              ),
              const SizedBox(height: 16),
              _AnalysisSection(
                title: 'Communication Style',
                icon: Icons.chat_bubble_outline,
                text: result['communicationStyle'] ?? '',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _confirmDeletePerson() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${widget.person.name}?'),
        content: const Text(
            'This will delete all entries and analysis for this person.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await widget.peopleService.deletePerson(widget.person.id);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) Navigator.pop(context);
            },
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Entry Tile ──

class _EntryTile extends StatelessWidget {
  final PersonEntry entry;
  final VoidCallback onDelete;

  const _EntryTile({required this.entry, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final sourceIcons = {
      'manual': Icons.edit_note,
      'diary': Icons.book_outlined,
      'chat': Icons.chat_bubble_outline,
      'social': Icons.public,
    };

    final dateStr =
        DateFormat.yMMMd().add_jm().format(entry.createdAt.toDate());

    return Dismissible(
      key: ValueKey(entry.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete_outline,
            color: Theme.of(context).colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete entry?'),
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
          onDelete();
          return true;
        }
        return false;
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: ExpansionTile(
          leading: Icon(sourceIcons[entry.sourceType] ?? Icons.notes),
          title: Text(
            entry.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(dateStr, style: Theme.of(context).textTheme.bodySmall),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Full text
                  Text(entry.text),
                  const Divider(),

                  if (entry.analyzed) ...[
                    if (entry.patterns != null && entry.patterns!.isNotEmpty)
                      _MiniSection(label: 'Patterns', text: entry.patterns!),
                    if (entry.redFlags != null && entry.redFlags!.isNotEmpty)
                      _MiniSection(
                          label: 'Red Flags',
                          text: entry.redFlags!,
                          isWarning: true),
                    if (entry.emotionalReflection != null &&
                        entry.emotionalReflection!.isNotEmpty)
                      _MiniSection(
                          label: 'Emotional Reflection',
                          text: entry.emotionalReflection!),
                    if (entry.communicationStyle != null &&
                        entry.communicationStyle!.isNotEmpty)
                      _MiniSection(
                          label: 'Communication Style',
                          text: entry.communicationStyle!),
                  ] else
                    Text(
                      'Not yet analyzed',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniSection extends StatelessWidget {
  final String label;
  final String text;
  final bool isWarning;

  const _MiniSection({
    required this.label,
    required this.text,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: isWarning
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 2),
          Text(text, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AnalysisSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final String text;
  final bool isWarning;

  const _AnalysisSection({
    required this.title,
    required this.icon,
    required this.text,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon,
                size: 18,
                color: isWarning
                    ? Theme.of(context).colorScheme.error
                    : Theme.of(context).colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(text.isEmpty ? '(No data)' : text),
      ],
    );
  }
}
