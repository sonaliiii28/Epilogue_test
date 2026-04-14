import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/session_manager.dart';
import '../core/supabase_service.dart';
import 'premium_bottom_nav.dart';

const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _mutedPurple = Color(0xFF6C648B);
const _borderColor = Color(0xFFD4CDDF);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

class NursePatientList extends StatelessWidget {
  const NursePatientList({super.key});

  @override
  Widget build(BuildContext context) {
    return const _NursePatientListBody();
  }
}

class _NursePatientListBody extends StatefulWidget {
  const _NursePatientListBody();

  @override
  State<_NursePatientListBody> createState() => _NursePatientListBodyState();
}

class _NursePatientListBodyState extends State<_NursePatientListBody> {
  final _supabaseService = SupabaseService();
  late final Future<List<CareTeamMembership>> _membershipsFuture;

  @override
  void initState() {
    super.initState();
    final email = SessionManager().currentMember?.email ?? '';
    _membershipsFuture = _supabaseService.getCareTeamsForMedicalMember(email);
  }

  Future<void> _openPatientDashboard(CareTeamMembership membership) async {
    await SessionManager().setSession(membership.careTeam, membership.member);
    if (!mounted) return;
    context.push('/dashboard?from=nurse_patients');
  }

  Future<void> _openVisit(CareTeamMembership membership) async {
    // For now, “Visit” is the same action as opening the care space.
    // If you later add a dedicated visit workflow, wire it here.
    await _openPatientDashboard(membership);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [_bg1, _bg2],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => context.go('/'),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'My Patients',
                            style: GoogleFonts.nunito(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            'Select a patient to visit',
                            style: GoogleFonts.nunito(
                              fontSize: 20,
                              color: Colors.white.withOpacity(0.75),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: _borderColor, thickness: 1),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<List<CareTeamMembership>>(
                  future: _membershipsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: _purple),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'Failed to load patients: ${snapshot.error}',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    final memberships = snapshot.data ?? const [];
                    if (memberships.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Text(
                            'No patients found yet. Join a care team using an invite code to see it here.',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                      itemCount: memberships.length,
                      itemBuilder: (context, index) {
                        final membership = memberships[index];
                        final patientName =
                            membership.careTeam.patientFirstName ?? 'Patient';
                        return _PatientCard(
                          name: patientName,
                          lastVisitedAt: membership.member.joinedAt,
                          onOpenDashboard: () =>
                              _openPatientDashboard(membership),
                          onVisit: () => _openVisit(membership),
                          onDeactivate: () async {
                            // Spec: show button; action can be wired later.
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Deactivate not implemented yet',
                                  style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
              const PremiumBottomNav(currentIndex: 0),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientCard extends StatefulWidget {
  final String name;
  final DateTime? lastVisitedAt;
  final VoidCallback onOpenDashboard;
  final VoidCallback onVisit;
  final VoidCallback onDeactivate;

  const _PatientCard({
    required this.name,
    required this.lastVisitedAt,
    required this.onOpenDashboard,
    required this.onVisit,
    required this.onDeactivate,
  });

  @override
  State<_PatientCard> createState() => _PatientCardState();
}

class _PatientCardState extends State<_PatientCard> {
  bool _expanded = false;

  String _lastVisitedLabel() {
    final last = widget.lastVisitedAt;
    if (last == null) return 'Not yet visited';
    return DateFormat('MMM d, yyyy h:mm a').format(last);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
        boxShadow: _expanded
            ? [
                BoxShadow(
                  color: _purple.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFF8E7CB1).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.person_outline,
                    size: 20,
                    color: _purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.name,
                        style: GoogleFonts.nunito(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: _deepPurple,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Last visited',
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color.fromARGB(255, 27, 27, 28),
                        ),
                      ),
                      Text(
                        _lastVisitedLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _expanded = !_expanded),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: _mutedPurple.withOpacity(0.5),
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 16),
              const Divider(color: _borderColor),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: widget.onOpenDashboard,
                      child: Text(
                        'Dashboard',
                        style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: _borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: widget.onVisit,
                      child: Text(
                        'Visit',
                        style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w700,
                          color: _deepPurple,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: _borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: widget.onDeactivate,
                      child: Text(
                        'Deactivate',
                        style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w700,
                          color: _deepPurple,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
