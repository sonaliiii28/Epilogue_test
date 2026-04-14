import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricLoginService {
  static const _enabledKey = 'biometric_login_enabled';
  static const _credentialLoginKey = 'biometric_credential_login_completed';
  static const _failedAttemptsKey = 'biometric_login_failed_attempts';

  final LocalAuthentication _localAuth;
  final int maxFailedAttempts;

  BiometricLoginService({
    LocalAuthentication? localAuth,
    this.maxFailedAttempts = 3,
  }) : _localAuth = localAuth ?? LocalAuthentication();

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (!enabled) {
      await prefs.remove(_failedAttemptsKey);
    }
  }

  Future<void> markCredentialLoginCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_credentialLoginKey, true);
    await prefs.remove(_failedAttemptsKey);
  }

  Future<bool> hasCompletedCredentialLogin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_credentialLoginKey) ?? false;
  }

  Future<int> getFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_failedAttemptsKey) ?? 0;
  }

  Future<void> clearFailedAttempts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_failedAttemptsKey);
  }

  Future<int> registerFailedAttempt() async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getInt(_failedAttemptsKey) ?? 0;
    final next = current + 1;
    await prefs.setInt(_failedAttemptsKey, next);
    return next;
  }

  Future<bool> isLockedOut() async {
    final attempts = await getFailedAttempts();
    return attempts >= maxFailedAttempts;
  }

  Future<bool> isDeviceSupported() async {
    try {
      final supported = await _localAuth.isDeviceSupported();
      if (!supported) return false;
      final canCheck = await _localAuth.canCheckBiometrics;
      if (canCheck) return true;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty;
    } on PlatformException {
      return false;
    }
  }

  Future<bool> authenticate({required String reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException {
      return false;
    }
  }
}
