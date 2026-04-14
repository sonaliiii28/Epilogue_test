import 'package:shared_preferences/shared_preferences.dart';

class PendingInvite {
  const PendingInvite({
    required this.email,
    required this.token,
    this.role,
    required this.savedAt,
  });

  final String email;
  final String token;
  final String? role;
  final DateTime savedAt;
}

class PendingInviteStore {
  static const String _emailKey = 'pending_invite_email';
  static const String _tokenKey = 'pending_invite_token';
  static const String _roleKey = 'pending_invite_role';
  static const String _savedAtMillisKey = 'pending_invite_saved_at_millis';

  String _normalizeEmail(String email) => email.trim().toLowerCase();

  Future<void> save({
    required String email,
    required String token,
    String? role,
  }) async {
    final normalizedEmail = _normalizeEmail(email);
    final trimmedToken = token.trim();
    final trimmedRole = (role ?? '').trim();
    if (normalizedEmail.isEmpty || trimmedToken.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, normalizedEmail);
    await prefs.setString(_tokenKey, trimmedToken);
    if (trimmedRole.isEmpty) {
      await prefs.remove(_roleKey);
    } else {
      await prefs.setString(_roleKey, trimmedRole);
    }
    await prefs.setInt(
      _savedAtMillisKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<PendingInvite?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final email = (prefs.getString(_emailKey) ?? '').trim();
    final token = (prefs.getString(_tokenKey) ?? '').trim();
    if (email.isEmpty || token.isEmpty) return null;

    final role = (prefs.getString(_roleKey) ?? '').trim();
    final savedAtMillis = prefs.getInt(_savedAtMillisKey);
    final savedAt = savedAtMillis == null
        ? DateTime.fromMillisecondsSinceEpoch(0)
        : DateTime.fromMillisecondsSinceEpoch(savedAtMillis);

    return PendingInvite(
      email: email,
      token: token,
      role: role.isEmpty ? null : role,
      savedAt: savedAt,
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_savedAtMillisKey);
  }
}
