import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/notes/future_letter.dart';
import '../../services/notes/future_letter_service.dart';
import 'future_letter_form_screen.dart';
import 'future_letter_reflect_screen.dart';

class FutureLetterListPage extends StatelessWidget {
  final FutureLetterService letterService;

  const FutureLetterListPage({super.key, required this.letterService});

  void _openCreate(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FutureLetterFormScreen(letterService: letterService),
      ),
    );
  }

  void _openReflect(BuildContext context, FutureLetter letter) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FutureLetterReflectScreen(
          letterService: letterService,
          letter: letter,
        ),
      ),
    );
  }

  void _openRead(BuildContext context, FutureLetter letter) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _LetterDetailScreen(letter: letter),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, FutureLetterService service, FutureLetter letter) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete letter?'),
        content: const Text('This letter will be permanently deleted.'),
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
      await service.deleteLetter(letter.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Letters to Future Me')),
      body: StreamBuilder<List<FutureLetter>>(
        stream: letterService.watchLetters(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final letters = snapshot.data ?? [];
          if (letters.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.mail_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 16),
                    Text(
                      'Write a letter to your future self.',
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Decide something now. The app will\nresurface it later so you can check\nif you followed through.',
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

          // Partition into ready, waiting, and reflected.
          final ready = letters.where((l) => l.isReady).toList();
          final waiting = letters
              .where((l) => !l.isReady && !l.isReflected)
              .toList();
          final reflected = letters.where((l) => l.isReflected).toList();

          return ListView(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).padding.bottom + 96,
            ),
            children: [
              if (ready.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.mark_email_unread,
                  label: 'Ready to open (${ready.length})',
                  color: Theme.of(context).colorScheme.primary,
                ),
                ...ready.map((letter) => _LetterTile(
                      letter: letter,
                      onTap: () => _openReflect(context, letter),
                      onDelete: () => _confirmDelete(context, letterService, letter),
                    )),
              ],
              if (waiting.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.schedule,
                  label: 'Waiting (${waiting.length})',
                  color: Theme.of(context).colorScheme.secondary,
                ),
                ...waiting.map((letter) => _LetterTile(
                      letter: letter,
                      onTap: () => _openRead(context, letter),
                      onDelete: () => _confirmDelete(context, letterService, letter),
                    )),
              ],
              if (reflected.isNotEmpty) ...[
                _SectionHeader(
                  icon: Icons.check_circle_outline,
                  label: 'Reflected (${reflected.length})',
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                ...reflected.map((letter) => _LetterTile(
                      letter: letter,
                      onTap: () => _openRead(context, letter),
                      onDelete: () => _confirmDelete(context, letterService, letter),
                    )),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCreate(context),
        tooltip: 'New letter',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _SectionHeader({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _LetterTile extends StatelessWidget {
  final FutureLetter letter;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _LetterTile({
    required this.letter,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final written = DateFormat.yMMMd().format(letter.writtenDate.toDate());
    final resurface = DateFormat.yMMMd().format(letter.resurfaceDate.toDate());
    final preview = letter.content.length > 80
        ? '${letter.content.substring(0, 80)}…'
        : letter.content;

    return Dismissible(
      key: ValueKey(letter.id),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete_outline,
            color: Theme.of(context).colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          letter.isReady
              ? Icons.mark_email_unread
              : letter.isReflected
                  ? Icons.check_circle
                  : Icons.mail_outline,
          color: letter.isReady
              ? Theme.of(context).colorScheme.primary
              : letter.isReflected
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.outline,
        ),
        title: Text(
          preview,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          'Written $written · Resurfaces $resurface',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        trailing: letter.isReady
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Open',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// Simple read-only detail screen for letters that aren't ready or are already
/// reflected. Shows the original content and (if present) the reflection.
class _LetterDetailScreen extends StatelessWidget {
  final FutureLetter letter;

  const _LetterDetailScreen({required this.letter});

  @override
  Widget build(BuildContext context) {
    final written = DateFormat.yMMMd().add_jm().format(letter.writtenDate.toDate());
    final resurface = DateFormat.yMMMd().format(letter.resurfaceDate.toDate());

    return Scaffold(
      appBar: AppBar(title: const Text('Your Letter')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Written on $written',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'Resurfaces on $resurface',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          Text(
            letter.content,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          if (letter.isReflected) ...[
            const Divider(height: 48),
            Text(
              'Your reflection',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              letter.reflection,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
          if (letter.isReady) ...[
            const Divider(height: 48),
            Text(
              'This letter is ready to be opened.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontStyle: FontStyle.italic,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}
