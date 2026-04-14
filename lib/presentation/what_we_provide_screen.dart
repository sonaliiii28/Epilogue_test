import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

class WhatWeProvideScreen extends StatefulWidget {
  const WhatWeProvideScreen({super.key});

  @override
  State<WhatWeProvideScreen> createState() => _WhatWeProvideScreenState();
}

class _WhatWeProvideScreenState extends State<WhatWeProvideScreen> {
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
                        // Ã¢Å“â€¦ FIXED BACK BUTTON
                        GestureDetector(
                          onTap: () => context.pop(),
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
                    'EVERYTHING YOUR FAMILY NEEDS',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: Colors.white,
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Title
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
                          const TextSpan(text: 'Designed with '),
                          TextSpan(
                            text: 'care',
                            style: GoogleFonts.nunito(
                              fontSize: 32,
                              fontWeight: FontWeight.w400,
                              fontStyle: FontStyle.italic,
                              color: const Color.fromARGB(255, 160, 128, 239),
                            ),
                          ),
                          const TextSpan(text: ' and clarity'),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Feature Cards
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: const [
                        _FeatureCard(
                          icon: Icons.description,
                          title: 'Coordinate care',
                          description:
                              'Track medications, symptoms, and daily observations. Keep everyone on the same page, always.',
                          gradientColors: [
                            Color(0xFF6B5B95),
                            Color(0xFF8B7BB5),
                          ],
                        ),
                        SizedBox(height: 14),
                        _FeatureCard(
                          icon: Icons.people,
                          title: 'Stay connected',
                          description:
                              'Family members near and far can see updates, share moments, and support one another.',
                          gradientColors: [
                            Color(0xFF9E7FA8),
                            Color(0xFFC4AED0),
                          ],
                        ),
                        SizedBox(height: 14),
                        _FeatureCard(
                          icon: Icons.calendar_today,
                          title: 'Manage visits',
                          description:
                              'Schedule hospice visits, equipment deliveries, and care aide shifts in one place.',
                          gradientColors: [
                            Color(0xFF7B9EB5),
                            Color(0xFFA8C0D2),
                          ],
                        ),
                        SizedBox(height: 14),
                        _FeatureCard(
                          icon: Icons.shield,
                          title: 'Private & secure',
                          description:
                              'Your family\'s information is encrypted and never shared. You control who has access.',
                          gradientColors: [
                            Color(0xFF8BAA8A),
                            Color(0xFFAECAD0),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 60),

                  // Values Section
                  Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF6B5B95),
                          Color(0xFF9E7FA8),
                          Color(0xFF7B9EB5),
                        ],
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 52,
                      horizontal: 24,
                    ),
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 32,
                      crossAxisSpacing: 20,
                      childAspectRatio: 1.1,
                      children: const [
                        _ValueCard(value: '24/7', label: 'Care Support'),
                        _ValueCard(value: '50k+', label: 'Families Helped'),
                        _ValueCard(value: '98%', label: 'Satisfaction'),
                        _ValueCard(value: '100%', label: 'Secure'),
                      ],
                    ),
                  ),

                  const SizedBox(height: 60),

                  // CTA Button
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

                  const SizedBox(height: 60),
                ],
              ),
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
                                context.go('/how_it_works');
                              },
                              child: Text(
                                'How it Works',
                                style: GoogleFonts.nunito(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w400,
                                  color: const Color(0xFF2E2540),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                            const SizedBox(height: 32),
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

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<Color> gradientColors;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE4E1EA),
        border: Border.all(color: const Color(0xFFE4E1EA).withOpacity(0.45)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: gradientColors,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 18),
          Expanded(
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
        ],
      ),
    );
  }
}

class _ValueCard extends StatelessWidget {
  final String value;
  final String label;

  const _ValueCard({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          value,
          style: GoogleFonts.nunito(
            fontSize: 44,
            fontWeight: FontWeight.w300,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.14,
            color: Colors.white.withOpacity(0.65),
          ),
        ),
      ],
    );
  }
}

