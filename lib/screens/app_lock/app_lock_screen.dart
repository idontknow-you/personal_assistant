import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_lock/app_lock_service.dart';

/// Shown on app launch or when app is backgrounded.
class AppLockScreen extends StatefulWidget {
  final bool isSetup;
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
  bool _isConfirmStep = false;
  String _firstPin = '';

  // Lockout state
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  static const int _pinLength = 4;

  @override
  void initState() {
    super.initState();
    _isSetupMode = widget.isSetup;
    _checkLockout();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkLockout() async {
    final remaining = await AppLockService.lockoutSecondsRemaining();
    if (remaining > 0 && mounted) {
      setState(() => _lockoutSeconds = remaining);
      _startLockoutTimer();
    }
  }

  void _startLockoutTimer() {
    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _lockoutSeconds--;
        if (_lockoutSeconds <= 0) {
          _lockoutSeconds = 0;
          timer.cancel();
          _error = '';
          _entered = '';
        }
      });
    });
  }

  void _onKeyPressed(String digit) {
    if (_entered.length >= _pinLength) return;
    if (_lockoutSeconds > 0) return;
    HapticFeedback.lightImpact();
    setState(() {
      _entered += digit;
      _error = '';
    });

    if (_entered.length == _pinLength) {
      Future.delayed(const Duration(milliseconds: 150), _submit);
    }
  }

  void _onBackspace() {
    if (_entered.isEmpty || _lockoutSeconds > 0) return;
    HapticFeedback.lightImpact();
    setState(() {
      _entered = _entered.substring(0, _entered.length - 1);
      _error = '';
    });
  }

  Future<void> _submit() async {
    final pin = _entered;
    if (pin.length != _pinLength) return;

    if (_isSetupMode) {
      if (!_isConfirmStep) {
        setState(() {
          _firstPin = pin;
          _isConfirmStep = true;
          _entered = '';
          _error = '';
        });
      } else {
        if (pin == _firstPin) {
          await AppLockService.setPin(pin);
          widget.onUnlocked();
        } else {
          HapticFeedback.heavyImpact();
          setState(() {
            _error = 'PINs don\'t match — try again';
            _entered = '';
            _isConfirmStep = false;
            _firstPin = '';
          });
        }
      }
    } else {
      final correct = await AppLockService.verify(pin);
      if (correct) {
        widget.onUnlocked();
      } else {
        HapticFeedback.heavyImpact();
        final remaining = await AppLockService.lockoutSecondsRemaining();
        if (remaining > 0) {
          setState(() {
            _error = 'Too many attempts. Wait ${remaining}s.';
            _entered = '';
            _lockoutSeconds = remaining;
          });
          _startLockoutTimer();
        } else {
          final attempts = await AppLockService.failedAttempts();
          final left = AppLockService.maxAttempts - attempts;
          setState(() {
            _error = left > 0
                ? 'Wrong PIN ($left attempts left)'
                : 'Wrong PIN';
            _entered = '';
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;

    String title;
    String subtitle;
    if (_lockoutSeconds > 0) {
      title = 'Locked Out';
      subtitle = 'Wait $_lockoutSeconds seconds';
    } else if (_isSetupMode) {
      if (_isConfirmStep) {
        title = 'Confirm PIN';
        subtitle = 'Re-enter your 4-digit PIN';
      } else {
        title = 'Set PIN';
        subtitle = 'Choose a 4-digit PIN to lock the app';
      }
    } else {
      title = 'Enter PIN';
      subtitle = 'Enter your 4-digit PIN to unlock';
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: cs.surface,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),

              Icon(
                _lockoutSeconds > 0 ? Icons.lock_clock : Icons.lock_outline,
                size: 64,
                color: _lockoutSeconds > 0 ? cs.error : cs.primary,
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

              // PIN dots — exactly 4
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (i) {
                  final filled = i < _entered.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? cs.primary : cs.surfaceContainerHighest,
                      border: filled ? null : Border.all(color: cs.outline),
                    ),
                  );
                }),
              ),

              if (_error.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _error,
                  style: TextStyle(
                    color: cs.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],

              const Spacer(flex: 1),

              _buildKeypad(cs),

              const SizedBox(height: 16),

              // Backspace
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
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
                    onPressed: _lockoutSeconds > 0
                        ? null
                        : () => _onKeyPressed(digit),
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
