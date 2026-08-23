import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App lock using a 4-digit PIN.
/// PIN is stored as a salted SHA-256 hash in SharedPreferences.
class AppLockService {
  static const _hashKey = 'app_lock_pin_hash';
  static const _saltKey = 'app_lock_pin_salt';
  static const _enabledKey = 'app_lock_enabled';

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
  }

  /// Verify a PIN attempt.
  static Future<bool> verify(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final storedHash = prefs.getString(_hashKey);
    final salt = prefs.getString(_saltKey);
    if (storedHash == null || salt == null) return false;
    return _hashPin(pin, salt) == storedHash;
  }

  /// Remove the PIN entirely (disable lock).
  static Future<void> removePin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hashKey);
    await prefs.remove(_saltKey);
    await prefs.setBool(_enabledKey, false);
  }

  /// Toggle lock on/off (only if PIN is set).
  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  // --- Internal helpers ---

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
