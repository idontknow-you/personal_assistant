import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/alarms/alarm.dart';
import '../../services/alarms/alarm_service.dart';

class AlarmFormScreen extends StatefulWidget {
  const AlarmFormScreen({
    super.key,
    required this.alarmService,
    this.existingAlarm,
  });

  final AlarmService alarmService;
  /// Null = creating a new alarm. Non-null = editing this one.
  final AlarmModel? existingAlarm;

  @override
  State<AlarmFormScreen> createState() => _AlarmFormScreenState();
}

class _AlarmFormScreenState extends State<AlarmFormScreen> {
  static const _bundledSounds = {
    'Default': 'assets/sounds/default.mp3',
    'Classic': 'assets/sounds/classic.mp3',
    'Gentle': 'assets/sounds/gentle.mp3',
    'Shock': 'assets/sounds/shock.mp3',
  };

  static const _weekdayLabels = {
    1: 'Mon', 2: 'Tue', 3: 'Wed', 4: 'Thu',
    5: 'Fri', 6: 'Sat', 7: 'Sun',
  };

  late TimeOfDay _time;
  late TextEditingController _labelController;
  late AlarmType _type;
  late Set<int> _repeatDays;
  late DateTime _oneTimeDate;
  late SoundSource _soundSource;
  String? _soundPath;
  bool _saving = false;

  bool get _isEditing => widget.existingAlarm != null;

  @override
  void initState() {
    super.initState();
    final a = widget.existingAlarm;
    _time = TimeOfDay(hour: a?.hour ?? 7, minute: a?.minute ?? 0);
    _labelController = TextEditingController(text: a?.label ?? '');
    _type = a?.type ?? AlarmType.oneTime;
    _repeatDays = {...(a?.repeatDays ?? const {})};
    _oneTimeDate = a?.oneTimeDate ?? DateTime.now();
    _soundSource = a?.soundSource ?? SoundSource.deviceDefault;
    _soundPath = a?.soundPath;
  }

  @override
  void dispose() {
    _labelController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _oneTimeDate.isBefore(DateTime.now())
          ? DateTime.now()
          : _oneTimeDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _oneTimeDate = picked);
  }

  Future<void> _pickDeviceFile() async {
    final result = await FilePicker.pickFiles(type: FileType.audio);    if (result != null && result.files.single.path != null) {
      setState(() {
        _soundSource = SoundSource.deviceFile;
        _soundPath = result.files.single.path;
      });
    }
  }

  bool get _canSave {
    if (_type == AlarmType.repeating && _repeatDays.isEmpty) return false;
    if (_soundSource == SoundSource.bundled && _soundPath == null) return false;
    if (_soundSource == SoundSource.deviceFile && _soundPath == null) return false;
    return true;
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    final now = DateTime.now();
    // Seconds-since-epoch fits int32 comfortably until 2038 — fine for an
    // alarm id. Existing alarms keep their id; new ones get a fresh one.
    final id = widget.existingAlarm?.id ?? (now.millisecondsSinceEpoch ~/ 1000);

    final alarm = AlarmModel(
      id: id,
      label: _labelController.text.trim(),
      hour: _time.hour,
      minute: _time.minute,
      type: _type,
      repeatDays: _type == AlarmType.repeating ? _repeatDays : const {},
      oneTimeDate: _type == AlarmType.oneTime
          ? DateTime(_oneTimeDate.year, _oneTimeDate.month, _oneTimeDate.day)
          : null,
      isEnabled: widget.existingAlarm?.isEnabled ?? true,
      soundSource: _soundSource,
      soundPath: _soundSource == SoundSource.deviceDefault ? null : _soundPath,
      createdAt: widget.existingAlarm?.createdAt ?? now,
      updatedAt: now,
    );

    // saveAlarm handles both Firestore persistence AND native scheduling
    // internally now — no need to call scheduleAlarm separately here.
    await widget.alarmService.saveAlarm(alarm);

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit Alarm' : 'New Alarm')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: TextButton(
              onPressed: _pickTime,
              child: Text(
                _time.format(context),
                style: Theme.of(context).textTheme.displaySmall,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _labelController,
            decoration: const InputDecoration(
              labelText: 'Label (optional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 24),
          SegmentedButton<AlarmType>(
            segments: const [
              ButtonSegment(value: AlarmType.oneTime, label: Text('One-time')),
              ButtonSegment(value: AlarmType.repeating, label: Text('Repeating')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 16),
          if (_type == AlarmType.repeating)
            Wrap(
              spacing: 8,
              children: _weekdayLabels.entries.map((entry) {
                final selected = _repeatDays.contains(entry.key);
                return FilterChip(
                  label: Text(entry.value),
                  selected: selected,
                  onSelected: (val) => setState(() {
                    val ? _repeatDays.add(entry.key) : _repeatDays.remove(entry.key);
                  }),
                );
              }).toList(),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '${_oneTimeDate.day}/${_oneTimeDate.month}/${_oneTimeDate.year}',
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDate,
            ),
          const SizedBox(height: 24),
          Text('Sound', style: Theme.of(context).textTheme.titleMedium),
          RadioListTile<SoundSource>(
            title: const Text('Device default'),
            value: SoundSource.deviceDefault,
            groupValue: _soundSource,
            onChanged: (v) => setState(() {
              _soundSource = v!;
              _soundPath = null;
            }),
          ),
          RadioListTile<SoundSource>(
            title: const Text('Bundled sound'),
            value: SoundSource.bundled,
            groupValue: _soundSource,
            onChanged: (v) => setState(() {
              _soundSource = v!;
              _soundPath = _bundledSounds.values.first;
            }),
          ),
          if (_soundSource == SoundSource.bundled)
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: DropdownButton<String>(
                value: _soundPath,
                items: _bundledSounds.entries
                    .map((e) => DropdownMenuItem(
                          value: e.value,
                          child: Text(e.key),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _soundPath = v),
              ),
            ),
          RadioListTile<SoundSource>(
            title: Text(
              _soundSource == SoundSource.deviceFile && _soundPath != null
                  ? 'Device file: ${_soundPath!.split('/').last}'
                  : 'Choose from device',
            ),
            value: SoundSource.deviceFile,
            groupValue: _soundSource,
            onChanged: (_) => _pickDeviceFile(),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: _canSave && !_saving ? _save : null,
            child: _saving
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Alarm'),
          ),
        ],
      ),
    );
  }
}