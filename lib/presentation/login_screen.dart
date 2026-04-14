import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/login_lockout_service.dart';
import '../core/biometric_login_service.dart';
import '../core/session_manager.dart';
import '../core/supabase_service.dart';
import '../core/validators.dart';
import '../domain/models.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    this.initialEmail,
    this.initialMessage,
    this.initialError,
  });

  final String? initialEmail;
  final String? initialMessage;
  final String? initialError;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _supabaseService = SupabaseService();
  final _lockoutService = LoginLockoutService();
  final _biometricLoginService = BiometricLoginService();

  bool _faceIdLoginAvailable = false;

  StreamSubscription<AuthState>? _authSubscription;
  bool _isLoading = false;
  bool _isHandlingGoogleResult = false;

  static final Uri _googleRedirectUri = Uri(
    scheme: 'com.example.epilouge',
    host: 'login-callback',
  );

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.initialEmail?.trim() ?? '';
    _loadFaceIdAvailability();
    _authSubscription = _supabaseService.client.auth.onAuthStateChange.listen((
      data,
    ) {
      if (data.event != AuthChangeEvent.signedIn) return;
      // During manual email/password login, we explicitly finish the session.
      if (_isLoading) return;
      final user = data.session?.user;
      if (user == null) return;
      _handleGoogleAuthResult(user);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final messenger = ScaffoldMessenger.of(context);
      final initialError = widget.initialError?.trim();
      final initialMessage = widget.initialMessage?.trim();
      if (initialError != null && initialError.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(initialError),
            backgroundColor: Colors.red.shade700,
          ),
        );
      } else if (initialMessage != null && initialMessage.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(initialMessage),
            backgroundColor: const Color(0xFF2E7D32),
          ),
        );
      }

      final user = _supabaseService.client.auth.currentUser;
      if (user != null) {
        _handleGoogleAuthResult(user);
      }
    });
  }

  Future<void> _loadFaceIdAvailability() async {
    final supported = await _biometricLoginService.isDeviceSupported();
    final enabled = await _biometricLoginService.isEnabled();
    final lockedOut = await _biometricLoginService.isLockedOut();
    if (!mounted) return;
    setState(() => _faceIdLoginAvailable = supported && enabled && !lockedOut);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    _trimEmailField();

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) return;

    setState(() => _isLoading = true);

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      final lockoutStatus = await _lockoutService.getStatus(email);
      if (lockoutStatus.isLocked) {
        throw const _LockedAccountException();
      }

      final accountExists = await _supabaseService.isRegisteredEmail(email);
      if (!accountExists) {
        throw const _NoAccountFoundException();
      }

      final authRes = await _supabaseService.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      final user = authRes.user;
      if (user == null) {
        throw Exception('Login failed');
      }

      await _finishAuthenticatedLogin(email);
      await _biometricLoginService.markCredentialLoginCompleted();
      await _lockoutService.clear(email);
    } on _LoginFlowException catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } on AuthException catch (error) {
      if (!mounted) return;
      final email = _emailController.text.trim();
      final message = await _mapAuthException(error, email: email);
      _showError(message);
    } on PostgrestException catch (_) {
      if (!mounted) return;
      _showError('Something went wrong. Please try again later');
    } catch (e) {
      if (!mounted) return;
      final message = _mapUnknownException(e);
      _showError(message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithFaceId() async {
    FocusScope.of(context).unfocus();

    final lockedOut = await _biometricLoginService.isLockedOut();
    if (lockedOut) {
      if (!mounted) return;
      _showError('Too many failed attempts. Please log in with password');
      return;
    }

    final supported = await _biometricLoginService.isDeviceSupported();
    if (!supported) {
      if (!mounted) return;
      _showError('Biometric authentication is not available on this device');
      return;
    }

    final enabled = await _biometricLoginService.isEnabled();
    if (!enabled) {
      if (!mounted) return;
      _showError('Face ID login is not enabled');
      return;
    }

    final ok = await _biometricLoginService.authenticate(
      reason: 'Log in quickly with Face ID',
    );
    if (!ok) {
      final attempts = await _biometricLoginService.registerFailedAttempt();
      if (!mounted) return;
      if (attempts >= _biometricLoginService.maxFailedAttempts) {
        await _loadFaceIdAvailability();
        _showError('Too many failed attempts. Please log in with password');
      } else {
        _showError('Face ID authentication failed. Please try again');
      }
      return;
    }

    await _biometricLoginService.clearFailedAttempts();

    final email = _supabaseService.client.auth.currentUser?.email?.trim() ?? '';
    if (email.isEmpty) {
      if (!mounted) return;
      _showError('Please log in with email and password first');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await _finishAuthenticatedLogin(email);
    } catch (e) {
      if (!mounted) return;
      final message = _mapUnknownException(e);
      _showError(message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    FocusScope.of(context).unfocus();
    setState(() => _isLoading = true);

    try {
      final launched = await _supabaseService.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : _googleRedirectUri.toString(),
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google login was unsuccessful')),
        );
      }
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google login was unsuccessful')),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleAuthResult(User user) async {
    if (_isHandlingGoogleResult) return;

    // This handler is used for OAuth callbacks and persisted sessions.
    // It should work for any provider (email/password, Google, etc.).

    final email = user.email?.trim() ?? '';
    if (email.isEmpty) {
      await _supabaseService.client.auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Google login was unsuccessful')),
      );
      return;
    }

    _emailController.text = email;
    _isHandlingGoogleResult = true;
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      await _finishAuthenticatedLogin(email);
    } catch (_) {
      await _supabaseService.client.auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Login was unsuccessful')));
    } finally {
      _isHandlingGoogleResult = false;
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _finishAuthenticatedLogin(String email) async {
    if (await _supabaseService.isDocxSchema()) {
      await _finishDocxAuthenticatedLogin();
      return;
    }

    try {
      final rows =
          (await _supabaseService.client
                  .from('members')
                  .select('*, care_teams(*)')
                  .eq('email', email)
                  .order('last_active', ascending: false)
                  .order('joined_at', ascending: false)
                  .limit(1))
              as List;

      final first = rows.isNotEmpty ? rows.first : null;
      if (first == null) {
        await _supabaseService.client.auth.signOut();
        throw const _NoAccountFoundException();
      }

      final member = Map<String, dynamic>.from(first as Map);
      final careTeamJson = member['care_teams'];
      if (careTeamJson is! Map<String, dynamic>) {
        await _supabaseService.client.auth.signOut();
        throw const _ServerSideLoginException();
      }

      await SessionManager().setSession(
        CareTeam.fromJson(careTeamJson),
        Member.fromJson(member),
      );

      final role = member['role'];

      if (!mounted) return;
      if (role == 'P5') {
        context.go('/nurse_patients');
      } else {
        context.go('/dashboard');
      }
    } on PostgrestException {
      await _finishDocxAuthenticatedLogin();
    }
  }

  Future<void> _finishDocxAuthenticatedLogin() async {
    final user = _supabaseService.client.auth.currentUser;
    final uid = user?.id;
    if (uid == null) {
      await _supabaseService.client.auth.signOut();
      throw const _ServerSideLoginException();
    }

    final membership = await _supabaseService.client
        .from('care_team_member')
        .select('care_space_id, is_primary, is_active, created_at')
        .eq('user_profile_id', uid)
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (membership == null) {
      await _supabaseService.client.auth.signOut();
      throw const _NoAccountFoundException();
    }

    final careSpaceId = (membership['care_space_id'] ?? '').toString().trim();
    if (careSpaceId.isEmpty) {
      await _supabaseService.client.auth.signOut();
      throw const _ServerSideLoginException();
    }

    final team = await _supabaseService.getCareTeam(careSpaceId);
    if (team == null) {
      await _supabaseService.client.auth.signOut();
      throw const _ServerSideLoginException();
    }

    final profile = await _supabaseService.client
        .from('user_profile')
        .select('full_name')
        .eq('user_profile_id', uid)
        .maybeSingle();
    final profileMap = (profile as Map?)?.cast<String, dynamic>();
    final fullName = (profileMap?['full_name'] ?? '').toString().trim();

    await SessionManager().setSession(
      team,
      Member(
        id: uid,
        careTeamId: team.id,
        name: fullName.isEmpty ? 'Member' : fullName,
        email: (user?.email ?? '').trim().isEmpty
            ? 'unknown@example.com'
            : user!.email!.trim(),
        role: 'family',
        isAdmin: membership['is_primary'] == true,
      ),
    );

    if (!mounted) return;
    context.go('/dashboard');
  }

  Future<String> _mapAuthException(
    AuthException error, {
    required String email,
  }) async {
    final message = error.message.toLowerCase();
    final code = (error.code ?? '').toLowerCase();
    final statusCode = error.statusCode ?? '';

    if (error is AuthRetryableFetchException) {
      if (_looksLikeNetworkError(message)) {
        return 'Check your internet connection';
      }
      return 'Something went wrong. Please try again later';
    }

    final invalidCredentials =
        message.contains('invalid login credentials') ||
        message.contains('invalid email or password') ||
        code == 'invalid_credentials' ||
        code == 'email_address_not_authorized';

    if (invalidCredentials) {
      final status = await _lockoutService.registerFailedAttempt(email);
      if (status.isLocked) {
        return 'Account temporarily locked. Try again later';
      }
      return 'Invalid email or password';
    }

    if (message.contains('user not found') ||
        message.contains('email not found') ||
        code == 'user_not_found') {
      return 'No account found with this email';
    }

    final parsedStatusCode = int.tryParse(statusCode);
    if (parsedStatusCode != null && parsedStatusCode >= 500) {
      return 'Something went wrong. Please try again later';
    }

    if (_looksLikeNetworkError(message)) {
      return 'Check your internet connection';
    }

    return 'Something went wrong. Please try again later';
  }

  String _mapUnknownException(Object error) {
    final message = error.toString().toLowerCase();
    if (_looksLikeNetworkError(message)) {
      return 'Check your internet connection';
    }
    return 'Something went wrong. Please try again later';
  }

  bool _looksLikeNetworkError(String message) {
    return message.contains('socketexception') ||
        message.contains('failed host lookup') ||
        message.contains('network') ||
        message.contains('connection') ||
        message.contains('timed out');
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red.shade700),
    );
  }

  void _trimEmailField() {
    final trimmedEmail = _emailController.text.trim();
    _emailController.value = _emailController.value.copyWith(
      text: trimmedEmail,
      selection: TextSelection.collapsed(offset: trimmedEmail.length),
      composing: TextRange.empty,
    );
  }

  String? _validateLoginPassword(String? value) => Validators.password(value);

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
                        onTap: () => context.go('/join'),
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
                        'Login',
                        style: GoogleFonts.nunito(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your details to access your care team.',
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
                              child: TextFormField(
                                controller: _passwordController,
                                obscureText: true,
                                autofillHints: const [AutofillHints.password],
                                textInputAction: TextInputAction.done,
                                validator: _validateLoginPassword,
                                onFieldSubmitted: (_) => _login(),
                                style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  color: const Color(0xFF2E2540),
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Enter Password',
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            final email = _emailController.text.trim();
                            final uri = Uri(
                              path: '/forgot-password',
                              queryParameters: email.isEmpty
                                  ? null
                                  : {'email': email},
                            );
                            context.push(uri.toString());
                          },
                          child: const Text('Forgot password?'),
                        ),
                      ),
                      const SizedBox(height: 40),
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _loginWithGoogle,
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.92),
                            foregroundColor: const Color(0xFF2E2540),
                            side: const BorderSide(
                              color: Color(0xFFD4CDDF),
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9999),
                            ),
                          ),
                          icon: const Icon(Icons.g_mobiledata, size: 28),
                          label: Text(
                            'Continue with Google',
                            style: GoogleFonts.nunito(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF2E2540),
                            ),
                          ),
                        ),
                      ),
                      if (_faceIdLoginAvailable) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _loginWithFaceId,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: Colors.white.withOpacity(0.92),
                              foregroundColor: const Color(0xFF2E2540),
                              side: const BorderSide(
                                color: Color(0xFFD4CDDF),
                                width: 1.5,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(9999),
                              ),
                            ),
                            icon: const Icon(Icons.face, size: 22),
                            label: Text(
                              'Login with Face ID',
                              style: GoogleFonts.nunito(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF2E2540),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 60,
                        child: ElevatedButton(
                          onPressed: _login,
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
                            'Login',
                            style: GoogleFonts.nunito(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
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

sealed class _LoginFlowException implements Exception {
  const _LoginFlowException(this.message);

  final String message;
}

final class _NoAccountFoundException extends _LoginFlowException {
  const _NoAccountFoundException() : super('No account found with this email');
}

final class _LockedAccountException extends _LoginFlowException {
  const _LockedAccountException()
    : super('Account temporarily locked. Try again later');
}

final class _ServerSideLoginException extends _LoginFlowException {
  const _ServerSideLoginException()
    : super('Something went wrong. Please try again later');
}
