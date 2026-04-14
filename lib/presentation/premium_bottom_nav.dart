import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

class PremiumBottomNav extends StatelessWidget {
  final int currentIndex;
  const PremiumBottomNav({super.key, required this.currentIndex});

  static const _items = [
    _NavItem(icon: Icons.home_rounded, label: 'Home', route: '/dashboard'),
    _NavItem(
      icon: Icons.calendar_today_outlined,
      label: 'Calendar',
      route: '/calendar',
    ),
    _NavItem(
      icon: Icons.chat_bubble_outline_rounded,
      label: 'Messages',
      route: '/messages',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFFEDE8F5).withOpacity(0.82),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: Colors.white.withOpacity(0.75),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF7A64A4).withOpacity(0.12),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: List.generate(
                _items.length,
                (i) => Expanded(child: _buildItem(context, i)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildItem(BuildContext context, int index) {
    final item = _items[index];
    final isActive = currentIndex == index;

    return GestureDetector(
      onTap: () => context.go(item.route),
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF7A64A4).withOpacity(0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              item.icon,
              size: 23,
              color: isActive
                  ? const Color(0xFF6B5B8E)
                  : const Color(0xFF8F7AB6),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            item.label,
            style: GoogleFonts.nunito(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              color: isActive
                  ? const Color(0xFF6B5B8E)
                  : const Color(0xFFB0A8C8),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String route;
  const _NavItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}
