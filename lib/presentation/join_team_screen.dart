import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/supabase_service.dart';
import '../core/session_manager.dart';
import '../core/validators.dart';
import '../domain/models.dart';

class JoinTeamScreen extends StatefulWidget {
  const JoinTeamScreen({super.key});

  @override
  State<JoinTeamScreen> createState() => _JoinTeamScreenState();
}

class _JoinTeamScreenState extends State<JoinTeamScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _pinController = TextEditingController();
  final _supabaseService = SupabaseService();
  bool _isLoading = false;

  String _selectedRole = "family";

  Future<void> _joinTeam() async {
    FocusScope.of(context).unfocus();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() => _isLoading = true);
    try {
      final joinCode = _pinController.text.trim().toUpperCase();
      final email = _emailController.text.trim();

      final invite = await _supabaseService.getActiveInviteByCodeAndEmail(
        inviteCode: joinCode,
        email: email,
      );

      final careTeamId = (invite?['care_team_id'] ?? '').toString().trim();
      var careTeam = careTeamId.isNotEmpty
          ? await _tryGetCareTeam(careTeamId)
          : null;
      careTeam ??= await _supabaseService.getCareTeamByJoinCode(joinCode);
      if (careTeam == null) {
        throw Exception('Invalid invite code');
      }

      final inviteRole = (invite?['role'] ?? '').toString().trim();
      if (invite != null && inviteRole.isNotEmpty) {
        _selectedRole = inviteRole;
      }

      final currentUser = _supabaseService.client.auth.currentUser;
      final currentEmail = currentUser?.email?.trim() ?? '';
      final normalizedEmail = email.toLowerCase();

      // If the user is already authenticated with the same email, we can join now.
      if (currentUser != null &&
          currentEmail.toLowerCase() == normalizedEmail) {
        final member = await _supabaseService.ensureMemberForTeam(
          careTeam: careTeam,
          email: email,
          role: _selectedRole,
        );

        await SessionManager().setSession(careTeam, member);

        if (!mounted) return;
        if (_selectedRole == 'medical_team' || _selectedRole == 'nurse') {
          context.go('/nurse_patients');
        } else {
          context.go('/dashboard');
        }
        return;
      }

      // Otherwise, require password setup/sign-in first, then complete the join.
      final uri = Uri(
        path: '/set-password',
        queryParameters: {
          'email': email,
          'code': joinCode,
          'role': _selectedRole,
        },
      );

      if (!mounted) return;
      context.go(uri.toString());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<CareTeam?> _tryGetCareTeam(String careTeamId) async {
    try {
      return await _supabaseService.getCareTeam(careTeamId);
    } catch (_) {
      return null;
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
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF6B5B95)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => context.go('/'),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.4),
                            ),
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
                        'Join Care Team',
                        style: GoogleFonts.nunito(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your credentials to join an existing care team.',
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withOpacity(0.85),
                        ),
                      ),
                      const SizedBox(height: 40),
                      Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Email',
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
                              child: TextFormField(
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                autofillHints: const [AutofillHints.email],
                                textInputAction: TextInputAction.next,
                                validator: Validators.email,
                                style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  color: const Color(0xFF2E2540),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'name@example.com',
                                  hintStyle: GoogleFonts.nunito(
                                    fontSize: 16,
                                    color: const Color(0xFFB8B0CC),
                                  ),
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
                            const SizedBox(height: 20),
                            Text(
                              'Invite Code',
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
                              child: TextFormField(
                                controller: _pinController,
                                keyboardType: TextInputType.text,
                                textCapitalization:
                                    TextCapitalization.characters,
                                textInputAction: TextInputAction.done,
                                validator: (value) {
                                  final code = (value ?? '').trim();
                                  if (code.isEmpty) {
                                    return 'Invite code is required';
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) => _joinTeam(),
                                style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  color: const Color(0xFF2E2540),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Enter your code',
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
                          ],
                        ),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _joinTeam,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6B5B95),
                            foregroundColor: Colors.white,
                            elevation: 4,
                            shadowColor: const Color(
                              0xFF6B5B95,
                            ).withOpacity(0.30),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9999),
                            ),
                          ),
                          child: Text(
                            'Join Team',
                            style: GoogleFonts.nunito(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      Center(
                        child: GestureDetector(
                          onTap: () => context.go('/login'),
                          child: Text(
                            'Already a member? Login',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF2E2540),
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
