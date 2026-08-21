import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Single shared GoogleSignIn instance — google_sign_in 7.x exposes only
  /// [GoogleSignIn.instance] (the constructor is private) and requires
  /// initialize() to be called exactly once before any other method.
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  bool _googleInitialized = false;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;

  /// google_sign_in 7.x only ships platform implementations for Android,
  /// iOS, and web. On desktop (Windows/macOS/Linux) the plugin calls throw
  /// MissingPluginException — catch that up front and fail with a clear
  /// message instead of a confusing raw plugin error.
  bool get _googleSignInSupported =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// google_sign_in 7.x: initialize() must run exactly once and be awaited
  /// before authenticate(). Guarded so repeated calls are no-ops.
  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await _googleSignIn.initialize();
    _googleInitialized = true;
  }

  void _ensureGoogleSupported() {
    if (!_googleSignInSupported) {
      throw UnsupportedError(
        'Google sign-in is not supported on this platform yet — '
        'use the Android app or a web browser.',
      );
    }
  }

  /// Returns true if the user cancelled/closed the Google flow (so callers
  /// can treat it as "no action"), false otherwise.
  bool _isGoogleCancellation(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.canceled:
      case GoogleSignInExceptionCode.interrupted:
      case GoogleSignInExceptionCode.uiUnavailable:
        return true;
      default:
        return false;
    }
  }

  Future<void> signInAnonymously() async {
    await _auth.signInAnonymously();
  }

  /// Signs in (or up) with the user's Google account. Returns false if
  /// the user cancelled the Google account picker — callers can treat
  /// that as "no action" rather than an error.
  Future<bool> signInWithGoogle() async {
    _ensureGoogleSupported();
    await _ensureGoogleInitialized();
    try {
      final googleUser = await _googleSignIn.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) return false;
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await _auth.signInWithCredential(credential);
      return true;
    } on GoogleSignInException catch (e) {
      if (_isGoogleCancellation(e)) return false;
      rethrow;
    }
  }

  /// Upgrades the current anonymous account to a Google account by
  /// linking credentials to the SAME Firebase uid, so all existing data
  /// (tasks, alarms, habits, streaks) carries over. Returns false if the
  /// user cancelled the Google picker. Throws if there's no anonymous
  /// account to upgrade.
  Future<bool> linkAnonymousWithGoogle() async {
    _ensureGoogleSupported();
    final user = _auth.currentUser;
    if (user == null || !user.isAnonymous) {
      throw FirebaseAuthException(
        code: 'not-anonymous',
        message: 'No anonymous account to upgrade.',
      );
    }
    await _ensureGoogleInitialized();
    try {
      final googleUser = await _googleSignIn.authenticate();
      final idToken = googleUser.authentication.idToken;
      if (idToken == null) return false;
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      await user.linkWithCredential(credential);
      return true;
    } on GoogleSignInException catch (e) {
      if (_isGoogleCancellation(e)) return false;
      rethrow;
    }
  }

  /// Signs in an existing email/password account.
  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Creates a brand-new email/password account.
  Future<void> registerWithEmail(String email, String password) async {
    await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Sends a password-reset email for the given account.
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    // Only touch Google on platforms that actually implement it. On
    // desktop the plugin has no implementation — the call can hang or
    // throw, which would BLOCK the Firebase sign-out below and make the
    // button appear completely dead.
    if (_googleSignInSupported) {
      // Sign out of Google too, not just Firebase, so the next sign-in
      // shows the account picker instead of silently reusing the last
      // account.
      try {
        await _googleSignIn.signOut();
      } catch (_) {
        // Best-effort — Firebase sign-out below is what actually matters.
      }
    }
    await _auth.signOut();
  }
}