import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';

/// Editable subtask list with add/remove/toggle — used by TaskFormScreen.
class SubtaskList extends StatefulWidget {
  const SubtaskList({
    super.key,
    required this.subtasks,
    required this.onChanged,
  });

  final List<Subtask> subtasks;
  final ValueChanged<List<Subtask>> onChanged;

  @override
  State<SubtaskList> createState() => _SubtaskListState();
}

class _SubtaskListState extends State<SubtaskList> {
  final _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _add() {
    final title = _inputController.text.trim();
    if (title.isEmpty) return;
    widget.onChanged([
      ...widget.subtasks,
      Subtask(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: title,
      ),
    ]);
    _inputController.clear();
  }

  void _remove(String id) {
    widget.onChanged(widget.subtasks.where((s) => s.id != id).toList());
  }

  void _toggle(String id, bool value) {
    widget.onChanged(
      widget.subtasks
          .map((s) => s.id == id ? s.copyWith(isCompleted: value) : s)
          .toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Subtasks', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ...widget.subtasks.map((sub) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Row(
                children: [
                  Checkbox(
                    value: sub.isCompleted,
                    onChanged: (val) => _toggle(sub.id, val!),
                  ),
                  Expanded(
                    child: Text(
                      sub.title,
                      style: TextStyle(
                        decoration: sub.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: sub.isCompleted
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _remove(sub.id),
                  ),
                ],
              ),
            )),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                decoration: const InputDecoration(
                  hintText: 'Add a subtask',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _add,
            ),
          ],
        ),
      ],
    );
  }
}
