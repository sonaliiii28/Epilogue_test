import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/session_manager.dart';
import '../core/supabase_service.dart';
import '../domain/models.dart';

// ─── Colors ───────────────────────────────────────────────────────────────────
const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _mutedPurple = Color(0xFF6C648B);
const _lightPurple = Color(0xFFB0A8C8);
const _borderColor = Color(0xFFD4CDDF);
const _cardBg = Color(0xFFF0EDF6);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _service = SupabaseService();
  List<Medication> _deprescribedMeds = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDeprescribedMedications();
  }

  Future<void> _loadDeprescribedMedications() async {
    setState(() => _isLoading = true);
    try {
      final careTeamId = SessionManager().currentCareTeam?.id;
      if (careTeamId == null) return;
      final allMeds = await _service.getMedications(careTeamId);
      if (!mounted) return;
      final inactive = allMeds.where((m) => m.pattern == 'inactive').toList()
        ..sort((a, b) {
          final aDate = a.deprescribedAt ?? a.createdAt;
          final bDate = b.deprescribedAt ?? b.createdAt;
          if (aDate == null && bDate == null) return 0;
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          return bDate.compareTo(aDate); // newest first
        });
      setState(() => _deprescribedMeds = inactive);
    } catch (e) {
      debugPrint('Error loading deprescribed medications: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Group medications by deprescribed/created date (day granularity).
  Map<String, List<Medication>> _groupByDate() {
    final Map<String, List<Medication>> grouped = {};
    for (final med in _deprescribedMeds) {
      final date = med.deprescribedAt ?? med.createdAt;
      final key = date != null
          ? DateFormat('MMMM d, yyyy').format(date)
          : 'Unknown Date';
      grouped.putIfAbsent(key, () => []).add(med);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDate();
    final dateKeys = grouped.keys.toList();

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
              // ── Header ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
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
                          size: 15,
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
                            'Deprescribed History',
                            style: GoogleFonts.nunito(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "${SessionManager().currentCareTeam?.patientFirstName ?? 'Your'}'s Medications",
                            style: GoogleFonts.nunito(
                              fontSize: 16,
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

              // ── Body ──
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: _purple),
                      )
                    : _deprescribedMeds.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        itemCount: dateKeys.length,
                        itemBuilder: (context, index) {
                          final dateLabel = dateKeys[index];
                          final meds = grouped[dateLabel]!;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (index > 0) const SizedBox(height: 20),
                              // Date header
                              Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today_outlined,
                                    size: 13,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    dateLabel,
                                    style: GoogleFonts.nunito(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white.withOpacity(0.8),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ...meds.map(_deprescribedCard),
                            ],
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deprescribedCard(Medication med) {
    final addedDate = med.createdAt != null
        ? DateFormat('MMM d, yyyy').format(med.createdAt!)
        : null;
    final deprescribedDate = med.deprescribedAt != null
        ? DateFormat('MMM d, yyyy').format(med.deprescribedAt!)
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.35),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor.withOpacity(0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _borderColor.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.medication_outlined,
                    size: 18,
                    color: _lightPurple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name ?? 'Unknown',
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _deepPurple.withOpacity(0.7),
                        ),
                      ),
                      if (med.strength != null)
                        Text(
                          med.strength!,
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            color: _mutedPurple,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _lightPurple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Deprescribed',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      color: _lightPurple,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),

            // Info chips
            if (med.typicalDose != null || med.route != null) ...[
              const SizedBox(height: 12),
              const Divider(color: _borderColor, height: 1),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (med.typicalDose != null)
                    _infoChip(Icons.scale_outlined, med.typicalDose!),
                  if (med.route != null)
                    _infoChip(Icons.directions_outlined, med.route!),
                ],
              ),
            ],

            if (med.scheduleDetails != null) ...[
              const SizedBox(height: 8),
              Text(
                med.scheduleDetails!,
                style: GoogleFonts.nunito(
                  fontSize: 16,
                  color: _mutedPurple,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],

            // Date info
            const SizedBox(height: 10),
            const Divider(color: _borderColor, height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                if (addedDate != null) ...[
                  Icon(Icons.add_circle_outline, size: 11, color: _lightPurple),
                  const SizedBox(width: 4),
                  Text(
                    'Added $addedDate',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      color: _lightPurple,
                    ),
                  ),
                ],
                if (addedDate != null && deprescribedDate != null)
                  const SizedBox(width: 16),
                if (deprescribedDate != null) ...[
                  Icon(
                    Icons.remove_circle_outline,
                    size: 11,
                    color: _lightPurple,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Deprescribed $deprescribedDate',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      color: _lightPurple,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: _mutedPurple),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.nunito(
              fontSize: 15,
              color: _mutedPurple,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFE1DCEA),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.history_outlined,
              size: 32,
              color: _lightPurple,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No deprescribed medications',
            style: GoogleFonts.nunito(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _deepPurple,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Deprescribed medications will appear here',
            style: GoogleFonts.nunito(fontSize: 15, color: _mutedPurple),
          ),
        ],
      ),
    );
  }
}

