import 'package:flutter/material.dart';
import '../../services/notes/brain_dump_service.dart';

/// A minimal bottom sheet for capturing a brain dump entry. Zero friction:
/// just text + send button. No title, no tags, no structure.
void showBrainDumpSheet(BuildContext context, BrainDumpService service) {
  final controller = TextEditingController();
  final focusNode = FocusNode();

  // Auto-focus the text field when the sheet opens.
  WidgetsBinding.instance.addPostFrameCallback((_) => focusNode.requestFocus());

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
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
              'Brain Dump',
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Just dump it. Sort later.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              focusNode: focusNode,
              minLines: 3,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [
                // No max length — brain dumps should be unlimited.
              ],
              decoration: const InputDecoration(
                hintText: 'What\'s on your mind?',
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
                FilledButton.icon(
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    await service.addEntry(text);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Dump'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
