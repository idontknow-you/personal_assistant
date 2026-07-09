import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/alarms/alarm.dart';
import '../../services/alarms/alarm_service.dart';
import 'package:audioplayers/audioplayers.dart';

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
  static const _defaultSoundAsset = 'assets/sounds/default.mp3';

  static const _bundledSounds = {
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
  bool _soundPickerExpanded = false;
  late final AudioPlayer _previewPlayer;

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
    _previewPlayer = AudioPlayer();
    _previewPlayer.setReleaseMode(ReleaseMode.stop);
  }

  @override
  void dispose() {
    _labelController.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (!mounted) return;
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
    if (!mounted) return;
    if (picked != null) setState(() => _oneTimeDate = picked);
  }

  Future<void> _pickDeviceFile() async {
    final result = await FilePicker.pickFiles(type: FileType.audio);
    if (!mounted) return;
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      setState(() {
        _soundSource = SoundSource.deviceFile;
        _soundPath = path;
      });
      await _previewPlayer.stop();
      if (!mounted) return;
      await _previewPlayer.play(DeviceFileSource(path));
    }
  }

  bool get _canSave {
    if (_type == AlarmType.repeating && _repeatDays.isEmpty) return false;
    if (_soundSource == SoundSource.bundled && _soundPath == null) return false;
    if (_soundSource == SoundSource.deviceFile && _soundPath == null) return false;
    return true;
  }

  Future<void> _selectBundledOrDefault(SoundSource source, String? path) async {
    setState(() {
      _soundSource = source;
      _soundPath = path;
    });
    final previewAsset = path ?? _defaultSoundAsset;
    await _previewPlayer.stop();
    if (!mounted) return;
    // audioplayers' AssetSource is relative to the assets/ root already.
    await _previewPlayer.play(
      AssetSource(previewAsset.replaceFirst('assets/', '')),
    );
  }

  String _currentSoundLabel() {
    switch (_soundSource) {
      case SoundSource.deviceDefault:
        return 'Default';
      case SoundSource.bundled:
        final match = _bundledSounds.entries.firstWhere(
          (e) => e.value == _soundPath,
          orElse: () => const MapEntry('Default', ''),
        );
        return match.key;
      case SoundSource.deviceFile:
        return _soundPath != null ? _soundPath!.split('/').last : 'Choose from device';
    }
  }

  Widget _soundCard({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        height: 100,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.volume_up : Icons.music_note_outlined,
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                color: selected ? theme.colorScheme.primary : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
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
        isEnabled: true,
        soundSource: _soundSource,
        soundPath: _soundSource == SoundSource.deviceDefault ? null : _soundPath,
        createdAt: widget.existingAlarm?.createdAt ?? now,
        updatedAt: now,
      );

      // saveAlarm handles both Firestore persistence AND native scheduling
      // internally now — no need to call scheduleAlarm separately here.
      await widget.alarmService.saveAlarm(alarm);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save alarm: $e')),
        );
      }
    }
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
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Select Sound'),
            subtitle: Text(_currentSoundLabel()),
            trailing: Icon(
              _soundPickerExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            onTap: () => setState(() => _soundPickerExpanded = !_soundPickerExpanded),
          ),
          if (_soundPickerExpanded)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _soundCard(
                  label: 'Default',
                  selected: _soundSource == SoundSource.deviceDefault,
                  onTap: () => _selectBundledOrDefault(SoundSource.deviceDefault, null),
                ),
                ..._bundledSounds.entries.map(
                  (e) => _soundCard(
                    label: e.key,
                    selected: _soundSource == SoundSource.bundled && _soundPath == e.value,
                    onTap: () => _selectBundledOrDefault(SoundSource.bundled, e.value),
                  ),
                ),
                _soundCard(
                  label: _soundSource == SoundSource.deviceFile && _soundPath != null
                      ? _soundPath!.split('/').last
                      : 'Choose from device',
                  selected: _soundSource == SoundSource.deviceFile,
                  onTap: _pickDeviceFile,
                ),
              ],
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