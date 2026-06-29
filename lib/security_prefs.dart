import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles everything related to app-lock security:
/// - Whether a PIN has been set (no PIN at all on first install).
/// - Hashing + verifying the PIN (the raw PIN is never stored).
/// - Whether biometric (fingerprint / Face ID) unlock is enabled.
///
/// All values live in SharedPreferences, which is local, on-device storage.
class SecurityPrefs {
  static const _kPinHash = 'security_pin_hash';
  static const _kPinSalt = 'security_pin_salt';
  static const _kBiometricEnabled = 'security_biometric_enabled';

  /// Returns true if the user has ever set a PIN. On a fresh install this
  /// is false, so the app opens straight to the home screen with no lock.
  static Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    final hash = prefs.getString(_kPinHash);
    return hash != null && hash.isNotEmpty;
  }

  /// Sets (or replaces) the PIN. Generates a fresh random salt every time
  /// so the stored hash isn't reusable/comparable across changes.
  static Future<void> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _generateSalt();
    final hash = _hash(pin, salt);
    await prefs.setString(_kPinSalt, salt);
    await prefs.setString(_kPinHash, hash);
  }

  /// Removes the PIN entirely (app goes back to "no password" state).
  /// Also disables biometrics, since biometric unlock is just a shortcut
  /// for the PIN and shouldn't be left on with nothing backing it up.
  static Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPinHash);
    await prefs.remove(_kPinSalt);
    await prefs.setBool(_kBiometricEnabled, false);
  }

  /// Verifies a PIN attempt against the stored hash.
  static Future<bool> verifyPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final storedHash = prefs.getString(_kPinHash);
    final salt = prefs.getString(_kPinSalt);
    if (storedHash == null || salt == null) return false;
    return _hash(pin, salt) == storedHash;
  }

  /// Whether the user has switched biometric unlock on in Settings.
  /// This is just a preference flag — actual biometric availability on
  /// the device is checked separately via local_auth.
  static Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometricEnabled) ?? false;
  }

  /// Enables/disables biometric unlock. Only meaningful while a PIN
  /// exists, since biometrics is an alternative entry method that still
  /// falls back to the PIN.
  static Future<void> setBiometricEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricEnabled, enabled);
  }

  static String _generateSalt() {
    final rand = Random.secure();
    final bytes = List<int>.generate(16, (_) => rand.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _hash(String pin, String salt) {
    final bytes = utf8.encode('$salt:$pin');
    return sha256.convert(bytes).toString();
  }
}
