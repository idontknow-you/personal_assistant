import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Scroll-wheel time picker (hour + minute), each wheel also tappable to
/// open a keyboard for direct entry, plus a stacked AM/PM toggle to the
/// right. Replaces the Material `showTimePicker` circular dial.
///
/// Colors are pulled from the ambient Theme rather than hardcoded, so it
/// matches whatever ColorScheme the rest of AlarmFormScreen is using
/// (same primary/surfaceContainerHighest/etc. already used by the sound
/// cards in that screen) instead of assuming a dark background.
class TimeWheelPicker extends StatefulWidget {
  const TimeWheelPicker({
    super.key,
    required this.initialTime,
    required this.onChanged,
  });

  final TimeOfDay initialTime;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  State<TimeWheelPicker> createState() => _TimeWheelPickerState();
}

class _TimeWheelPickerState extends State<TimeWheelPicker> {
  static const _wheelHeight = 180.0;
  static const _itemExtent = 44.0;

  late int _displayHour; // 1-12
  late int _minute; // 0-59
  late DayPeriod _period;

  late FixedExtentScrollController _hourController;
  late FixedExtentScrollController _minuteController;

  @override
  void initState() {
    super.initState();
    final hourOfPeriod = widget.initialTime.hourOfPeriod;
    _displayHour = hourOfPeriod == 0 ? 12 : hourOfPeriod; // 0 means 12 (mid/noon)
    _minute = widget.initialTime.minute;
    _period = widget.initialTime.period;

    _hourController = FixedExtentScrollController(initialItem: _displayHour - 1);
    _minuteController = FixedExtentScrollController(initialItem: _minute);
  }

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  void _emit() {
    final hour24 = _period == DayPeriod.am
        ? _displayHour % 12 // 12 AM -> 0
        : (_displayHour % 12) + 12; // 12 PM -> 12
    widget.onChanged(TimeOfDay(hour: hour24, minute: _minute));
  }

  Future<void> _typeHour() async {
    final result = await _showTypeDialog(
      title: 'Hour',
      initial: _displayHour.toString(),
      min: 1,
      max: 12,
    );
    if (result == null) return;
    setState(() => _displayHour = result);
    await _hourController.animateToItem(
      result - 1,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    _emit();
  }

  Future<void> _typeMinute() async {
    final result = await _showTypeDialog(
      title: 'Minute',
      initial: _minute.toString().padLeft(2, '0'),
      min: 0,
      max: 59,
    );
    if (result == null) return;
    setState(() => _minute = result);
    await _minuteController.animateToItem(
      result,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
    _emit();
  }

  Future<int?> _showTypeDialog({
    required String title,
    required String initial,
    required int min,
    required int max,
  }) async {
    final controller = TextEditingController(text: initial);
    return showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Enter $title'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(border: OutlineInputBorder()),
          onSubmitted: (v) {
            final n = int.tryParse(v);
            if (n != null && n >= min && n <= max) {
              Navigator.of(dialogContext).pop(n);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null && n >= min && n <= max) {
                Navigator.of(dialogContext).pop(n);
              }
              // Silently ignore out-of-range/invalid input rather than
              // dismissing with a bad value -- dialog just stays open.
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  Widget _wheel({
    required FixedExtentScrollController controller,
    required int itemCount,
    required String Function(int index) label,
    required ValueChanged<int> onSelected,
    required VoidCallback onTapCenter,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 72,
      height: _wheelHeight,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Highlight band marking the centered/selected value.
          Container(
            height: _itemExtent,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
            ),
          ),
          ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: _itemExtent,
            diameterRatio: 1.6,
            perspective: 0.003,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: onSelected,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: itemCount,
              builder: (context, index) => Center(
                child: Text(
                  label(index),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w300,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          // Tap the centered value to open a keyboard for direct entry,
          // instead of only being able to scroll to it.
          SizedBox(
            height: _itemExtent,
            width: 72,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onTapCenter,
            ),
          ),
        ],
      ),
    );
  }

  Widget _periodButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 48,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: selected ? scheme.primary : scheme.surfaceContainerHighest,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.55),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _wheel(
          controller: _hourController,
          itemCount: 12,
          label: (i) => (i + 1).toString(),
          onSelected: (i) {
            _displayHour = i + 1;
            _emit();
          },
          onTapCenter: _typeHour,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            ':',
            style: TextStyle(fontSize: 28, color: scheme.onSurfaceVariant),
          ),
        ),
        _wheel(
          controller: _minuteController,
          itemCount: 60,
          label: (i) => i.toString().padLeft(2, '0'),
          onSelected: (i) {
            _minute = i;
            _emit();
          },
          onTapCenter: _typeMinute,
        ),
        const SizedBox(width: 16),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _periodButton(
              label: 'AM',
              selected: _period == DayPeriod.am,
              onTap: () {
                setState(() => _period = DayPeriod.am);
                _emit();
              },
            ),
            const SizedBox(height: 8),
            _periodButton(
              label: 'PM',
              selected: _period == DayPeriod.pm,
              onTap: () {
                setState(() => _period = DayPeriod.pm);
                _emit();
              },
            ),
          ],
        ),
      ],
    );
  }
}