import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'home_shell.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();

  // Guards against calling signInAnonymously() more than once. Previously
  // this call lived inside build(), which can run repeatedly (parent
  // rebuilds, hot reload, etc.) — each time the stream's first value was
  // still "no user" during that async gap, build() would fire off another
  // sign-in attempt. Doing it once in initState() instead means it only
  // ever runs a single time per AuthGate lifetime.
  bool _signInStarted = false;

  @override
  void initState() {
    super.initState();
    _signInIfNeeded();
  }

  Future<void> _signInIfNeeded() async {
    if (_signInStarted) return;
    _signInStarted = true;
    // If there's already a signed-in anonymous user (e.g. hot restart),
    // signInAnonymously() in AuthService should just return the existing
    // user rather than creating a new one — this call is safe to make
    // unconditionally either way. The StreamBuilder below shows a loading
    // state until this resolves and the stream emits the user.
    await _authService.signInAnonymously();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasData) {
          return HomeShell(uid: snapshot.data!.uid);
        }
        // No user yet — _signInIfNeeded() (called once, in initState) is
        // already handling sign-in in the background. Just show loading
        // until the stream emits the new user.
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}