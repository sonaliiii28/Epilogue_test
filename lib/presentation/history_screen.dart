import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../core/session_manager.dart';
import '../core/supabase_service.dart';
import '../domain/models.dart';

// ─── Colors ───────────────────────────────────────────────────────────────────
const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
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

  List<DoseLog> _logs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);

    try {
      final careTeamId = SessionManager().currentCareTeam?.id;
      if (careTeamId == null) return;

      final logs = await _service.getDoseLogs(careTeamId);

      if (!mounted) return;

      setState(() {
        _logs = logs;
      });
    } catch (e) {
      debugPrint("History error: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// ─── Group logs like YouTube history ───
  Map<String, List<DoseLog>> _groupLogs() {
    final Map<String, List<DoseLog>> grouped = {};

    for (final log in _logs) {
      final date = log.doseTime!;
      final now = DateTime.now();

      String key;

      if (DateUtils.isSameDay(date, now)) {
        key = "Today";
      } else if (DateUtils.isSameDay(
          date, now.subtract(const Duration(days: 1)))) {
        key = "Yesterday";
      } else {
        key = DateFormat('MMM d, yyyy').format(date);
      }

      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(log);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final patientName =
        SessionManager().currentCareTeam?.patientFirstName ?? 'Patient';

    final groupedLogs = _groupLogs();

    return Scaffold(
      body: Container(
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
              /// ─── HEADER ───
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
                            "History",
                            style: GoogleFonts.nunito(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "$patientName's Care Space",
                            style: GoogleFonts.nunito(
                              fontSize: 20,
                              color: Colors.white.withOpacity(0.75),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    )
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: _borderColor.withOpacity(0.6)),
              ),

              const SizedBox(height: 16),

              /// ─── BODY ───
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _logs.isEmpty
                        ? Center(
                            child: Text(
                              "No medication history yet",
                              style: GoogleFonts.nunito(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                            children: groupedLogs.entries.map((entry) {
                              final dateTitle = entry.key;
                              final logs = entry.value;

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  /// Date Header
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 16, bottom: 8),
                                    child: Text(
                                      dateTitle,
                                      style: GoogleFonts.nunito(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),

                                  /// Logs
                                  ...logs.map((log) {
                                    final time =
                                        DateFormat('h:mm a').format(log.doseTime!);

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: _cardBg,
                                        borderRadius: BorderRadius.circular(16),
                                        border:
                                            Border.all(color: _borderColor),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.medication,
                                              color: _purple),
                                          const SizedBox(width: 12),

                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  log.medicationName ??
                                                      "Medication",
                                                  style: GoogleFonts.nunito(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w700,
                                                    color: _deepPurple,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  "Dose: ${log.amountGiven ?? '-'}",
                                                  style: GoogleFonts.nunito(
                                                    fontSize: 16,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                                Text(
                                                  "Given by: ${log.whoGave ?? 'Caregiver'}",
                                                  style: GoogleFonts.nunito(
                                                    fontSize: 16,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                          Text(
                                            time,
                                            style: GoogleFonts.nunito(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: _deepPurple,
                                            ),
                                          )
                                        ],
                                      ),
                                    );
                                  })
                                ],
                              );
                            }).toList(),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
