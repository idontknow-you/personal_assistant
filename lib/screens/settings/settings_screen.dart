import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../main.dart';
import '../../services/auth_service.dart';
import '../../services/profile_service.dart';
import '../../services/tags/tag_service.dart';
import '../../services/app_lock/app_lock_service.dart';
import '../../theme/app_theme.dart';
import '../tags/tag_management_screen.dart';
import '../app_lock/app_lock_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.tagService});

  final TagService tagService;

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _SectionLabel('Account'),
          Card(
            // StreamBuilder keeps this card live: upgrading an anonymous
            // account to email (or signing in/out) updates it in place
            // without a manual rebuild.
            child: StreamBuilder<User?>(
              stream: authService.authStateChanges,
              builder: (context, snapshot) {
                final user = snapshot.data;
                final isAnonymous = user?.isAnonymous ?? true;
                return Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        isAnonymous
                            ? Icons.person_outline
                            : Icons.alternate_email,
                      ),
                      title: Text(
                        isAnonymous ? 'Anonymous account' : 'Email account',
                      ),
                      subtitle: Text(
                        isAnonymous
                            ? (user != null
                                ? 'ID: ${user.uid.substring(0, 8)}…'
                                : 'Not signed in')
                            : (user?.email ?? ''),
                      ),
                    ),
                    if (isAnonymous) ...[
                      const Divider(height: 1),
                      ListTile(
                        leading: Icon(
                          Icons.g_mobiledata,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: const Text('Link with Google'),
                        subtitle: const Text(
                          'Keep this data, sign in with Google from now on',
                        ),
                        onTap: () => _linkGoogle(context, authService),
                      ),
                    ],
                    const Divider(height: 1),
                    ListTile(
                      leading: Icon(Icons.logout, color: AppColors.error),
                      title: Text(
                        'Sign out',
                        style: TextStyle(color: AppColors.error),
                      ),
                      subtitle: Text(
                        isAnonymous
                            ? 'This will permanently lose access to your data'
                            : 'You can sign back in with your email & password',
                      ),
                      onTap: () =>
                          _confirmSignOut(context, authService, isAnonymous),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          _SectionLabel('Profile'),
          Card(
            child: StreamBuilder<User?>(
              stream: authService.authStateChanges,
              builder: (context, snapshot) {
                final user = snapshot.data;
                if (user == null) return const SizedBox.shrink();
                final profileService = ProfileService(user.uid);
                return StreamBuilder<String>(
                  stream: profileService.watchName(),
                  builder: (context, nameSnap) {
                    final name = nameSnap.data ?? '';
                    return ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: const Text('What should we call you?'),
                      subtitle: Text(
                        name.isEmpty
                            ? 'Not set'
                            : 'We\'ll call you “$name”',
                      ),
                      trailing: const Icon(Icons.edit_outlined, size: 20),
                      onTap: () =>
                          _promptName(context, profileService, name),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          _SectionLabel('Appearance'),
          Card(
            child: ValueListenableBuilder<ThemeMode>(
              valueListenable: themeNotifier,
              builder: (context, currentMode, _) {
                return RadioGroup<ThemeMode>(
                  groupValue: currentMode,
                  onChanged: (mode) => setThemeMode(mode!),
                  child: Column(
                    children: [
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.light,
                        title: const Text('Light'),
                        secondary: const Icon(Icons.light_mode_outlined),
                      ),
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.dark,
                        title: const Text('Dark'),
                        secondary: const Icon(Icons.dark_mode_outlined),
                      ),
                      RadioListTile<ThemeMode>(
                        value: ThemeMode.system,
                        title: const Text('System default'),
                        secondary: const Icon(Icons.brightness_auto_outlined),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          _SectionLabel('Theme'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ValueListenableBuilder<ThemePalette>(
                valueListenable: paletteNotifier,
                builder: (context, currentPalette, _) {
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: AppThemePresets.all.map((palette) {
                      final selected = palette.key == currentPalette.key;
                      return GestureDetector(
                        onTap: () => setThemePreset(palette.key),
                        child: Container(
                          width: 140,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? palette.primary
                                  : Theme.of(context).dividerColor,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: palette.preview
                                    .map((c) => Expanded(
                                          child: Container(
                                            height: 28,
                                            color: c,
                                          ),
                                        ))
                                    .toList(),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      palette.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  if (selected)
                                    Icon(Icons.check_circle,
                                        size: 16, color: palette.primary),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 24),

          _SectionLabel('Tags'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.label_outline),
              title: const Text('Manage tags'),
              subtitle: const Text('Rename or delete your tags'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TagManagementScreen(tagService: tagService),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          _SectionLabel('Security'),
          _AppLockSection(),
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
                  onTap: () => _confirmResetStreak(
                    context,
                    FirebaseAuth.instance.currentUser?.uid,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    AuthService authService,
    bool isAnonymous,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: Text(
          isAnonymous
              ? 'Your account is anonymous — it isn\'t linked to an email or '
                  'password. Signing out means you will PERMANENTLY lose access '
                  'to this account and all its data (tasks, alarms, streaks). '
                  'This cannot be undone.'
              : 'You can sign back in anytime with your email and password. '
                  'Your data stays safe in the cloud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              isAnonymous ? 'Sign out anyway' : 'Sign out',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await authService.signOut();
        // AuthGate listens to authStateChanges and will redirect to login.
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Sign out failed: $e')),
          );
        }
      }
    }
  }

  /// Links Google to the current anonymous account, preserving all
  /// existing data (same Firebase uid).
  Future<void> _linkGoogle(
    BuildContext context,
    AuthService authService,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link with Google?'),
        content: const Text(
          'Your current account is anonymous. Linking your Google account '
          'keeps all your tasks, alarms, habits and streaks — and lets you '
          'sign back in on any device with Google.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Link with Google'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    try {
      final linked = await authService.linkAnonymousWithGoogle();
      if (!context.mounted) return;
      if (linked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account linked with Google.')),
        );
      }
      // linked == false: user cancelled the Google picker — no feedback
      // needed, nothing changed.
    } catch (e) {
      if (!context.mounted) return;
      final message = _linkErrorMessage(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  /// Turns a linking failure into a clear, actionable message instead of
  /// a raw exception dump.
  String _linkErrorMessage(Object e) {
    if (e is UnsupportedError) {
      return e.message ?? 'Google linking is not supported on this platform.';
    }
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'account-exists-with-different-credential':
          return 'This Google account is already linked to another account.';
        case 'credential-already-in-use':
          return 'This Google account is already in use.';
        case 'network-request-failed':
          return 'Network error — check your connection.';
        default:
          return e.message ?? 'Failed to link Google.';
      }
    }
    if (e is GoogleSignInException) {
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError) {
        return 'Google sign-in is not configured yet. Enable the Google '
            'provider in Firebase and add your app\'s SHA-1 fingerprint.';
      }
      return e.description ?? 'Google sign-in failed.';
    }
    return 'Failed to link Google: $e';
  }

  /// Dialog to set (or change) the name the app uses to refer to you.
  Future<void> _promptName(
    BuildContext context,
    ProfileService profileService,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('What should we call you?'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            hintText: 'Your name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || !context.mounted) return;
    await profileService.setName(result);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isEmpty
                ? 'Name cleared.'
                : 'Got it — we\'ll call you “$result”.',
          ),
        ),
      );
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

class _AppLockSection extends StatefulWidget {
  @override
  State<_AppLockSection> createState() => _AppLockSectionState();
}

class _AppLockSectionState extends State<_AppLockSection> {
  bool _hasPin = false;
  bool _enabled = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final hasPin = await AppLockService.hasPin();
    final enabled = await AppLockService.isEnabled();
    final biometricAvailable = await AppLockService.canUseBiometric();
    final biometricEnabled = await AppLockService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _hasPin = hasPin;
        _enabled = enabled;
        _biometricAvailable = biometricAvailable;
        _biometricEnabled = biometricEnabled;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    if (value && !_hasPin) {
      // Need to set PIN first
      final navigator = Navigator.of(context);
      await navigator.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AppLockScreen(
          isSetup: true,
          onUnlocked: () {
            navigator.pop();
            _load();
          },
        ),
      ));
      return;
    }
    await AppLockService.setEnabled(value);
    setState(() => _enabled = value);
  }

  Future<void> _changeOrRemovePin() async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('App Lock'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'change'),
            child: const Text('Change PIN'),
          ),
          if (_hasPin)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, 'remove'),
              child: Text('Remove PIN',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
        ],
      ),
    );

    if (action == 'change') {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      await navigator.push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AppLockScreen(
          isSetup: true,
          onUnlocked: () {
            navigator.pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PIN changed.')),
            );
          },
        ),
      ));
    } else if (action == 'remove') {
      await AppLockService.removePin();
      setState(() { _hasPin = false; _enabled = false; });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('App lock removed.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SizedBox.shrink();

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('App Lock'),
            subtitle: Text(
              _hasPin
                  ? (_enabled ? 'Enabled — PIN required on launch' : 'PIN set but disabled')
                  : 'No PIN set',
            ),
            value: _enabled,
            onChanged: _toggle,
          ),
          if (_hasPin) ...[
            const Divider(height: 1),
            if (_biometricAvailable)
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Biometric unlock'),
                subtitle: const Text('Use fingerprint or face to unlock'),
                value: _biometricEnabled && _enabled,
                onChanged: _enabled
                    ? (v) async {
                        await AppLockService.setBiometricEnabled(v);
                        setState(() => _biometricEnabled = v);
                      }
                    : null,
              ),
            ListTile(
              leading: const Icon(Icons.key),
              title: const Text('Change or remove PIN'),
              onTap: _changeOrRemovePin,
            ),
          ],
        ],
      ),
    );
  }
}