import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key, this.errorMessage});

  final String? errorMessage;

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _supabaseService = SupabaseService();

  bool _isLoading = false;

  bool get _hasRecoverySession =>
      _supabaseService.client.auth.currentSession != null &&
      _supabaseService.client.auth.currentUser != null;

  String? get _blockingError {
    if (widget.errorMessage != null && widget.errorMessage!.trim().isNotEmpty) {
      return widget.errorMessage;
    }
    if (!_hasRecoverySession) {
      return 'Invalid or already used link';
    }
    return null;
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _resetPassword() async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final password = _passwordController.text.trim();
      final confirmPassword = _confirmPasswordController.text.trim();

      if (_blockingError != null) {
        throw Exception(_blockingError);
      }
      if (password.isEmpty || confirmPassword.isEmpty) {
        throw Exception('Please enter and confirm your new password');
      }
      if (password != confirmPassword) {
        throw Exception('Passwords do not match');
      }
      if (password.length < 8) {
        throw Exception('Password must be at least 8 characters');
      }

      final email = _supabaseService.client.auth.currentUser?.email?.trim();

      await _supabaseService.client.auth.updateUser(
        UserAttributes(password: password),
      );
      await _supabaseService.client.auth.signOut();

      if (!mounted) return;
      final uri = Uri(
        path: '/login',
        queryParameters: {
          if (email != null && email.isNotEmpty) 'email': email,
          'message': 'Password reset successful. Please log in with your new password.',
        },
      );
      context.go(uri.toString());
    } on AuthException catch (error) {
      if (!mounted) return;
      final message = _mapResetPasswordError(error);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _mapResetPasswordError(AuthException error) {
    final message = error.message.toLowerCase();
    final code = (error.code ?? '').toLowerCase();

    if (message.contains('expired') || code == 'otp_expired') {
      return 'Link expired';
    }
    if (message.contains('invalid') ||
        message.contains('used') ||
        message.contains('session') ||
        code == 'bad_code_verifier') {
      return 'Invalid or already used link';
    }
    return error.message;
  }

  @override
  Widget build(BuildContext context) {
    final blockingError = _blockingError;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF74659A), Color(0xFFDFDBE5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () => context.go('/login'),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.4)),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  'Reset Password',
                  style: GoogleFonts.nunito(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  blockingError == null
                      ? 'Enter and confirm your new password to finish recovering your account.'
                      : blockingError,
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 40),
                Text(
                  'New Password',
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2E2540),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFD4CDDF),
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: _passwordController,
                    obscureText: true,
                    enabled: !_isLoading && blockingError == null,
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      color: const Color(0xFF2E2540),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Enter new password',
                      hintStyle: GoogleFonts.nunito(
                        fontSize: 16,
                        color: const Color(0xFFB8B0CC),
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 20,
                        color: Color(0xFF6C648B),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Confirm Password',
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2E2540),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFD4CDDF),
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    enabled: !_isLoading && blockingError == null,
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      color: const Color(0xFF2E2540),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Confirm new password',
                      hintStyle: GoogleFonts.nunito(
                        fontSize: 16,
                        color: const Color(0xFFB8B0CC),
                      ),
                      prefixIcon: const Icon(
                        Icons.lock_outline_rounded,
                        size: 20,
                        color: Color(0xFF6C648B),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : (blockingError == null
                              ? _resetPassword
                              : () => context.go('/login')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B5B95),
                      foregroundColor: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(0xFF6B5B95).withOpacity(0.30),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9999),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            blockingError == null
                                ? 'Update Password'
                                : 'Back to Login',
                            style: GoogleFonts.nunito(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
