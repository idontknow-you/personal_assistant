import 'package:flutter/material.dart';
import '../../models/tasks/task.dart';
import '../../services/tasks/task_service.dart';
import '../../widgets/tasks/task_tile.dart';
import '../../widgets/common/theme_toggle_switch.dart';

class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key, required this.uid});
  final String uid;

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  late final TaskService _taskService;

  @override
  void initState() {
    super.initState();
    _taskService = TaskService(widget.uid);
  }

  void _showAddTaskSheet() {
    final controller = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'New task title',
                  ),
                  onSubmitted: (value) {
                    _taskService.addTask(value);
                    Navigator.pop(context);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () {
                  _taskService.addTask(controller.text);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
            title: const Text('Tasks'),
            actions: [
                ThemeToggleSwitch(),
                SizedBox(width: 8),
            ],
        ),
      body: StreamBuilder<List<Task>>(
        stream: _taskService.watchTasks(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final tasks = snapshot.data ?? [];
          if (tasks.isEmpty) {
            return const Center(
              child: Text('No tasks yet. Tap + to add one.'),
            );
          }
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return TaskTile(
                task: task,
                onToggle: () =>
                    _taskService.toggleComplete(task.id, task.completed),
                onDismissed: () => _taskService.deleteTask(task.id),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddTaskSheet,
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
    );
  }
}