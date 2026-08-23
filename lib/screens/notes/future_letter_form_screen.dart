import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../services/notes/future_letter_service.dart';

class FutureLetterFormScreen extends StatefulWidget {
  final FutureLetterService letterService;

  const FutureLetterFormScreen({super.key, required this.letterService});

  @override
  State<FutureLetterFormScreen> createState() => _FutureLetterFormScreenState();
}

class _FutureLetterFormScreenState extends State<FutureLetterFormScreen> {
  final _contentController = TextEditingController();
  DateTime _resurfaceDate = DateTime.now().add(const Duration(days: 30));
  bool _saving = false;

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  bool get _canSave => _contentController.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _resurfaceDate,
      firstDate: now.add(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 10)),
      helpText: 'When should this letter resurface?',
    );
    if (picked != null) {
      setState(() => _resurfaceDate = picked);
    }
  }

  Future<void> _save() async {
    if (_saving || !_canSave) return;
    HapticFeedback.lightImpact();
    setState(() => _saving = true);

    try {
      await widget.letterService.addLetter(
        content: _contentController.text.trim(),
        resurfaceDate: _resurfaceDate,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save letter: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat.yMMMd().format(_resurfaceDate);

    return Scaffold(
      appBar: AppBar(title: const Text('Write to Future You')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Write something your future self should hear. A decision you made, '
            'a goal you set, how you feel right now — whatever matters.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _contentController,
            autofocus: true,
            minLines: 8,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Dear future me...',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Resurface on',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      Text(
                        dateStr,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      color: Theme.of(context).colorScheme.outline),
                ],
              ),
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
                : const Text('Send Letter to the Future'),
          ),
        ],
      ),
    );
  }
}
