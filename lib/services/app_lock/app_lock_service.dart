import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App lock using a 4-digit PIN with brute-force protection.
/// PIN is stored as a salted SHA-256 hash in SharedPreferences.
/// After 5 failed attempts, the user is locked out for 30 seconds.
class AppLockService {
  static const _hashKey = 'app_lock_pin_hash';
  static const _saltKey = 'app_lock_pin_salt';
  static const _enabledKey = 'app_lock_enabled';
  static const _failCountKey = 'app_lock_fail_count';
  static const _lockoutUntilKey = 'app_lock_lockout_until';

  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(seconds: 30);

  /// Has the user set a PIN?
  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_hashKey);
  }

  /// Is app lock currently enabled?
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_enabledKey) != true) return false;
    return hasPin();
  }

  /// Set or change the PIN.
  static Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    final hash = _hashPin(pin, salt);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hashKey, hash);
    await prefs.setString(_saltKey, salt);
    await prefs.setBool(_enabledKey, true);
    await _resetAttempts();
  }

  /// Verify a PIN attempt. Returns true if correct.
  /// Implements lockout after maxAttempts failures.
  static Future<bool> verify(String pin) async {
    final prefs = await SharedPreferences.getInstance();

    // Check lockout
    final lockoutUntil = prefs.getInt(_lockoutUntilKey);
    if (lockoutUntil != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now < lockoutUntil) {
        return false; // Still locked out
      }
      // Lockout expired — reset
      await _resetAttempts();
    }

    final storedHash = prefs.getString(_hashKey);
    final salt = prefs.getString(_saltKey);
    if (storedHash == null || salt == null) return false;

    final correct = _hashPin(pin, salt) == storedHash;
    if (correct) {
      await _resetAttempts();
    } else {
      await _recordFailure();
    }
    return correct;
  }

  /// How many seconds remain in the lockout (0 if not locked out).
  static Future<int> lockoutSecondsRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final lockoutUntil = prefs.getInt(_lockoutUntilKey);
    if (lockoutUntil == null) return 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    final remaining = ((lockoutUntil - now) / 1000).ceil();
    return remaining > 0 ? remaining : 0;
  }

  /// Number of failed attempts so far (before lockout triggers).
  static Future<int> failedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_failCountKey) ?? 0;
  }

  /// Remove the PIN entirely (disable lock).
  static Future<void> removePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashKey);
    await prefs.remove(_saltKey);
    await prefs.setBool(_enabledKey, false);
    await _resetAttempts();
  }

  /// Toggle lock on/off (only if PIN is set).
  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  // --- Internal helpers ---

  static Future<void> _recordFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final count = (prefs.getInt(_failCountKey) ?? 0) + 1;
    await prefs.setInt(_failCountKey, count);
    if (count >= maxAttempts) {
      final lockoutUntil =
          DateTime.now().add(lockoutDuration).millisecondsSinceEpoch;
      await prefs.setInt(_lockoutUntilKey, lockoutUntil);
    }
  }

  static Future<void> _resetAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_failCountKey);
    await prefs.remove(_lockoutUntilKey);
  }

  static String _generateSalt() {
    final rng = Random.secure();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    return base64Encode(bytes);
  }

  static String _hashPin(String pin, String salt) {
    final bytes = utf8.encode('$pin:$salt');
    return sha256.convert(bytes).toString();
  }
}
