class Validators {
  Validators._();

  static final RegExp _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static String? email(String? value) {
    final email = (value ?? '').trim();
    if (email.isEmpty) return 'Email is required';
    if (!_emailRegex.hasMatch(email)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value) {
    final password = (value ?? '').trim();
    if (password.isEmpty) return 'Password is required';
    if (password.length < 8) return 'Password must be at least 8 characters';

    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    final hasNumber = RegExp(r'\d').hasMatch(password);
    // Common definition of symbol: anything not letter/number/underscore/space.
    final hasSymbol = RegExp(r'[^A-Za-z0-9\s_]').hasMatch(password);

    if (!hasUppercase || !hasNumber || !hasSymbol) {
      return 'Password must include at least one uppercase letter, one number, and one symbol';
    }

    return null;
  }
}
