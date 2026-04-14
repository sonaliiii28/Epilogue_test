import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_service.dart';
import '../core/session_manager.dart';

class SetPasswordAfterJoinScreen extends StatefulWidget {
  const SetPasswordAfterJoinScreen({
    super.key,
    required this.email,
    this.inviteCode,
    this.role,
  });

  final String email;
  final String? inviteCode;
  final String? role;

  @override
  State<SetPasswordAfterJoinScreen> createState() =>
      _SetPasswordAfterJoinScreenState();
}

class _SetPasswordAfterJoinScreenState
    extends State<SetPasswordAfterJoinScreen> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _supabaseService = SupabaseService();

  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _setPassword() async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final email = widget.email.trim();
      final password = _passwordController.text.trim();
      final confirmPassword = _confirmPasswordController.text.trim();

      if (email.isEmpty) {
        throw Exception('Missing email');
      }
      if (password.isEmpty || confirmPassword.isEmpty) {
        throw Exception('Please enter and confirm your password');
      }
      if (password != confirmPassword) {
        throw Exception('Passwords do not match');
      }
      if (password.length < 8) {
        throw Exception('Password must be at least 8 characters');
      }

      try {
        await _supabaseService.client.auth.signUp(
          email: email,
          password: password,
        );
      } on AuthException catch (e) {
        final msg = e.message.toLowerCase();
        final code = (e.code ?? '').toLowerCase();
        final alreadyRegistered =
            msg.contains('already') ||
            msg.contains('registered') ||
            code == 'user_already_exists';
        if (!alreadyRegistered) rethrow;

        await _supabaseService.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      }

      // If we have an invite code, complete the care-space join now.
      final inviteCode = (widget.inviteCode ?? '').trim();
      if (inviteCode.isNotEmpty) {
        final careTeam = await _supabaseService.getCareTeamByJoinCode(
          inviteCode,
        );
        if (careTeam == null) {
          throw Exception('Invalid invite code');
        }

        final role = (widget.role ?? 'family').trim().isEmpty
            ? 'family'
            : widget.role!.trim();

        final member = await _supabaseService.ensureMemberForTeam(
          careTeam: careTeam,
          email: email,
          role: role,
        );

        await SessionManager().setSession(careTeam, member);

        if (!mounted) return;
        if (role == 'medical_team' || role == 'nurse') {
          context.go('/nurse_patients');
        } else {
          context.go('/dashboard');
        }
        return;
      }

      // Backward-compatible behavior: set password then go to login.
      if (!mounted) return;
      context.go(
        '/login?email=${Uri.encodeQueryComponent(email)}&message=${Uri.encodeQueryComponent('Password set. Please log in.')}',
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

  @override
  Widget build(BuildContext context) {
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
                  onTap: () => context.go('/join'),
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
                  'Set Your Password',
                  style: GoogleFonts.nunito(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Create a password to access this care space.',
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Email',
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
                    enabled: false,
                    controller: TextEditingController(text: widget.email),
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      color: const Color(0xFF2E2540),
                    ),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(
                        Icons.mail_outline_rounded,
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
                  'Password',
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
                    textInputAction: TextInputAction.next,
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      color: const Color(0xFF2E2540),
                    ),
                    decoration: InputDecoration(
                      hintText: 'At least 8 characters',
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
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _setPassword(),
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      color: const Color(0xFF2E2540),
                    ),
                    decoration: InputDecoration(
                      hintText: 'Re-enter password',
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
                const SizedBox(height: 34),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _setPassword,
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
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(
                            'Set Password',
                            style: GoogleFonts.nunito(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
