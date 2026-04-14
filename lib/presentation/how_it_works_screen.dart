import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class HowItWorksScreen extends StatefulWidget {
  const HowItWorksScreen({super.key});

  @override
  State<HowItWorksScreen> createState() => _HowItWorksScreenState();
}

class _HowItWorksScreenState extends State<HowItWorksScreen> {
  bool _isDrawerOpen = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Main content
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF74659A), Color(0xFFDFDBE5)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        GestureDetector(
                          onTap: () => context.go('/'),
                          child: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.menu, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _isDrawerOpen = !_isDrawerOpen;
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),
                  // Section Label
                  Text(
                    'GETTING STARTED',
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Section Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.nunito(
                          fontSize: 32,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF2E2540),
                        ),
                        children: [
                          const TextSpan(text: 'Simple to begin,\n'),
                          TextSpan(
                            text: 'meaningful',
                            style: GoogleFonts.nunito(
                              fontSize: 32,
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.italic,
                              color: const Color(0xFF8B7BB5),
                            ),
                          ),
                          const TextSpan(text: ' from day one'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 44),
                  // Steps
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        _StepCard(
                          number: '1',
                          title: 'Create a care space',
                          description:
                              'Set up your family\'s private care space in minutes. No technical knowledge needed.',
                          isFirst: true,
                        ),
                        const SizedBox(height: 36),
                        _StepCard(
                          number: '2',
                          title: 'Invite your team',
                          description:
                              'Send a simple invite to family members, hospice nurses, and care aides.',
                          isFirst: false,
                        ),
                        const SizedBox(height: 36),
                        _StepCard(
                          number: '3',
                          title: 'Stay together',
                          description:
                              'Everyone stays informed, coordinated, and connected Ã¢â‚¬â€ no matter the distance.',
                          isFirst: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 70),
                  // Call-to-action button
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => context.go('/setup'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6B5B95),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Get Started',
                              style: GoogleFonts.nunito(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.arrow_forward,
                              color: Colors.white,
                              size: 18,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 70),
                ],
              ),
            ),
          ),
          // Hamburger drawer
          if (_isDrawerOpen)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _isDrawerOpen = false),
                child: Container(color: Colors.black.withOpacity(0.5)),
              ),
            ),
          if (_isDrawerOpen)
            Align(
              alignment: Alignment.topRight,
              child: Container(
                width: 250,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.98),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Close button
                      Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              _isDrawerOpen = false;
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      // Menu items
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () {
                                setState(() => _isDrawerOpen = false);
                                context.go('/');
                              },
                              child: Text(
                                'Home',
                                style: GoogleFonts.nunito(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF2E2540),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            GestureDetector(
                              onTap: () {
                                setState(() => _isDrawerOpen = false);
                                context.go('/what_we_provide');
                              },
                              child: Text(
                                'What We Provide',
                                style: GoogleFonts.nunito(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF2E2540),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
                            // CTA button
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() => _isDrawerOpen = false);
                                  context.go('/setup');
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF6B5B95),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Get Started',
                                      style: GoogleFonts.nunito(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(
                                      Icons.arrow_forward,
                                      color: Colors.white,
                                      size: 16,
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
              ),
            ),
        ],
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  final String number;
  final String title;
  final String description;
  final bool isFirst;

  const _StepCard({
    required this.number,
    required this.title,
    required this.description,
    required this.isFirst,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            // Number circle
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6B5B95), Color(0xFF9E7FA8)],
                ),
                borderRadius: BorderRadius.circular(32),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6B5B95).withOpacity(0.28),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  number,
                  style: GoogleFonts.nunito(
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            // Vertical line (if not last)
            if (!isFirst)
              Container(
                width: 1,
                height: 36,
                color: const Color(0xFFC8BFE0).withOpacity(0.5),
              ),
          ],
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.nunito(
                    fontSize: 17,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF2E2540),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    color: const Color(0xFF8A7FA8),
                    fontStyle: FontStyle.italic,
                    height: 1.75,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

