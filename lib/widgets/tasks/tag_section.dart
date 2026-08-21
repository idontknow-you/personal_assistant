import 'package:flutter/material.dart';
import '../../models/tags/tag.dart';
import '../../services/tags/tag_service.dart';

/// Tag picker with inline "new tag" creation — used by TaskFormScreen.
class TagSection extends StatefulWidget {
  const TagSection({
    super.key,
    required this.tagService,
    required this.selectedTagId,
    required this.onTagSelected,
  });

  final TagService tagService;
  final String? selectedTagId;
  final ValueChanged<String?> onTagSelected;

  @override
  State<TagSection> createState() => _TagSectionState();
}

class _TagSectionState extends State<TagSection> {
  final _newTagController = TextEditingController();
  bool _addingTag = false;
  bool _submittingTag = false;

  @override
  void dispose() {
    _newTagController.dispose();
    super.dispose();
  }

  Future<void> _submitNewTag(List<Tag> existingTags) async {
    if (_submittingTag) return;
    final name = _newTagController.text.trim();
    if (name.isEmpty) {
      setState(() => _addingTag = false);
      return;
    }
    setState(() => _submittingTag = true);
    final newTagId = await widget.tagService.addTag(name, existingTags);
    if (!mounted) return;
    setState(() {
      if (newTagId.isNotEmpty) widget.onTagSelected(newTagId);
      _addingTag = false;
      _submittingTag = false;
      _newTagController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Tag>>(
      stream: widget.tagService.watchTags(),
      builder: (context, snapshot) {
        final tags = snapshot.data ?? [];
        final tagColor = Theme.of(context).colorScheme.primary;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tag', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...tags.map((tag) {
                  final selected = widget.selectedTagId == tag.id;
                  return ChoiceChip(
                    label: Text(tag.name),
                    selected: selected,
                    selectedColor: tagColor.withValues(alpha: 0.25),
                    labelStyle: TextStyle(
                      color: selected ? tagColor : null,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                    onSelected: (_) {
                      // Tapping the already-selected tag deselects it.
                      widget.onTagSelected(
                        widget.selectedTagId == tag.id ? null : tag.id,
                      );
                    },
                  );
                }),
                if (_addingTag)
                  SizedBox(
                    width: 140,
                    child: TextField(
                      controller: _newTagController,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Tag name',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => _submitNewTag(tags),
                    ),
                  )
                else
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 16),
                    label: const Text('New tag'),
                    onPressed: () => setState(() => _addingTag = true),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
