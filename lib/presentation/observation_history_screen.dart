import 'dart:io';

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

class QuickNotesHistoryScreen extends StatefulWidget {
  const QuickNotesHistoryScreen({super.key});

  @override
  State<QuickNotesHistoryScreen> createState() =>
      _QuickNotesHistoryScreenState();
}

class _QuickNotesHistoryScreenState extends State<QuickNotesHistoryScreen> {
  final _service = SupabaseService();

  List<Observation> _notes = [];
  bool _isLoading = true;
  final Set<String> _expandedNoteIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _isLoading = true);

    try {
      final careTeamId = SessionManager().currentCareTeam?.id;
      if (careTeamId == null) return;

      final notes = await _service.getObservations(
        careTeamId,
        includeDeleted: true,
      );

      if (!mounted) return;
      setState(() => _notes = notes);
    } catch (e) {
      debugPrint('Quick notes history error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, List<Observation>> _groupNotes() {
    final grouped = <String, List<Observation>>{};

    for (final note in _notes) {
      final date = note.createdAt;
      if (date == null) continue;
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
      grouped[key]!.add(note);
    }

    return grouped;
  }

  IconData _iconFor(Observation note) {
    switch (note.category) {
      case 'photo':
        return Icons.photo_camera_back_outlined;
      case 'voice':
        return Icons.mic_none_rounded;
      default:
        return Icons.description_outlined;
    }
  }

  String _titleFor(Observation note) {
    switch (note.category) {
      case 'photo':
        return 'Photo note';
      case 'voice':
        return 'Voice note';
      default:
        return (note.content ?? '').trim().isEmpty
            ? 'Note'
            : note.content!.trim();
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName =
        SessionManager().currentCareTeam?.patientFirstName ?? 'Patient';
    final groupedNotes = _groupNotes();

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
                    : _notes.isEmpty
                    ? Center(
                        child: Text(
                          'No notes history yet',
                          style: GoogleFonts.nunito(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                        children: groupedNotes.entries.map((entry) {
                          final dateTitle = entry.key;
                          final notes = entry.value;

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
                              ...notes.map((note) {
                                final time = note.createdAt != null
                                    ? DateFormat(
                                        'h:mm a',
                                      ).format(note.createdAt!)
                                    : '';

                                final isPhoto = note.category == 'photo';
                                final hasPhoto =
                                    isPhoto && (note.content ?? '').isNotEmpty;
                                final canExpand =
                                    !hasPhoto &&
                                    (note.content ?? '').trim().isNotEmpty;
                                final isExpanded = _expandedNoteIds.contains(
                                  note.id,
                                );

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
                                      Icon(_iconFor(note), color: _purple),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            if (hasPhoto)
                                              ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Image.file(
                                                  File(note.content!),
                                                  height: 120,
                                                  width: double.infinity,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      Container(
                                                        height: 90,
                                                        width: double.infinity,
                                                        color: Colors.white,
                                                        alignment:
                                                            Alignment.center,
                                                        child: Text(
                                                          'Photo unavailable',
                                                          style:
                                                              GoogleFonts.nunito(
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700,
                                                                color:
                                                                    _deepPurple,
                                                              ),
                                                        ),
                                                      ),
                                                ),
                                              )
                                            else
                                              Text(
                                                _titleFor(note),
                                                maxLines: isExpanded ? null : 3,
                                                overflow: isExpanded
                                                    ? TextOverflow.visible
                                                    : TextOverflow.ellipsis,
                                                style: GoogleFonts.nunito(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: _deepPurple,
                                                ),
                                              ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'Logged by: ${note.createdByMemberName ?? 'Caregiver'}',
                                              style: GoogleFonts.nunito(
                                                fontSize: 16,
                                                color: Colors.black,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            time,
                                            style: GoogleFonts.nunito(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                              color: _deepPurple,
                                            ),
                                          ),
                                          if (canExpand)
                                            GestureDetector(
                                              onTap: () {
                                                setState(() {
                                                  if (isExpanded) {
                                                    _expandedNoteIds.remove(
                                                      note.id,
                                                    );
                                                  } else {
                                                    _expandedNoteIds.add(
                                                      note.id,
                                                    );
                                                  }
                                                });
                                              },
                                              child: Icon(
                                                isExpanded
                                                    ? Icons.keyboard_arrow_up
                                                    : Icons.keyboard_arrow_down,
                                                size: 24,
                                                color: _deepPurple,
                                              ),
                                            ),
                                        ],
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
