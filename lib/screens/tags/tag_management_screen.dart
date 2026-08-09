import 'package:flutter/material.dart';
import '../../models/tags/tag.dart';
import '../../services/tags/tag_service.dart';

/// Standalone screen for renaming or deleting tags. Reachable from
/// Settings (or from TaskFormScreen's tag section) — kept separate from
/// TaskFormScreen itself since tag management isn't really part of
/// editing one specific task.
class TagManagementScreen extends StatelessWidget {
  const TagManagementScreen({super.key, required this.tagService});

  final TagService tagService;

  Future<void> _rename(BuildContext context, Tag tag, List<Tag> allTags) async {
    final controller = TextEditingController(text: tag.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename tag'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newName == null) return;
    await tagService.updateTagName(tag.id, newName, allTags);
  }

  Future<void> _confirmDelete(BuildContext context, Tag tag) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete tag?'),
        // Sets expectations up front: this doesn't touch the tasks
        // themselves, only clears the tag from them — matches what
        // TagService.deleteTag actually does.
        content: Text(
          'Deleting "${tag.name}" will remove it from every task that '
          'uses it. The tasks themselves won\'t be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await tagService.deleteTag(tag.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Tags')),
      body: StreamBuilder<List<Tag>>(
        stream: tagService.watchTags(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final tags = snapshot.data ?? [];
          if (tags.isEmpty) {
            return const Center(child: Text('No tags yet.'));
          }
          return ListView.builder(
            itemCount: tags.length,
            itemBuilder: (context, index) {
              final tag = tags[index];
              return ListTile(
                leading: CircleAvatar(
                  radius: 10,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                ),
                title: Text(tag.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Rename',
                      onPressed: () => _rename(context, tag, tags),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete',
                      onPressed: () => _confirmDelete(context, tag),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}