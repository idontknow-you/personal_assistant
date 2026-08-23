import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_lock/app_lock_service.dart';

/// Shown on app launch if PIN is set and enabled.
/// Modes: verify (unlock) or setup (create/change PIN).
class AppLockScreen extends StatefulWidget {
  /// If true, user is setting a new PIN for the first time.
  final bool isSetup;

  /// Called when the user successfully unlocks or sets their PIN.
  final VoidCallback onUnlocked;

  const AppLockScreen({
    super.key,
    this.isSetup = false,
    required this.onUnlocked,
  });

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen> {
  String _entered = '';
  String _error = '';
  bool _isSetupMode = false;
  bool _isConfirmStep = false; // for setup: confirm PIN step
  String _firstPin = ''; // for setup: first entry
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _isSetupMode = widget.isSetup;
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final available = await AppLockService.canUseBiometric();
    final enabled = await AppLockService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricAvailable = available;
        _biometricEnabled = enabled;
      });
    }
    // Auto-prompt biometric on launch if enabled and in verify mode
    if (available && enabled && !_isSetupMode) {
      Future.delayed(const Duration(milliseconds: 500), _tryBiometric);
    }
  }

  Future<void> _tryBiometric() async {
    final success = await AppLockService.authenticateWithBiometric();
    if (success && mounted) {
      widget.onUnlocked();
    }
  }

  void _onKeyPressed(String digit) {
    if (_entered.length >= 6) return;
    HapticFeedback.lightImpact();
    setState(() {
      _entered += digit;
      _error = '';
    });

    // Auto-submit at 4 digits (minimum) — or 6 if user entered 6
    if (_entered.length >= 4) {
      // Small delay so user sees the last dot
      Future.delayed(const Duration(milliseconds: 150), _submit);
    }
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    HapticFeedback.lightImpact();
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = '';
    });
  }

  Future<void> _submit() async {
    final pin = _entered;

    if (_isSetupMode) {
      if (!_isConfirmStep) {
        // First entry — save and ask for confirmation
        if (pin.length < 4) {
          setState(() {
            _error = 'PIN must be at least 4 digits';
            _entered = '';
          });
          return;
        }
        setState(() {
          _firstPin = pin;
          _isConfirmStep = true;
          _entered = '';
          _error = '';
        });
      } else {
        // Confirmation step
        if (pin == _firstPin) {
          await AppLockService.setPin(pin);
          widget.onUnlocked();
        } else {
          setState(() {
            _error = 'PINs don\'t match — try again';
            _entered = '';
            _isConfirmStep = false;
            _firstPin = '';
          });
        }
      }
    } else {
      // Verify mode
      final correct = await AppLockService.verify(pin);
      if (correct) {
        widget.onUnlocked();
      } else {
        HapticFeedback.heavyImpact();
        setState(() {
          _error = 'Wrong PIN';
          _entered = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    String title;
    String subtitle;
    if (_isSetupMode) {
      if (_isConfirmStep) {
        title = 'Confirm PIN';
        subtitle = 'Re-enter your PIN to confirm';
      } else {
        title = 'Set PIN';
        subtitle = 'Choose a 4–6 digit PIN to lock the app';
      }
    } else {
      title = 'Enter PIN';
      subtitle = 'Enter your PIN to unlock';
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Lock icon
              Icon(
                Icons.lock_outline,
                size: 64,
                color: cs.primary,
              ),

              const SizedBox(height: 24),

              Text(
                title,
                style: ts.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),

              const SizedBox(height: 8),

              Text(
                subtitle,
                style: ts.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),

              const SizedBox(height: 32),

              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  final filled = i < _entered.length;
                  return Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? cs.primary : cs.surfaceContainerHighest,
                      border: filled ? null : Border.all(color: cs.outline),
                    ),
                  );
                }),
              ),

              // Error message
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _error,
                  style: TextStyle(color: cs.error, fontWeight: FontWeight.w500),
                ),
              ],

              const Spacer(flex: 1),

              // Keypad
              _buildKeypad(cs),

              const SizedBox(height: 16),

              // Biometric + Backspace row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Biometric button
                    if (_biometricAvailable && _biometricEnabled && !_isSetupMode)
                      IconButton(
                        onPressed: _tryBiometric,
                        icon: const Icon(Icons.fingerprint, size: 32),
                        tooltip: 'Unlock with fingerprint',
                      )
                    else
                      const SizedBox(width: 48),
                    // Backspace
                    IconButton(
                      onPressed: _onBackspace,
                      icon: const Icon(Icons.backspace_outlined),
                      iconSize: 28,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),

              SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad(ColorScheme cs) {
    return Column(
      children: [
        for (final row in [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', ''],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: row.map((digit) {
                if (digit.isEmpty) return const SizedBox(width: 72, height: 56);
                return SizedBox(
                  width: 72,
                  height: 56,
                  child: FilledButton(
                    onPressed: () => _onKeyPressed(digit),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.surfaceContainerHighest,
                      foregroundColor: cs.onSurface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      digit,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    );
  }
}
