import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/session_manager.dart';
import 'moment_store.dart';

const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _borderColor = Color(0xFFD4CDDF);
const _cardBg = Color(0xFFF0EDF6);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

class MomentsHistoryScreen extends StatelessWidget {
  const MomentsHistoryScreen({super.key});

  Map<String, List<MomentEntry>> _groupMoments(List<MomentEntry> moments) {
    final grouped = <String, List<MomentEntry>>{};

    for (final moment in moments) {
      final date = moment.createdAt;
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

      grouped.putIfAbsent(key, () => <MomentEntry>[]);
      grouped[key]!.add(moment);
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final patientName =
        SessionManager().currentCareTeam?.patientFirstName ?? 'Patient';

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
          child: ValueListenableBuilder<List<MomentEntry>>(
            valueListenable: momentEntriesNotifier,
            builder: (context, allMoments, _) {
              final moments = allMoments.toList()
                ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              final groupedMoments = _groupMoments(moments);

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (context.canPop()) {
                              context.pop();
                            } else {
                              context.go('/moments');
                            }
                          },
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
                    child: moments.isEmpty
                        ? Center(
                            child: Text(
                              'No moments history yet',
                              style: GoogleFonts.nunito(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : ListView(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                            children: groupedMoments.entries.map((entry) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      top: 16,
                                      bottom: 8,
                                    ),
                                    child: Text(
                                      entry.key,
                                      style: GoogleFonts.nunito(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  ...entry.value.map((moment) {
                                    final time = DateFormat(
                                      'h:mm a',
                                    ).format(moment.createdAt);

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
                                            Icons.auto_awesome,
                                            color: _purple,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                if (moment.photoPath !=
                                                    null) ...[
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: Image.file(
                                                      File(moment.photoPath!),
                                                      height: 120,
                                                      width: double.infinity,
                                                      fit: BoxFit.cover,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 10),
                                                ],
                                                if (moment.content.isNotEmpty)
                                                  Text(
                                                    moment.content,
                                                    style: GoogleFonts.nunito(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: _deepPurple,
                                                    ),
                                                  )
                                                else
                                                  Text(
                                                    moment.audioPath != null
                                                        ? 'Voice moment'
                                                        : 'Photo moment',
                                                    style: GoogleFonts.nunito(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: _deepPurple,
                                                    ),
                                                  ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Logged by: ${moment.authorName}',
                                                  style: GoogleFonts.nunito(
                                                    fontSize: 16,
                                                    color: Colors.black,
                                                  ),
                                                ),
                                                if (moment.deletedAt != null)
                                                  Text(
                                                    'Deleted',
                                                    style: GoogleFonts.nunito(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color:
                                                          Colors.red.shade700,
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
              );
            },
          ),
        ),
      ),
    );
  }
}
