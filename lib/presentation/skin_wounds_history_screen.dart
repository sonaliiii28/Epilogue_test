import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/session_manager.dart';
import '../core/supabase_service.dart';
import '../domain/models.dart';

const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _borderColor = Color(0xFFD4CDDF);
const _cardBg = Color(0xFFF0EDF6);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

class SkinWoundsHistoryScreen extends StatefulWidget {
  const SkinWoundsHistoryScreen({super.key});

  @override
  State<SkinWoundsHistoryScreen> createState() =>
      _SkinWoundsHistoryScreenState();
}

class _SkinWoundsHistoryScreenState extends State<SkinWoundsHistoryScreen> {
  final _service = SupabaseService();

  List<SkinWoundEvent> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    setState(() => _isLoading = true);

    try {
      final careTeamId = SessionManager().currentCareTeam?.id;
      if (careTeamId == null) return;

      final events = await _service.getSkinWoundEventsIncludingDeleted(
        careTeamId,
      );

      if (!mounted) return;
      setState(() => _events = events);
    } catch (e) {
      debugPrint('Skin history error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _titleForEvent(SkinWoundEvent event) {
    if (!event.hasSkinCondition) return 'No skin issues';
    final title = (event.skinCondition ?? '').trim();
    if (title.isNotEmpty) return title;
    return 'Skin record';
  }

  Map<String, List<SkinWoundEvent>> _groupEvents() {
    final grouped = <String, List<SkinWoundEvent>>{};

    for (final event in _events) {
      final date = event.eventTime;
      final now = DateTime.now();

      String key;
      if (DateUtils.isSameDay(date, now)) {
        key = 'Today';
      } else if (DateUtils.isSameDay(
        date,
        now.subtract(const Duration(days: 1)),
      )) {
        key = 'Yesterday';
      } else {
        key = DateFormat('MMM d, yyyy').format(date);
      }

      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(event);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final patientName =
        SessionManager().currentCareTeam?.patientFirstName ?? 'Patient';
    final groupedEvents = _groupEvents();

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
                            'History',
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Divider(color: _borderColor.withOpacity(0.6)),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _events.isEmpty
                    ? Center(
                        child: Text(
                          'No skin history yet',
                          style: GoogleFonts.nunito(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        children: groupedEvents.entries.map((entry) {
                          final dateTitle = entry.key;
                          final events = entry.value;

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 16,
                                  bottom: 8,
                                ),
                                child: Text(
                                  dateTitle,
                                  style: GoogleFonts.nunito(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              ...events.map((event) {
                                final time = DateFormat(
                                  'h:mm a',
                                ).format(event.eventTime);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: _cardBg,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _borderColor),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.healing_outlined,
                                        color: _purple,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _titleForEvent(event),
                                              style: GoogleFonts.nunito(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w700,
                                                color: _deepPurple,
                                              ),
                                            ),
                                            Text(
                                              'Logged by: ${event.createdByMemberName ?? 'Caregiver'}',
                                              style: GoogleFonts.nunito(
                                                fontSize: 16,
                                                color: Colors.black,
                                              ),
                                            ),
                                            if (event.deletedAt != null)
                                              Text(
                                                'Deleted',
                                                style: GoogleFonts.nunito(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.red.shade600,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        time,
                                        style: GoogleFonts.nunito(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: _deepPurple,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
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
