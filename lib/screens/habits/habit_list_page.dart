import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/habits/habit.dart';
import '../../services/habits/habit_service.dart';

import '../../widgets/habits/habit_tile.dart';

class HabitListPage extends StatefulWidget {
  final HabitService habitService;

  const HabitListPage({super.key, required this.habitService});

  @override
  State<HabitListPage> createState() => _HabitListPageState();
}

class _HabitListPageState extends State<HabitListPage> {
  Future<void> _showAddHabitDialog() async {
    final controller = TextEditingController();
    final selectedDays = <int>{}; // empty = every day

    const weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('New Habit'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Habit name'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Days (leave blank for every day)',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (i) {
                      final weekday = i + 1; // 1 = Monday
                      final selected = selectedDays.contains(weekday);
                      return FilterChip(
                        label: Text(weekdayLabels[i]),
                        selected: selected,
                        onSelected: (val) {
                          setDialogState(() {
                            if (val) {
                              selectedDays.add(weekday);
                            } else {
                              selectedDays.remove(weekday);
                            }
                          });
                        },
                      );
                    }),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    final name = controller.text.trim();
                    if (name.isEmpty) return;
                    HapticFeedback.lightImpact();
                    await widget.habitService.addHabit(
                      name,
                      frequency: selectedDays,
                    );
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDelete(Habit habit) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete habit?'),
        content: Text('"${habit.name}" and its full history will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.habitService.deleteHabit(habit);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Habits')),
      body: StreamBuilder<List<Habit>>(
        stream: widget.habitService.watchHabits(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final habits = snapshot.data!;
          if (habits.isEmpty) {
            return const Center(
              child: Text('No habits yet — tap + to add one.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: habits.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final habit = habits[i];
              return HabitTile(
                habit: habit,
                onDotTap: (date) =>
                    widget.habitService.cycleStatus(habit, date),
                onLongPress: () => _confirmDelete(habit),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddHabitDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}