import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/tasks/task.dart';
import '../../models/alarms/alarm.dart' as alarm_model;
import '../../services/tasks/task_service.dart';
import '../../services/alarms/alarm_service.dart';
import '../../services/tags/tag_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/tasks/tag_section.dart';
import '../../widgets/tasks/subtask_list.dart';

class TaskFormScreen extends StatefulWidget {
  const TaskFormScreen({
    super.key,
    required this.taskService,
    required this.alarmService,
    required this.tagService,
    this.existingTask,
  });

  final TaskService taskService;
  final AlarmService alarmService;
  final TagService tagService;
  /// Null = creating a new task. Non-null = editing this one.
  final Task? existingTask;

  @override
  State<TaskFormScreen> createState() => _TaskFormScreenState();
}

class _TaskFormScreenState extends State<TaskFormScreen> {
  static const _weekdayLabels = {
    1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu',
    5: 'Fri', 6: 'Sat', 7: 'Sun',
  };

  late TextEditingController _titleController;
  late TextEditingController _notesController;
  DateTime? _dueDate;
  TaskRepeatType _repeatType = TaskRepeatType.none;
  Set<int> _repeatDays = {};
  Priority _priority = Priority.low;
  List<Subtask> _subtasks = [];
  String? _tagId;

  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 9, minute: 0);

  /// The alarm currently linked to this task, if any — loaded async in
  /// initState so we can prefill the reminder toggle/time correctly and
  /// know its id for update-in-place vs delete.
  alarm_model.AlarmModel? _existingAlarm;
  bool _loadingAlarm = false;
  bool _saving = false;

  bool get _isEditing => widget.existingTask != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existingTask;
    _titleController = TextEditingController(text: t?.title ?? '');
    _notesController = TextEditingController(text: t?.notes ?? '');
    _dueDate = t?.dueDate?.toDate();
    _repeatType = t?.repeatType ?? TaskRepeatType.none;
    _repeatDays = {...(t?.repeatDays ?? const {})};
    // New tasks (t == null) default to low priority.
    _priority = t?.priority ?? Priority.low;
    _subtasks = [...(t?.subtasks ?? const [])];
    _tagId = t?.tagId;

    if (t?.linkedAlarmId != null) {
      _loadingAlarm = true;
      widget.alarmService.getAlarm(t!.linkedAlarmId!).then((alarm) {
        if (!mounted) return;
        setState(() {
          _existingAlarm = alarm;
          _reminderEnabled = alarm != null;
          if (alarm != null) {
            _reminderTime = TimeOfDay(hour: alarm.hour, minute: alarm.minute);
          }
          _loadingAlarm = false;
        });
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (!mounted) return;
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickReminderTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );
    if (!mounted) return;
    if (picked != null) setState(() => _reminderTime = picked);
  }

  void _onReminderToggled(bool val) {
    // A reminder alarm needs a specific calendar date to fire on. If the
    // user hasn't set a due date yet, default it to today rather than
    // silently refusing — they can still change it.
    setState(() {
      _reminderEnabled = val;
      if (val && _dueDate == null) {
        _dueDate = DateTime.now();
      }
    });
  }

  bool get _canSave {
    if (_titleController.text.trim().isEmpty) return false;
    if (_repeatType == TaskRepeatType.weekly && _repeatDays.isEmpty) {
      return false;
    }
    return true;
  }

  /// The repeatDays a linked alarm should use, derived from the task's own
  /// repeat settings — daily means "every day," so the alarm's repeatDays
  /// is all seven weekdays; weekly reuses the task's own set directly.
  Set<int> get _alarmRepeatDays {
    if (_repeatType == TaskRepeatType.daily) return {1, 2, 3, 4, 5, 6, 7};
    return _repeatDays;
  }

  Future<void> _save() async {
    // Guard against double-tap re-entrancy: onPressed only gets disabled
    // once setState below triggers a rebuild, and there's a real gap
    // between a tap and that rebuild landing. A second tap in that gap
    // would otherwise re-enter _save() and create a SECOND task doc (via
    // addTask, which always allocates a fresh Firestore id) plus a SECOND
    // alarm (via a freshly computed id in the reminder block below) —
    // this is exactly what produced duplicate tasks/alarms. This check is
    // synchronous and runs before anything else, so it closes that gap.
    if (_saving) return;
    HapticFeedback.lightImpact();
    if (!_canSave) return;
    setState(() => _saving = true);

    try {
      final title = _titleController.text.trim();
      final notes = _notesController.text.trim();
      final repeats = _repeatType != TaskRepeatType.none;

      // Repeating tasks MUST have a dueDate — TaskService.runDailyRollover()
      // finds repeating tasks via a Firestore query on dueDate, so a
      // repeating task with no dueDate is invisible to it and will never
      // roll over (never reset to unchecked the next day). Due date is
      // optional in the UI above, so default it to today here rather than
      // leaving it null when the user turned on Daily/Weekly but didn't
      // separately set a date. TaskService.addTask/updateTask also enforce
      // this independently now, so this is belt-and-suspenders.
      if (repeats && _dueDate == null) {
        _dueDate = DateTime.now();
      }
      final dueTimestamp =
          _dueDate == null ? null : Timestamp.fromDate(_dueDate!);

      String taskId;
      if (_isEditing) {
        taskId = widget.existingTask!.id;
      } else {
        // Create the task first so we have a Firestore id to attach to
        // the alarm as linkedTaskId.
        taskId = await widget.taskService.addTask(
          title,
          dueDate: dueTimestamp,
          repeatType: _repeatType,
          repeatDays: _repeatDays,
          priority: _priority,
          subtasks: _subtasks,
          notes: notes,
          tagId: _tagId,
        );
      }

      int? linkedAlarmId = widget.existingTask?.linkedAlarmId;

      if (_reminderEnabled) {
        final now = DateTime.now();
        final alarmId = _existingAlarm?.id ??
            (now.millisecondsSinceEpoch ~/ 1000);

        // Repeating tasks get a genuinely repeating alarm (same weekday
        // set), so it keeps firing every period without needing to be
        // recreated by rollover. Non-repeating tasks keep the simple
        // one-time-tied-to-due-date alarm as before.
        final alarm = repeats
            ? alarm_model.AlarmModel(
                id: alarmId,
                label: title,
                hour: _reminderTime.hour,
                minute: _reminderTime.minute,
                type: alarm_model.AlarmType.repeating,
                repeatDays: _alarmRepeatDays,
                isEnabled: true,
                createdAt: _existingAlarm?.createdAt ?? now,
                updatedAt: now,
                linkedTaskId: taskId,
              )
            : alarm_model.AlarmModel(
                id: alarmId,
                label: title,
                hour: _reminderTime.hour,
                minute: _reminderTime.minute,
                type: alarm_model.AlarmType.oneTime,
                oneTimeDate:
                    DateTime(_dueDate!.year, _dueDate!.month, _dueDate!.day),
                isEnabled: true,
                createdAt: _existingAlarm?.createdAt ?? now,
                updatedAt: now,
                linkedTaskId: taskId,
              );

        await widget.alarmService.saveAlarm(alarm);
        linkedAlarmId = alarmId;
      } else if (_existingAlarm != null) {
        // Reminder was turned off — cancel and drop the old alarm.
        await widget.alarmService.deleteAlarm(_existingAlarm!.id);
        linkedAlarmId = null;
      }

      if (_isEditing) {
        final updated = widget.existingTask!.copyWith(
          title: title,
          dueDate: dueTimestamp,
          clearDueDate: dueTimestamp == null,
          repeatType: _repeatType,
          repeatDays: _repeatType == TaskRepeatType.weekly ? _repeatDays : {},
          linkedAlarmId: linkedAlarmId,
          clearLinkedAlarmId: linkedAlarmId == null,
          priority: _priority,
          subtasks: _subtasks,
          notes: notes,
          tagId: _tagId,
          clearTagId: _tagId == null,
        );
        await widget.taskService.updateTask(updated);
      } else if (linkedAlarmId != null) {
        // New task: patch in just linkedAlarmId. Deliberately not a full
        // updateTask call here — see TaskFormScreen history for why a bare
        // partial Task object would wipe fields already saved by addTask.
        await widget.taskService.setLinkedAlarm(taskId, linkedAlarmId);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save task: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Task' : 'New Task')),
      body: _loadingAlarm
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  controller: _titleController,
                  autofocus: !_isEditing,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 24),
                Text('Priority', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<Priority>(
                  segments: [
                    ButtonSegment(
                      value: Priority.low,
                      label: const Text('Low'),
                      icon: Icon(Icons.circle, size: 10, color: AppColors.priorityLow),
                    ),
                    ButtonSegment(
                      value: Priority.medium,
                      label: const Text('Medium'),
                      icon: Icon(Icons.circle, size: 10, color: AppColors.priorityMedium),
                    ),
                    ButtonSegment(
                      value: Priority.high,
                      label: const Text('High'),
                      icon: Icon(Icons.circle, size: 10, color: AppColors.priorityHigh),
                    ),
                  ],
                  selected: {_priority},
                  onSelectionChanged: (s) => setState(() => _priority = s.first),
                ),
                const Divider(height: 32),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Due date'),
                  subtitle: Text(
                    _dueDate == null
                        ? 'None set'
                        : '${_dueDate!.day}/${_dueDate!.month}/${_dueDate!.year}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_dueDate != null &&
                          !_reminderEnabled &&
                          _repeatType == TaskRepeatType.none)
                        // Clearing the due date on a repeating task would
                        // just get silently re-defaulted back to today by
                        // _save() (and by TaskService itself), which reads
                        // as broken rather than intentional — so the
                        // clear button is only offered for non-repeating
                        // tasks, where "no due date" is a real, stable
                        // state.
                        IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => _dueDate = null),
                        ),
                      const Icon(Icons.calendar_today),
                    ],
                  ),
                  onTap: _pickDueDate,
                ),
                const Divider(height: 32),
                Text('Repeat', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                SegmentedButton<TaskRepeatType>(
                  segments: const [
                    ButtonSegment(value: TaskRepeatType.none, label: Text('None')),
                    ButtonSegment(value: TaskRepeatType.daily, label: Text('Daily')),
                    ButtonSegment(value: TaskRepeatType.weekly, label: Text('Weekly')),
                  ],
                  selected: {_repeatType},
                  onSelectionChanged: (s) => setState(() => _repeatType = s.first),
                ),
                if (_repeatType == TaskRepeatType.weekly) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: _weekdayLabels.entries.map((entry) {
                      final selected = _repeatDays.contains(entry.key);
                      return FilterChip(
                        label: Text(entry.value),
                        selected: selected,
                        onSelected: (val) => setState(() {
                          val
                              ? _repeatDays.add(entry.key)
                              : _repeatDays.remove(entry.key);
                        }),
                      );
                    }).toList(),
                  ),
                ],
                const Divider(height: 32),
                TagSection(
                  tagService: widget.tagService,
                  selectedTagId: _tagId,
                  onTagSelected: (id) => setState(() => _tagId = id),
                ),
                const Divider(height: 32),
                SubtaskList(
                  subtasks: _subtasks,
                  onChanged: (subs) => setState(() => _subtasks = subs),
                ),
                const Divider(height: 32),
                Text('Notes', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: 8,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Anything else about this task...',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const Divider(height: 32),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Set reminder alarm'),
                  subtitle: _reminderEnabled
                      ? Text(
                          _repeatType == TaskRepeatType.none
                              ? 'Rings at ${_reminderTime.format(context)}'
                              : 'Rings at ${_reminderTime.format(context)}, repeats with the task',
                        )
                      : const Text('Off'),
                  value: _reminderEnabled,
                  onChanged: _onReminderToggled,
                ),
                if (_reminderEnabled)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Reminder time'),
                    trailing: Text(
                      _reminderTime.format(context),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    onTap: _pickReminderTime,
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
                      : const Text('Save Task'),
                ),
              ],
            ),
    );
  }
}