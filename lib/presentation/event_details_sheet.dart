import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/supabase_service.dart';
import '../domain/models.dart';

class EventDetailsSheet extends StatelessWidget {
  const EventDetailsSheet({super.key, required this.event});

  final CalendarEvent event;

  String _formatType(EventType type) {
    switch (type) {
      case EventType.medication:
        return 'Medication';
      case EventType.visit:
        return 'Visit';
      case EventType.care:
        return 'Care Activity';
      case EventType.symptom:
        return 'Symptom';
    }
  }

  String? _extractVisitorName(String? notes) {
    if (notes == null) return null;
    const prefix = '[[VISITOR]]:';
    if (!notes.startsWith(prefix)) return null;
    final v = notes.substring(prefix.length).trim();
    return v.isEmpty ? null : v;
  }

  Future<Map<String, dynamic>?> _loadRelatedDetails() async {
    if (event.relatedId == null) return null;

    final service = SupabaseService();
    switch (event.type) {
      case EventType.medication:
        return service.getMedicationDetails(event.relatedId!);
      case EventType.symptom:
        return service.getSymptomDetails(event.relatedId!);
      case EventType.visit:
      case EventType.care:
        return null;
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.nunito(
            fontSize: 16,
            color: const Color(0xFF2E2540),
          ),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visitorName = event.type == EventType.visit
        ? _extractVisitorName(event.notes)
        : null;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: Color(0xFFF0EDF6),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _formatType(event.type),
              style: GoogleFonts.nunito(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF2E2540),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              DateFormat.yMMMEd().add_jm().format(event.dateTime),
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF2E2540),
              ),
            ),
            const SizedBox(height: 10),
            _infoRow(
              'Source',
              event.source == 'manual' ? 'Manual' : 'System Generated',
            ),
            _infoRow('Created by', event.createdBy ?? 'System'),
            const Divider(height: 24),
            if (event.type == EventType.medication) ...[
              _infoRow('Medication', event.title),
            ],
            if (event.type == EventType.symptom) ...[
              _infoRow('Severity', event.severity ?? '-'),
              if (event.notes?.isNotEmpty ?? false)
                _infoRow('Notes', event.notes!),
            ],
            if (event.type == EventType.visit ||
                event.type == EventType.care) ...[
              if (event.duration != null)
                _infoRow('Duration', '${event.duration} mins'),
              if (visitorName != null)
                _infoRow('Visitor name', visitorName)
              else if (event.notes?.isNotEmpty ?? false)
                _infoRow('Notes', event.notes!),
            ],
            FutureBuilder<Map<String, dynamic>?>(
              future: _loadRelatedDetails(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: LinearProgressIndicator(minHeight: 2),
                  );
                }

                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'Extra details unavailable right now.',
                      style: GoogleFonts.nunito(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  );
                }

                final data = snapshot.data;
                if (data == null) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 24),
                      if (event.type == EventType.medication) ...[
                        if ((data['strength'] as String?)?.isNotEmpty ?? false)
                          _infoRow('Dosage', data['strength'] as String),
                        if ((data['pattern'] as String?)?.isNotEmpty ?? false)
                          _infoRow('Frequency', data['pattern'] as String),
                        if ((data['schedule_details'] as String?)?.isNotEmpty ??
                            false)
                          _infoRow(
                            'Instructions',
                            data['schedule_details'] as String,
                          ),
                      ],
                      if (event.type == EventType.symptom) ...[
                        if ((data['severity'] as String?)?.isNotEmpty ?? false)
                          _infoRow(
                            'Recorded severity',
                            data['severity'] as String,
                          ),
                        if ((data['what_happened'] as String?)?.isNotEmpty ??
                            false)
                          _infoRow('Notes', data['what_happened'] as String),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
