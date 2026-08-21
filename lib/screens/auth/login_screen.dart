import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';

/// Full-screen auth entry point shown by AuthGate when no user is signed
/// in. Deliberately NOT themed — always renders on a plain light
/// background with simple styling, so the first screen looks clean and
/// consistent regardless of the app's palette/dark mode.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Fixed light colors — independent of Theme.of(context), so this screen
  // never follows the app palette or dark mode.
  static const _bg = Color(0xFFF7F8FA);
  static const _surface = Colors.white;
  static const _text = Color(0xFF1F2937);
  static const _muted = Color(0xFF6B7280);
  static const _border = Color(0xFFE5E7EB);
  static const _googleBlue = Color(0xFF4285F4);

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _showEmailForm = false;
  bool _isRegistering = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Maps Firebase auth error codes to human-readable messages.
  String _friendlyError(Object error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'invalid-email':
          return 'That email address doesn\'t look valid.';
        case 'user-not-found':
        case 'wrong-password':
          return 'Incorrect email or password.';
        case 'email-already-in-use':
          return 'An account with that email already exists.';
        case 'weak-password':
          return 'Password must be at least 6 characters.';
        case 'network-request-failed':
          return 'Network error — check your connection.';
        case 'too-many-requests':
          return 'Too many attempts — try again later.';
        default:
          return error.message ?? 'Something went wrong.';
      }
    }
    if (error is UnsupportedError) {
      return error.message ?? 'Not supported on this platform.';
    }
    return error.toString();
  }

  Future<void> _signInWithGoogle() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final signedIn = await widget.authService.signInWithGoogle();
      if (!mounted) return;
      if (!signedIn) {
        // User cancelled the Google account picker — just reset.
        setState(() => _busy = false);
      }
      // On success, AuthGate's authStateChanges stream fires and swaps in
      // HomeShell automatically, so there's nothing to do here.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      if (_isRegistering) {
        await widget.authService.registerWithEmail(email, password);
      } else {
        await widget.authService.signInWithEmail(email, password);
      }
      // Success — AuthGate's authStateChanges stream fires and swaps in
      // HomeShell automatically.
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _continueAsGuest() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.authService.signInAnonymously();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email address first.');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password reset email sent — check your inbox.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = _friendlyError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.dashboard_customize_outlined,
                    size: 56,
                    color: _googleBlue,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Personal OS',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _text,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Sign in to access your data',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: _muted, fontSize: 14),
                  ),
                  const SizedBox(height: 28),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Primary: Google sign-in — classic white button
                        // with the Google "G", not the app's themed button.
                        SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            onPressed: _busy ? null : _signInWithGoogle,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: _text,
                              side: const BorderSide(color: _border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            icon: _busy
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: _googleBlue,
                                    ),
                                  )
                                : const Icon(
                                    Icons.g_mobiledata,
                                    size: 24,
                                    color: _googleBlue,
                                  ),
                            label: const Text(
                              'Continue with Google',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_error != null) ...[
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: AppColors.error,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        // Secondary: toggle the email/password form.
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => setState(() {
                                    _showEmailForm = !_showEmailForm;
                                    _error = null;
                                  }),
                          style: TextButton.styleFrom(
                            foregroundColor: _muted,
                          ),
                          icon: Icon(
                            _showEmailForm
                                ? Icons.expand_less
                                : Icons.alternate_email,
                            size: 18,
                          ),
                          label: Text(
                            _showEmailForm
                                ? 'Hide email sign-in'
                                : 'Use email & password instead',
                          ),
                        ),
                        if (_showEmailForm) ...[
                          const SizedBox(height: 8),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: false,
                                label: Text('Sign in'),
                              ),
                              ButtonSegment(
                                value: true,
                                label: Text('Create account'),
                              ),
                            ],
                            selected: {_isRegistering},
                            onSelectionChanged: (s) {
                              setState(() {
                                _isRegistering = s.first;
                                _error = null;
                              });
                            },
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            autocorrect: false,
                            textInputAction: TextInputAction.next,
                            style: const TextStyle(color: _text),
                            decoration: InputDecoration(
                              labelText: 'Email',
                              labelStyle: const TextStyle(color: _muted),
                              filled: true,
                              fillColor: const Color(0xFFFAFAFA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: _border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: _border),
                              ),
                              prefixIcon: const Icon(
                                Icons.mail_outline,
                                color: _muted,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passwordController,
                            obscureText: true,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _submitEmail(),
                            style: const TextStyle(color: _text),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              labelStyle: const TextStyle(color: _muted),
                              filled: true,
                              fillColor: const Color(0xFFFAFAFA),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: _border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: _border),
                              ),
                              prefixIcon: const Icon(
                                Icons.lock_outline,
                                color: _muted,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 44,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _googleBlue,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: _busy ? null : _submitEmail,
                              child: Text(
                                _isRegistering
                                    ? 'Create account'
                                    : 'Sign in',
                              ),
                            ),
                          ),
                          if (!_isRegistering) ...[
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: _muted,
                              ),
                              onPressed: _busy ? null : _resetPassword,
                              child: const Text('Forgot password?'),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _busy ? null : _continueAsGuest,
                    style: TextButton.styleFrom(foregroundColor: _muted),
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('Continue without an account'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
