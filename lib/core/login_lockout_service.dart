import 'package:shared_preferences/shared_preferences.dart';

class LoginLockoutStatus {
  const LoginLockoutStatus({
    required this.failedAttempts,
    required this.lockedUntil,
  });

  final int failedAttempts;
  final DateTime? lockedUntil;

  bool get isLocked =>
      lockedUntil != null && lockedUntil!.isAfter(DateTime.now());
}

class LoginLockoutService {
  static const int _maxFailedAttempts = 7;
  static const Duration _lockDuration = Duration(minutes: 120);
  static const String _countPrefix = 'login_failed_count_';
  static const String _lockedUntilPrefix = 'login_locked_until_';

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  Future<LoginLockoutStatus> getStatus(String email) async {
    final normalizedEmail = _normalizeEmail(email);
    final prefs = await SharedPreferences.getInstance();
    final lockedUntilMillis = prefs.getInt('$_lockedUntilPrefix$normalizedEmail');

    if (lockedUntilMillis != null) {
      final lockedUntil = DateTime.fromMillisecondsSinceEpoch(
        lockedUntilMillis,
      );
      if (lockedUntil.isAfter(DateTime.now())) {
        return LoginLockoutStatus(
          failedAttempts: prefs.getInt('$_countPrefix$normalizedEmail') ?? 0,
          lockedUntil: lockedUntil,
        );
      }
      await clear(email);
    }

    return LoginLockoutStatus(
      failedAttempts: prefs.getInt('$_countPrefix$normalizedEmail') ?? 0,
      lockedUntil: null,
    );
  }

  Future<LoginLockoutStatus> registerFailedAttempt(String email) async {
    final normalizedEmail = _normalizeEmail(email);
    final prefs = await SharedPreferences.getInstance();
    final currentStatus = await getStatus(email);
    final failedAttempts = currentStatus.failedAttempts + 1;

    if (failedAttempts >= _maxFailedAttempts) {
      final lockedUntil = DateTime.now().add(_lockDuration);
      await prefs.setInt('$_countPrefix$normalizedEmail', failedAttempts);
      await prefs.setInt(
        '$_lockedUntilPrefix$normalizedEmail',
        lockedUntil.millisecondsSinceEpoch,
      );
      return LoginLockoutStatus(
        failedAttempts: failedAttempts,
        lockedUntil: lockedUntil,
      );
    }

    await prefs.setInt('$_countPrefix$normalizedEmail', failedAttempts);
    await prefs.remove('$_lockedUntilPrefix$normalizedEmail');
    return LoginLockoutStatus(
      failedAttempts: failedAttempts,
      lockedUntil: null,
    );
  }

  Future<void> clear(String email) async {
    final normalizedEmail = _normalizeEmail(email);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_countPrefix$normalizedEmail');
    await prefs.remove('$_lockedUntilPrefix$normalizedEmail');
  }
}
