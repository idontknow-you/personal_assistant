import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/notes/note.dart';
import '../../services/notes/note_service.dart';
import 'note_form_screen.dart';

/// Diary notes page — now notes only (brain dump lives in its own tab).
class NoteListPage extends StatefulWidget {
  final NoteService noteService;

  const NoteListPage({
    super.key,
    required this.noteService,
  });

  @override
  State<NoteListPage> createState() => _NoteListPageState();
}

class _NoteListPageState extends State<NoteListPage> {
  Mood? _filterMood;

  void _openForm({Note? existingNote}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteFormScreen(
          noteService: widget.noteService,
          existingNote: existingNote,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Note note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete note?'),
        content: Text('"${note.title}" will be permanently deleted.'),
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
      await widget.noteService.deleteNote(note.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diary')),
      body: Column(
        children: [
          // Mood filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('All'),
                      selected: _filterMood == null,
                      onSelected: (_) => setState(() => _filterMood = null),
                    ),
                  ),
                  ...Mood.values.map((mood) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Text(mood.emoji),
                          label: Text(mood.name[0].toUpperCase() +
                              mood.name.substring(1)),
                          selected: _filterMood == mood,
                          selectedColor:
                              Color(mood.colorValue).withValues(alpha: 0.2),
                          onSelected: (_) => setState(() {
                            _filterMood = _filterMood == mood ? null : mood;
                          }),
                        ),
                      )),
                ],
              ),
            ),
          ),
          // Notes list
          Expanded(
            child: StreamBuilder<List<Note>>(
              stream: widget.noteService.watchNotes(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                var notes = snapshot.data ?? [];
                if (_filterMood != null) {
                  notes = notes.where((n) => n.mood == _filterMood).toList();
                }

                if (notes.isEmpty) {
                  return Center(
                    child: Text(
                      _filterMood == null
                          ? 'No notes yet — tap + to write one.'
                          : 'No ${_filterMood!.name} notes.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).padding.bottom + 96,
                  ),
                  itemCount: notes.length,
                  itemBuilder: (context, index) {
                    final note = notes[index];
                    final dateStr = note.createdAt != null
                        ? DateFormat.yMMMd().format(note.createdAt!.toDate())
                        : '';
                    final preview = note.content.length > 100
                        ? '${note.content.substring(0, 100)}...'
                        : note.content;

                    return Dismissible(
                      key: ValueKey(note.id),
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
                        await _confirmDelete(note);
                        return false;
                      },
                      child: ListTile(
                        onTap: () => _openForm(existingNote: note),
                        leading: note.mood != null
                            ? Text(
                                note.mood!.emoji,
                                style: const TextStyle(fontSize: 28),
                              )
                            : null,
                        title: Text(
                          note.title,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (preview.isNotEmpty)
                              Text(
                                preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            if (dateStr.isNotEmpty)
                              Text(
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
                          ],
                        ),
                        trailing: note.mood != null
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Color(note.mood!.colorValue)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  note.mood!.name,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(note.mood!.colorValue),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openForm(),
        tooltip: 'New note',
        child: const Icon(Icons.add),
      ),
    );
  }
}
