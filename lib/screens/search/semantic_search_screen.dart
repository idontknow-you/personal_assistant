import 'package:flutter/material.dart';
import '../../services/notes/note_service.dart';
import '../../services/notes/brain_dump_service.dart';
import '../../services/api/api_service.dart';

/// Search across notes, diary, and brain dump by meaning (semantic search).
class SemanticSearchScreen extends StatefulWidget {
  final String uid;
  final NoteService noteService;
  final BrainDumpService brainDumpService;

  const SemanticSearchScreen({
    super.key,
    required this.uid,
    required this.noteService,
    required this.brainDumpService,
  });

  @override
  State<SemanticSearchScreen> createState() => _SemanticSearchScreenState();
}

class _SemanticSearchScreenState extends State<SemanticSearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _loading = true;
      _error = null;
      _results = [];
    });

    try {
      // Gather all entries from Firestore
      final notes = await widget.noteService.watchNotes().first;
      final dumps = await widget.brainDumpService.watchEntries().first;

      final entries = <Map<String, dynamic>>[];

      for (final n in notes) {
        entries.add({
          'id': n.id,
          'type': 'note',
          'title': n.title,
          'text': n.content,
          'mood': n.mood?.name ?? '',
          'date': n.createdAt?.toDate().toIso8601String() ?? '',
        });
      }

      for (final d in dumps) {
        entries.add({
          'id': d.id,
          'type': 'braindump',
          'title': '',
          'text': d.text,
          'mood': '',
          'date': d.createdAt.toDate().toIso8601String(),
        });
      }

      if (entries.isEmpty) {
        setState(() {
          _results = [];
          _loading = false;
        });
        return;
      }

      final results = await ApiService.semanticSearch(query, entries: entries);

      if (mounted) {
        setState(() {
          _results = results ?? [];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Search failed: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                hintText: 'Search by meaning, not keywords...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _controller.clear();
                          setState(() => _results = []);
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Results
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          'Searching by meaning...',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 48, color: cs.error),
                              const SizedBox(height: 12),
                              Text(_error!, textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      )
                    : _results.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search,
                                      size: 56,
                                      color: cs.outline),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Search your notes and thoughts',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Type a question like "what made me anxious" or "ideas about fitness"',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        color: cs.onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16),
                            itemCount: _results.length,
                            itemBuilder: (context, index) {
                              final r = _results[index];
                              final relevance =
                                  r['relevance'] ?? 'medium';
                              final relevanceColor = relevance == 'high'
                                  ? cs.primary
                                  : relevance == 'medium'
                                      ? cs.tertiary
                                      : cs.outline;

                              return Card(
                                margin:
                                    const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  leading: Icon(
                                    r['type'] == 'note'
                                        ? Icons.note_outlined
                                        : Icons.psychology_outlined,
                                    color: relevanceColor,
                                  ),
                                  title: Text(
                                    r['title']?.isNotEmpty == true
                                        ? r['title']
                                        : (r['text'] as String?)
                                                ?.substring(
                                                    0,
                                                    r['text']
                                                            .toString()
                                                            .length
                                                        .clamp(
                                                            0, 50)) ??
                                            '',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (r['summary']
                                              ?.toString()
                                              .isNotEmpty ==
                                          true)
                                        Padding(
                                          padding: const EdgeInsets
                                              .only(top: 4),
                                          child: Text(
                                            r['summary'],
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: cs
                                                  .onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Container(
                                            padding:
                                                const EdgeInsets
                                                    .symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration:
                                                BoxDecoration(
                                              color:
                                                  relevanceColor
                                                      .withValues(
                                                          alpha:
                                                              0.1),
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(4),
                                            ),
                                            child: Text(
                                              relevance
                                                  .toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color:
                                                    relevanceColor,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            r['type'],
                                            style: TextStyle(
                                              fontSize: 11,
                                              color:
                                                  cs.outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
