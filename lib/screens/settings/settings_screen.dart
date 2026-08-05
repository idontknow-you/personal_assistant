import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../main.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final user = authService.currentUser;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('Account'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Anonymous account'),
                  subtitle: Text(
                    user != null
                        ? 'ID: ${user.uid.substring(0, 8)}…'
                        : 'Not signed in',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.logout, color: AppColors.error),
                  title: Text(
                    'Sign out',
                    style: TextStyle(color: AppColors.error),
                  ),
                  subtitle: const Text('This will permanently lose access to your data'),
                  onTap: () => _confirmSignOut(context, authService),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _SectionLabel('Appearance'),
          Card(
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, currentMode, _) {
                return Column(
                  children: [
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.light,
                      groupValue: currentMode,
                      title: const Text('Light'),
                      secondary: const Icon(Icons.light_mode_outlined),
                      onChanged: (mode) => setThemeMode(mode!),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.dark,
                      groupValue: currentMode,
                      title: const Text('Dark'),
                      secondary: const Icon(Icons.dark_mode_outlined),
                      onChanged: (mode) => setThemeMode(mode!),
                    ),
                    RadioListTile<ThemeMode>(
                      value: ThemeMode.system,
                      groupValue: currentMode,
                      title: const Text('System default'),
                      secondary: const Icon(Icons.brightness_auto_outlined),
                      onChanged: (mode) => setThemeMode(mode!),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          _SectionLabel('About & Data'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Personal OS'),
                  subtitle: Text('v1.0.0'),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.local_fire_department_outlined,
                      color: AppColors.warning),
                  title: const Text('Reset current streak'),
                  subtitle: const Text(
                    'Sets current streak to 0. Best streak is kept.',
                  ),
                  onTap: () => _confirmResetStreak(context, user?.uid),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context, AuthService authService) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your account is anonymous — it isn\'t linked to an email or password. '
          'Signing out means you will PERMANENTLY lose access to this account and '
          'all its data (tasks, alarms, streaks). This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sign out anyway', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await authService.signOut();
      // AuthGate listens to authStateChanges and will redirect to login.
    }
  }

  Future<void> _confirmResetStreak(BuildContext context, String? uid) async {
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset current streak?'),
        content: const Text(
          'This sets your current streak to 0 and clears the last-checked date. '
          'Your best streak record is not affected. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Reset', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('meta')
          .doc('streak')
          .set(
        {
          'currentStreak': 0,
          'lastCheckedDate': null,
        },
        SetOptions(merge: true),
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Streak reset.')),
        );
      }
    }
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}