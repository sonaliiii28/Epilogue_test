import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/biometric_login_service.dart';
import '../core/session_manager.dart';

class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});

  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

class _LandingScreenState extends State<LandingScreen> {
  final _biometricLoginService = BiometricLoginService();
  final _sessionManager = SessionManager();

  bool _isDrawerOpen = false;
  DateTime _currentDate = DateTime.now();
  Timer? _dateTimer;
  bool _isHandlingBiometricLaunch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attemptBiometricAutoLogin();
    });
    _dateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      if (now.year != _currentDate.year ||
          now.month != _currentDate.month ||
          now.day != _currentDate.day) {
        if (mounted) {
          setState(() {
            _currentDate = now;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _dateTimer?.cancel();
    super.dispose();
  }

  Future<void> _attemptBiometricAutoLogin() async {
    if (_isHandlingBiometricLaunch) return;
    _isHandlingBiometricLaunch = true;

    try {
      final enabled = await _biometricLoginService.isEnabled();
      if (!enabled) return;

      final hasCredentialLogin = await _biometricLoginService
          .hasCompletedCredentialLogin();
      if (!hasCredentialLogin) return;

      final supported = await _biometricLoginService.isDeviceSupported();
      if (!supported) {
        if (!mounted) return;
        final uri = Uri(
          path: '/login',
          queryParameters: {
            'error':
                'Biometric login is unavailable. Please log in with password',
          },
        );
        context.go(uri.toString());
        return;
      }

      final lockedOut = await _biometricLoginService.isLockedOut();
      if (lockedOut) {
        if (!mounted) return;
        final uri = Uri(
          path: '/login',
          queryParameters: {
            'error': 'Too many failed attempts. Please log in with password',
          },
        );
        context.go(uri.toString());
        return;
      }

      final ok = await _biometricLoginService.authenticate(
        reason: 'Log in quickly with Face ID',
      );

      if (!ok) {
        final attempts = await _biometricLoginService.registerFailedAttempt();
        if (!mounted) return;

        if (attempts >= _biometricLoginService.maxFailedAttempts) {
          final uri = Uri(
            path: '/login',
            queryParameters: {
              'error': 'Too many failed attempts. Please log in with password',
            },
          );
          context.go(uri.toString());
          return;
        }

        final uri = Uri(
          path: '/login',
          queryParameters: {
            'error':
                'Face ID authentication failed. Please log in with password',
          },
        );
        context.go(uri.toString());
        return;
      }

      await _biometricLoginService.clearFailedAttempts();

      final loaded = await _sessionManager.loadSession();
      if (!mounted) return;
      if (!loaded) {
        context.go('/login');
        return;
      }

      final role = _sessionManager.currentMember?.role;
      if (role == 'P5') {
        context.go('/nurse_patients');
      } else {
        context.go('/dashboard');
      }
    } finally {
      _isHandlingBiometricLaunch = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main content
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF74659A), // deep purple at top
                  Color(0xFFDFDBE5), // soft lilac at bottom
                ],
              ),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Align(
                    alignment: const Alignment(0, 0.10),
                    child: SizedBox(
                      width: 760,
                      height: 760,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [_ring(760), _ring(520), _ring(360)],
                      ),
                    ),
                  ),
                ),
                SafeArea(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Today',
                                  style: GoogleFonts.nunito(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 3.0,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('EEEE').format(_currentDate),
                                  style: GoogleFonts.nunito(
                                    fontSize: 36,
                                    fontWeight: FontWeight.w400,
                                    color: Colors.white,
                                    height: 1.1,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('MMMM d, y').format(_currentDate),
                                  style: GoogleFonts.nunito(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.menu,
                                color: Colors.white,
                                size: 36,
                              ),
                              onPressed: () {
                                setState(() {
                                  _isDrawerOpen = !_isDrawerOpen;
                                });
                              },
                            ),
                          ],
                        ),
                      ),

                      Divider(
                        height: 1,
                        thickness: 1,
                        color: Colors.white.withOpacity(0.30),
                      ),

                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Epilogue',
                                style: GoogleFonts.playfairDisplay(
                                  fontSize: 80,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.white,
                                  height: 1.0,
                                ),
                              ),
                              const SizedBox(height: 24),
                              SizedBox(
                                width: 320,
                                child: Text(
                                  'Care and collaboration',
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.nunito(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF1A1A24),
                                    height: 1.5,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 48),

                              // Start button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  onPressed: () => context.go('/setup'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6B5B95),
                                    foregroundColor: Colors.white,
                                    elevation: 6,
                                    shadowColor: const Color(
                                      0xFF6B5B95,
                                    ).withOpacity(0.30),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(9999),
                                    ),
                                  ),
                                  child: Text(
                                    'Start Your Care Team',
                                    style: GoogleFonts.nunito(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),

                              const SizedBox(height: 32),

                              Text(
                                'Already have an invite code?',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.nunito(
                                  fontSize: 20,
                                  color: const Color(0xFF1A1A24),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),

                              const SizedBox(height: 16),

                              ElevatedButton(
                                onPressed: () => context.go('/join'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6B5B95),
                                  foregroundColor: Colors.white,
                                  elevation: 4,
                                  shadowColor: const Color(
                                    0xFF6B5B95,
                                  ).withOpacity(0.30),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                    horizontal: 32,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9999),
                                  ),
                                ),
                                child: Text(
                                  'Join here',
                                  style: GoogleFonts.nunito(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Drawer overlay
          if (_isDrawerOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isDrawerOpen = false),
                child: Container(color: Colors.black.withOpacity(0.5)),
              ),
            ),

          // Drawer panel
          if (_isDrawerOpen)
            Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 250,
                height: double.infinity,
                color: Colors.white,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _isDrawerOpen = false),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ✅ FIXED — using push
                        GestureDetector(
                          onTap: () {
                            setState(() => _isDrawerOpen = false);
                            context.push('/what_we_provide');
                          },
                          child: Text(
                            'What We Provide',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 18,
                              fontStyle: FontStyle.italic,
                              color: const Color(0xFF2E2540),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        GestureDetector(
                          onTap: () {
                            setState(() => _isDrawerOpen = false);
                            context.go('/how_it_works');
                          },
                          child: Text(
                            'How it Works',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 18,
                              fontStyle: FontStyle.italic,
                              color: const Color(0xFF2E2540),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _ring(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: const Color(0xFF6B5B95).withOpacity(0.05),
          width: 1.5,
        ),
      ),
    );
  }
}
