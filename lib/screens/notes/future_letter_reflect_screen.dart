import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/notes/future_letter.dart';
import '../../services/notes/future_letter_service.dart';

/// Screen shown when a letter's resurface date has arrived. Displays the
/// original letter and lets the user write a follow-through reflection.
class FutureLetterReflectScreen extends StatefulWidget {
  final FutureLetterService letterService;
  final FutureLetter letter;

  const FutureLetterReflectScreen({
    super.key,
    required this.letterService,
    required this.letter,
  });

  @override
  State<FutureLetterReflectScreen> createState() =>
      _FutureLetterReflectScreenState();
}

class _FutureLetterReflectScreenState extends State<FutureLetterReflectScreen> {
  final _reflectionController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _reflectionController.dispose();
    super.dispose();
  }

  bool get _canSave => _reflectionController.text.trim().isNotEmpty;

  Future<void> _save() async {
    if (_saving || !_canSave) return;
    setState(() => _saving = true);

    try {
      await widget.letterService.addReflection(
        widget.letter.id,
        _reflectionController.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save reflection: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final written = DateFormat.yMMMd().format(widget.letter.writtenDate.toDate());
    final resurface =
        DateFormat.yMMMd().format(widget.letter.resurfaceDate.toDate());

    return Scaffold(
      appBar: AppBar(title: const Text('Your Future Letter')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.mail,
                  color: Theme.of(context).colorScheme.primary, size: 28),
              const SizedBox(width: 8),
              Text(
                'This letter has arrived!',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Written $written · Scheduled for $resurface',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),

          // Original letter
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              widget.letter.content,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),

          // Reflection prompt
          const Divider(height: 48),
          Text(
            'How did it go?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Did you follow through on what you wrote about? Be honest.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _reflectionController,
            minLines: 4,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Looking back, here\'s what happened...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),

          const SizedBox(height: 24),
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
                : const Text('Save Reflection'),
          ),
        ],
      ),
    );
  }
}
