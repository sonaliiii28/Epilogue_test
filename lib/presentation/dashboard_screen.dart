import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/session_manager.dart';
import '../core/supabase_service.dart';
import '../domain/models.dart';
import 'care_team_screen.dart';
import 'moment_store.dart';

const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final _session = SessionManager();
  final _service = SupabaseService();

  int _doseBadge = 0;
  int _observationBadge = 0;
  int _symptomBadge = 0;
  int _momentBadge = 0;
  bool _isLoading = true;

  late AnimationController _staggerCtrl;

  @override
  void initState() {
    super.initState();
    _staggerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _loadData();
  }

  @override
  void dispose() {
    _staggerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final teamId = _session.currentCareTeam?.id;
    if (teamId == null) {
      if (mounted) context.go('/');
      return;
    }
    bool isTransientNetworkError(Object error) {
      final msg = error.toString().toLowerCase();
      return msg.contains('failed host lookup') ||
          msg.contains('socketexception') ||
          msg.contains('network is unreachable') ||
          msg.contains('connection timed out') ||
          msg.contains('timed out');
    }

    try {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final results = await Future.wait([
            _service.getMedications(teamId),
            _service.getObservations(teamId),
            _service.getSymptomEvents(teamId),
            _service.getMoments(teamId),
          ]);
          if (!mounted) return;
          setState(() {
            _doseBadge = (results[0] as List<Medication>)
                .where((m) => (m.pattern ?? '').toLowerCase() != 'inactive')
                .length;
            _observationBadge = (results[1] as List).length;
            _symptomBadge = (results[2] as List).length;
            _momentBadge = momentEntriesNotifier.value
                .where((m) => m.deletedAt == null)
                .length;
          });
          break;
        } catch (e) {
          final isTransient = isTransientNetworkError(e);
          final isLastAttempt = attempt == 2;
          debugPrint('Dashboard load error (attempt ${attempt + 1}/3): $e');
          if (!isTransient || isLastAttempt) {
            rethrow;
          }
          await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
        }
      }
    } catch (e) {
      debugPrint('Dashboard load error (final): $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _staggerCtrl.forward();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final careTeam = _session.currentCareTeam;
    final member = _session.currentMember;
    final cameFromNurseList =
        GoRouterState.of(context).uri.queryParameters['from'] ==
        'nurse_patients';

    if (careTeam == null || member == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Session expired',
                style: GoogleFonts.nunito(fontSize: 24, color: _deepPurple),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => context.go('/'),
                child: const Text('Return to home'),
              ),
            ],
          ),
        ),
      );
    }

    final rawFirst = member.name.split(' ').first;
    final firstName = rawFirst.isEmpty
        ? ''
        : '${rawFirst[0].toUpperCase()}${rawFirst.substring(1).toLowerCase()}';
    final patientName = careTeam.patientFirstName ?? 'your loved one';
    final today = DateFormat('EEE, MMM d').format(DateTime.now());

    return Scaffold(
      drawer: _AppDrawer(patientName: patientName),
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
        child: Column(
          children: [
            // â”€â”€ Top Bar (dark band from top of screen) â”€â”€
            Container(
              width: double.infinity,
              color: const Color(0xFF74659A),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 14,
                  ),
                  child: _isLoading
                      ? const SizedBox.shrink()
                      : _topBar(
                          today,
                          careTeam,
                          context,
                          showBackToPatients: cameFromNurseList,
                        ),
                ),
              ),
            ),

            // â”€â”€ Rest of the page â”€â”€
            Expanded(
              child: SafeArea(
                top: false,
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: _purple),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 18),

                          // â”€â”€ Welcome â”€â”€
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              'Welcome, $firstName',
                              style: GoogleFonts.nunito(
                                fontSize: 30,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // â”€â”€ Grid â”€â”€
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: _grid(),
                            ),
                          ),

                          const SizedBox(height: 6),

                          // â”€â”€ Emergency â”€â”€
                          if (careTeam.nurseLineNumber != null &&
                              careTeam.nurseLineNumber!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: _emergencyCard(careTeam),
                            ),

                          const SizedBox(height: 6),

                          // â”€â”€ Bottom Nav â”€â”€
                          _BottomNav(currentIndex: 0),

                          const SizedBox(height: 10),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // top bar with avatar, name, date, and menu button
  Widget _topBar(
    String today,
    CareTeam careTeam,
    BuildContext context, {
    required bool showBackToPatients,
  }) {
    return Row(
      children: [
        if (showBackToPatients) ...[
          GestureDetector(
            onTap: () => context.go('/nurse_patients'),
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.3),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white.withOpacity(0.4)),
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 15,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: Colors.white.withOpacity(0.7)),
          ),
          child: Center(
            child: Text(
              'E',
              style: GoogleFonts.nunito(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _purple,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "${careTeam.patientFirstName ?? 'Your'}'s Care Space",
                style: GoogleFonts.nunito(
                  fontSize: 20,
                  color: const Color.fromARGB(
                    255,
                    255,
                    255,
                    255,
                  ).withOpacity(0.75),
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                today,
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Builder(
          builder: (ctx) => GestureDetector(
            onTap: () => Scaffold.of(ctx).openDrawer(),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white.withOpacity(0.6)),
              ),
              child: const Icon(
                Icons.people_outline,
                size: 17,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // â”€â”€â”€ Grid â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _grid() {
    final cards = [
      _CardData(
        title: 'Medications',
        subtitle: 'Doses & logs',
        icon: Icons.medication_outlined,
        badge: _doseBadge,
        route: '/medications',
      ),
      _CardData(
        title: 'Symptoms',
        subtitle: 'Track changes',
        icon: Icons.monitor_heart_outlined,
        badge: _symptomBadge,
        route: '/symptoms',
      ),
      _CardData(
        title: 'Quick Notes',
        subtitle: 'Capture thoughts',
        icon: Icons.description_outlined,
        badge: _observationBadge,
        route: '/observations',
      ),
      _CardData(
        title: 'Moments',
        subtitle: 'What matters',
        icon: Icons.favorite_border_rounded,
        badge: _momentBadge,
        route: '/moments',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final spacing = 12.0;
        final cardW = (constraints.maxWidth - spacing) / 2;
        final cardH = (constraints.maxHeight - spacing) / 2;
        final cardSize = cardW < cardH ? cardW : cardH;

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _gridCard(cards[0], cardSize),
                  SizedBox(width: spacing),
                  _gridCard(cards[1], cardSize),
                ],
              ),
              SizedBox(height: spacing),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _gridCard(cards[2], cardSize),
                  SizedBox(width: spacing),
                  _gridCard(cards[3], cardSize),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _gridCard(_CardData c, double size) {
    return GestureDetector(
      onTap: () async {
        await context.push(c.route);
        if (!mounted) return;
        _loadData();
      },
      child: SizedBox(
        width: size,
        height: size,
        // âœ… clipBehavior.none allows badge to overflow outside card boundary
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.65),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: size * 0.3,
                        height: size * 0.3,
                        decoration: BoxDecoration(
                          color: const Color(0xFF8E7CB1).withOpacity(0.85),
                          borderRadius: BorderRadius.circular(size * 0.09),
                        ),
                        child: Icon(
                          c.icon,
                          color: Colors.white,
                          size: size * 0.14,
                        ),
                      ),
                      SizedBox(height: size * 0.07),
                      Text(
                        c.title,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(
                          fontSize: size * 0.13,
                          fontWeight: FontWeight.w600,
                          color: const Color.fromARGB(255, 9, 9, 9),
                        ),
                      ),
                      SizedBox(height: size * 0.02),
                      Text(
                        c.subtitle,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.nunito(
                          fontSize: size * 0.09,
                          color: const Color.fromARGB(255, 34, 34, 35),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // âœ… Badge â€” always visible, top-right corner
            if (c.badge > 0)
              Positioned(
                top: -8,
                right: -8,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.25),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      c.badge.toString(),
                      style: GoogleFonts.nunito(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // â”€â”€â”€ Emergency â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  Widget _emergencyCard(CareTeam careTeam) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.65)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.phone_outlined,
              size: 18,
              color: Color.fromARGB(255, 104, 8, 8),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Emergency Help',
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: const Color.fromARGB(255, 2, 2, 2),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Nurse on call 24/7',
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.black.withOpacity(0.62),
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              final num = careTeam.nurseLineNumber;
              if (num == null || num.isEmpty) return;
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(
                    'Emergency Call',
                    style: GoogleFonts.nunito(
                      fontWeight: FontWeight.w700,
                      color: const Color.fromARGB(255, 182, 34, 34),
                    ),
                  ),
                  content: Text(
                    'Are you sure you want to call the nurse line?\n\n$num',
                    style: GoogleFonts.nunito(),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: Text('Cancel', style: GoogleFonts.nunito()),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red.shade600,
                      ),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: Text(
                        'Yes, Call Now',
                        style: GoogleFonts.nunito(color: Colors.white),
                      ),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await launchUrl(Uri.parse('tel:$num'));
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'CALL NOW',
                style: GoogleFonts.nunito(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€ Card Data â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _CardData {
  final String title, subtitle, route;
  final IconData icon;
  final int badge;
  const _CardData({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badge,
    required this.route,
  });
}

// â”€â”€â”€ Bottom Nav â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
class _BottomNav extends StatelessWidget {
  final int currentIndex;
  const _BottomNav({required this.currentIndex});

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
    return ClipRRect(
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
              size: 19,
              color: isActive
                  ? const Color(0xFF6B5B8E)
                  : const Color(0xFFB0A8C8),
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

//  Drawer with navigation links and sign out option
class _AppDrawer extends StatelessWidget {
  final String patientName;
  const _AppDrawer({required this.patientName});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF74659A), Color(0xFFDFDBE5)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Epilogue',
                      style: GoogleFonts.nunito(
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      "$patientName's Care Space",
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: Colors.white.withOpacity(0.24)),
              const SizedBox(height: 8),
              _drawerItem(
                context,
                icon: Icons.people_outline,
                label: 'Care Team',
                fontSize: 18,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CareTeamScreen()),
                  );
                },
              ),
              _drawerItem(
                context,
                icon: Icons.medical_information_outlined,
                label: 'Care Plan',
                fontSize: 18,
                onTap: () {
                  Navigator.pop(context);
                  context.push('/care_plan');
                },
              ),
              const Spacer(),
              Divider(color: Colors.white.withOpacity(0.24)),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _signOutButton(
                  context,
                  onTap: () async {
                    final rootContext = Navigator.of(
                      context,
                      rootNavigator: true,
                    ).context;
                    Navigator.pop(context);
                    await Supabase.instance.client.auth.signOut();
                    await SessionManager().clearSession();
                    if (!rootContext.mounted) return;
                    rootContext.go('/login');
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    double fontSize = 16,
  }) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.white, size: 20),
      title: Text(
        label,
        style: GoogleFonts.nunito(
          fontSize: fontSize,
          fontWeight: FontWeight.w500,
          color: color ?? Colors.white,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
    );
  }

  Widget _signOutButton(BuildContext context, {required VoidCallback onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3F3),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFF0B5B5), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF8A2D2D).withOpacity(0.10),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color.fromARGB(255, 255, 255, 255),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: Color.fromARGB(255, 248, 0, 0),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Sign out',
                      style: GoogleFonts.nunito(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: const Color.fromARGB(255, 241, 2, 2),
                      ),
                    ),
                    Text(
                      'Return to the login screen',
                      style: GoogleFonts.nunito(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: const Color.fromARGB(255, 0, 0, 0),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: Color.fromARGB(255, 247, 1, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
