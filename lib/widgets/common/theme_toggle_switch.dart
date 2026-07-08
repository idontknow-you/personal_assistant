import 'package:flutter/material.dart';
import '../../main.dart';

class ThemeToggleSwitch extends StatelessWidget {
  const ThemeToggleSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(isDark ? Icons.dark_mode : Icons.light_mode, size: 20),
            Switch(
              value: isDark,
              onChanged: (value) {
                setThemeMode(value ? ThemeMode.dark : ThemeMode.light);
              },
            ),
          ],
        );
      },
    );
  }
}