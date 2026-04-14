import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../core/note_voice_codec.dart';
import '../core/session_manager.dart';
import '../core/supabase_service.dart';
import '../domain/models.dart';
import '../domain/symptom_data.dart';
import 'calendar_service.dart';
import 'premium_bottom_nav.dart';
import 'widgets/voice_note_attachment.dart';

const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _mutedPurple = Color(0xFF6C648B);
const _lightPurple = Color(0xFFB0A8C8);
const _borderColor = Color(0xFFD4CDDF);
const _cardBg = Color(0xFFF0EDF6);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

/// Sorted symptom list for the UI, alphabetical by name.
final _sortedSymptoms = List<SymptomDefinition>.from(kHospiceSymptoms)
  ..sort((a, b) => a.name.compareTo(b.name));

const hopeSymptoms = [
  'Pain',
  'Shortness of breath',
  'Nausea',
  'Anxiety / Feeling nervous',
  'Vomiting',
  'Diarrhea',
  'Constipation',
  'Agitation',
];

/// Canonical allowlist for symptoms that should trigger the
/// "In-Person Follow Up Required" indicator.
///
/// Note: UI labels differ from the core symptom definitions (e.g.
/// "Shortness of breath" vs "Breathlessness"), so we include known variants.
const kHopeSymptomNames = <String>{
  'Pain',
  'Shortness of breath',
  'Breathlessness',
  'Nausea',
  'Anxiety / Feeling nervous',
  'Anxiety',
  'Vomiting',
  'Diarrhea',
  'Constipation',
  'Agitation',
};

bool _isHopeSymptomName(String name) => kHopeSymptomNames.contains(name.trim());

class SymptomEventsScreen extends StatefulWidget {
  const SymptomEventsScreen({super.key});

  @override
  State<SymptomEventsScreen> createState() => _SymptomEventsScreenState();
}

class _SymptomEventsScreenState extends State<SymptomEventsScreen> {
  final _service = SupabaseService();
  final _calendarService = CalendarService();
  final _uuid = const Uuid();
  List<SymptomEvent> _events = [];
  bool _isLoading = true;
  Set<String> _locallyHiddenEventIds = <String>{};

  bool _isLegacySkinWoundEvent(SymptomEvent event) {
    final symptoms = event.symptoms ?? const <String>[];
    for (final symptom in symptoms) {
      final name = symptom.split(':').first.trim().toLowerCase();
      if (name == 'skin & wounds' ||
          name == 'skin & wound' ||
          name == 'skin and wounds' ||
          name == 'skin and wound' ||
          name == 'skin&wounds' ||
          name == 'skin&wound') {
        return true;
      }
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _loadLocallyHiddenIds();
    await _loadEvents();
  }

  String _hiddenIdsKey(String careTeamId) =>
      'symptom_events_hidden_ids:$careTeamId';

  Future<void> _loadLocallyHiddenIds() async {
    final careTeamId = SessionManager().currentCareTeam?.id;
    if (careTeamId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_hiddenIdsKey(careTeamId)) ?? const [];
    _locallyHiddenEventIds = list.toSet();
  }

  Future<void> _hideEventLocally(String eventId) async {
    final careTeamId = SessionManager().currentCareTeam?.id;
    if (careTeamId == null) return;
    final prefs = await SharedPreferences.getInstance();
    _locallyHiddenEventIds = {..._locallyHiddenEventIds, eventId};
    await prefs.setStringList(
      _hiddenIdsKey(careTeamId),
      _locallyHiddenEventIds.toList(),
    );
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final teamId = SessionManager().currentCareTeam?.id;
      if (teamId == null) return;
      final result = await _service.getSymptomEvents(teamId);
      final visible = result
          .where((e) => e.deletedAt == null)
          // Legacy data: some skin/wound logs were previously stored as
          // symptom_events (e.g. a symptom named "Skin & Wounds"). Those
          // belong exclusively to the Skin & Wounds module.
          .where((e) => !_isLegacySkinWoundEvent(e))
          .where((e) => !_locallyHiddenEventIds.contains(e.id))
          .toList();
      if (mounted) setState(() => _events = visible);
    } catch (e) {
      debugPrint('Error loading symptom events: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showLogSymptomModal() {
    // Set of selected symptom IDs.
    final selectedIds = <String>{};
    // Per-symptom severity selection
    final selectedRatings = <String, String>{};
    final searchCtrl = TextEditingController();
    final additionalNotesCtrl = TextEditingController();
    String? voiceNotePath;
    List<SymptomDefinition> filteredSymptoms = List.from(_sortedSymptoms);
    bool nurseContacted = false;
    final selectedHopeSymptoms = <String>{};
    final selectedHopeRatings = <String, String>{};

    const ratingOptions = <String>['Not at all', 'Mild', 'Moderate', 'Severe'];

    int severityRank(String severity) {
      switch (severity) {
        case 'Not at all':
          return 0;
        case 'Mild':
          return 1;
        case 'Moderate':
          return 2;
        case 'Severe':
          return 3;
        default:
          return 1;
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) {
          // Check if any selected symptom triggers a nurse alert
          final hasAlert = selectedIds.any((id) {
            final def = kSymptomById[id];
            return def != null && def.isAlertTrigger;
          });

          // Banner alert should only react to regular symptom ratings.
          // The 8 HOPE symptoms keep their own in-card follow-up message.
          final hasSfvRating = selectedRatings.values.any(
            (v) => severityRank(v) >= 2,
          );
          final showNurseAlert = hasAlert || hasSfvRating;

          final selectedDefs =
              selectedIds
                  .map((id) => kSymptomById[id])
                  .whereType<SymptomDefinition>()
                  .toList()
                ..sort((a, b) => a.name.compareTo(b.name));

          return Container(
            height: MediaQuery.of(ctx).size.height * 0.92,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFEDE8F5), Color(0xFFDAD4E6)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              children: [
                // Handle
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),

                // Title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      Text(
                        'Log Symptoms',
                        style: GoogleFonts.nunito(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          color: const Color.fromARGB(255, 0, 0, 0),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.only(
                      left: 24,
                      right: 24,
                      bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Text(
                          'Choose Your Symptom or Search Below',
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _deepPurple,
                          ),
                        ),
                        const SizedBox(height: 12),

                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: hopeSymptoms.map((symptom) {
                              final isSelected = selectedHopeSymptoms.contains(
                                symptom,
                              );
                              return GestureDetector(
                                onTap: () {
                                  setModal(() {
                                    if (isSelected) {
                                      selectedHopeSymptoms.remove(symptom);
                                      selectedHopeRatings.remove(symptom);
                                    } else {
                                      selectedHopeSymptoms.add(symptom);
                                      selectedHopeRatings[symptom] =
                                          selectedHopeRatings[symptom] ??
                                          ratingOptions[1];
                                    }
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isSelected ? _purple : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: isSelected
                                          ? _purple
                                          : _borderColor,
                                    ),
                                  ),
                                  child: Text(
                                    symptom,
                                    style: GoogleFonts.nunito(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Text(
                            'Symptom name',
                            style: GoogleFonts.nunito(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _deepPurple,
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: searchCtrl.text.isNotEmpty
                                  ? _purple
                                  : _borderColor,
                              width: searchCtrl.text.isNotEmpty ? 1.8 : 1.0,
                            ),
                            boxShadow: searchCtrl.text.isNotEmpty
                                ? [
                                    BoxShadow(
                                      color: _purple.withOpacity(0.15),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : const [],
                          ),
                          child: TextField(
                            controller: searchCtrl,
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              color: _deepPurple,
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search symptom name...',
                              hintStyle: GoogleFonts.nunito(
                                fontSize: 16,
                                color: _mutedPurple,
                                fontWeight: FontWeight.w500,
                              ),
                              border: InputBorder.none,
                              prefixIcon: const Icon(
                                Icons.search_rounded,
                                size: 22,
                                color: _deepPurple,
                              ),
                              suffixIcon: searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear,
                                        size: 20,
                                        color: _deepPurple,
                                      ),
                                      onPressed: () {
                                        searchCtrl.clear();
                                        setModal(() {
                                          filteredSymptoms = List.from(
                                            _sortedSymptoms,
                                          );
                                        });
                                      },
                                    )
                                  : null,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 0,
                                vertical: 14,
                              ),
                            ),
                            onChanged: (value) {
                              setModal(() {
                                filteredSymptoms = _sortedSymptoms
                                    .where(
                                      (s) => s.name.toLowerCase().contains(
                                        value.toLowerCase(),
                                      ),
                                    )
                                    .toList();
                              });
                            },
                          ),
                        ),
                        if (searchCtrl.text.trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 240),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _borderColor),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: filteredSymptoms.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 18,
                                      ),
                                      child: Text(
                                        'No symptoms found',
                                        style: GoogleFonts.nunito(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: _mutedPurple,
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      shrinkWrap: true,
                                      itemCount: filteredSymptoms.length,
                                      separatorBuilder: (_, __) => Divider(
                                        height: 1,
                                        color: _borderColor.withOpacity(0.7),
                                      ),
                                      itemBuilder: (_, i) {
                                        final def = filteredSymptoms[i];
                                        final isSelected = selectedIds.contains(
                                          def.id,
                                        );
                                        final subtitle =
                                            def.description
                                                    ?.trim()
                                                    .isNotEmpty ==
                                                true
                                            ? def.description!.trim()
                                            : def.options.isNotEmpty
                                            ? def.options.join(', ')
                                            : def.inputType ==
                                                  SymptomInputType.event
                                            ? 'Event symptom'
                                            : null;

                                        return ListTile(
                                          dense: true,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 4,
                                              ),
                                          title: Text(
                                            def.name,
                                            style: GoogleFonts.nunito(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: _deepPurple,
                                            ),
                                          ),
                                          subtitle: subtitle != null
                                              ? Text(
                                                  subtitle,
                                                  style: GoogleFonts.nunito(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w500,
                                                    color: _mutedPurple,
                                                  ),
                                                )
                                              : null,
                                          trailing: isSelected
                                              ? const Icon(
                                                  Icons.check_circle,
                                                  color: _purple,
                                                )
                                              : null,
                                          onTap: () {
                                            setModal(() {
                                              if (!isSelected) {
                                                selectedIds.add(def.id);
                                                selectedRatings[def.id] =
                                                    ratingOptions[1];
                                              }
                                              searchCtrl.clear();
                                              filteredSymptoms = List.from(
                                                _sortedSymptoms,
                                              );
                                            });
                                          },
                                        );
                                      },
                                    ),
                            ),
                          ),
                        ],

                        if (selectedHopeSymptoms.isNotEmpty ||
                            selectedDefs.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(
                            'How much has this affected the patient in the past 2 days?',
                            style: GoogleFonts.nunito(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 10),
                        ],

                        ...hopeSymptoms.where(selectedHopeSymptoms.contains).map((
                          symptom,
                        ) {
                          final current =
                              selectedHopeRatings[symptom] ?? ratingOptions[1];
                          final isFlagged = severityRank(current) >= 2;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.72),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isFlagged
                                      ? Colors.red.shade200
                                      : _borderColor,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (isFlagged)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 4,
                                          ),
                                          child: Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: Colors.orange.shade500,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      Expanded(
                                        child: Text(
                                          symptom,
                                          style: GoogleFonts.nunito(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                            color: isFlagged
                                                ? Colors.red.shade700
                                                : Colors.black,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: ratingOptions.map((severity) {
                                      final isSel = current == severity;
                                      final isSfv = severityRank(severity) >= 2;

                                      return GestureDetector(
                                        onTap: () {
                                          setModal(() {
                                            selectedHopeRatings[symptom] =
                                                severity;
                                            if (isSfv) {
                                              nurseContacted = true;
                                            }
                                          });
                                        },
                                        child: AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 140,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 5,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isSel
                                                ? (isSfv
                                                      ? Colors.red.shade400
                                                      : _purple)
                                                : Colors.white.withOpacity(0.5),
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            border: Border.all(
                                              color: isSel
                                                  ? (isSfv
                                                        ? Colors.red.shade400
                                                        : _purple)
                                                  : _borderColor,
                                              width: isSel ? 1.5 : 1,
                                            ),
                                          ),
                                          child: Text(
                                            severity,
                                            style: GoogleFonts.nunito(
                                              fontSize: 16,
                                              fontWeight: isSel
                                                  ? FontWeight.w700
                                                  : FontWeight.w600,
                                              color: isSel
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                  if (isFlagged)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 10),
                                      child: Text(
                                        'In-Person follow up required.\nNurse will be notified.',
                                        style: GoogleFonts.nunito(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.red.shade700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        }),

                        // Per-symptom severity
                        if (selectedDefs.isNotEmpty) ...[
                          if (selectedHopeSymptoms.isNotEmpty)
                            const SizedBox(height: 12),
                          ...selectedDefs.map((def) {
                            final current =
                                selectedRatings[def.id] ?? ratingOptions[1];
                            final label = def.description != null
                                ? '${def.name}   ${def.description}'
                                : def.name;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.72),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: def.isAlertTrigger
                                        ? Colors.red.shade200
                                        : _borderColor,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (def.isAlertTrigger)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              right: 4,
                                            ),
                                            child: Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                color: Colors.orange.shade500,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        Expanded(
                                          child: Text(
                                            label,
                                            style: GoogleFonts.nunito(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w700,
                                              color: def.isAlertTrigger
                                                  ? Colors.red.shade700
                                                  : Colors.black,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: ratingOptions.map((severity) {
                                        final isSel = current == severity;
                                        final isSfv =
                                            severityRank(severity) >= 2;
                                        return GestureDetector(
                                          onTap: () {
                                            setModal(() {
                                              selectedRatings[def.id] =
                                                  severity;
                                              if (isSfv) nurseContacted = true;
                                            });
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 140,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isSel
                                                  ? (isSfv
                                                        ? Colors.red.shade400
                                                        : _purple)
                                                  : Colors.white.withOpacity(
                                                      0.5,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              border: Border.all(
                                                color: isSel
                                                    ? (isSfv
                                                          ? Colors.red.shade400
                                                          : _purple)
                                                    : _borderColor,
                                                width: isSel ? 1.5 : 1,
                                              ),
                                            ),
                                            child: Text(
                                              severity,
                                              style: GoogleFonts.nunito(
                                                fontSize: 16,
                                                fontWeight: isSel
                                                    ? FontWeight.w700
                                                    : FontWeight.w600,
                                                color: isSel
                                                    ? Colors.white
                                                    : Colors.black,
                                              ),
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    if (_isHopeSymptomName(def.name) &&
                                        severityRank(current) >= 2)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Text(
                                          'In-Person follow up required.\nNurse will be notified.',
                                          style: GoogleFonts.nunito(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.red.shade700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],

                        const SizedBox(height: 20),

                        //  Nurse Alert Banner
                        if (showNurseAlert)
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color.fromARGB(
                                255,
                                236,
                                118,
                                109,
                              ).withOpacity(0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade500,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Moderate or severe symptoms detected. The nurse will be automatically notified.',
                                    style: GoogleFonts.nunito(
                                      fontSize: 16,
                                      color: const Color.fromARGB(255, 0, 0, 0),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        if (showNurseAlert) const SizedBox(height: 12),

                        if (selectedIds.isNotEmpty ||
                            selectedHopeSymptoms.isNotEmpty) ...[
                          GestureDetector(
                            onTap: () => setModal(
                              () => nurseContacted = !nurseContacted,
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: nurseContacted
                                    ? _purple.withOpacity(0.08)
                                    : Colors.white.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: nurseContacted
                                      ? _purple.withOpacity(0.4)
                                      : _borderColor,
                                ),
                              ),
                              child: Row(
                                children: [
                                  AnimatedContainer(
                                    duration: const Duration(milliseconds: 180),
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: nurseContacted
                                          ? _purple
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: nurseContacted
                                            ? _purple
                                            : _borderColor,
                                        width: 2,
                                      ),
                                    ),
                                    child: nurseContacted
                                        ? const Icon(
                                            Icons.check,
                                            size: 18,
                                            color: Colors.white,
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Notify nurse',
                                      style: GoogleFonts.nunito(
                                        fontSize: 18,
                                        color: const Color.fromARGB(
                                          255,
                                          0,
                                          0,
                                          0,
                                        ),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.92),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Additional notes',
                                  style: GoogleFonts.nunito(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: _deepPurple,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextField(
                                  controller: additionalNotesCtrl,
                                  minLines: 3,
                                  maxLines: 5,
                                  keyboardType: TextInputType.multiline,
                                  style: GoogleFonts.nunito(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: _deepPurple,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Optional',
                                    hintStyle: GoogleFonts.nunito(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: _mutedPurple,
                                    ),
                                    border: InputBorder.none,
                                    isDense: true,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                VoiceNoteAttachment(
                                  initialPath: voiceNotePath,
                                  onChanged: (p) =>
                                      setModal(() => voiceNotePath = p),
                                  primaryColor: _purple,
                                  borderColor: _borderColor,
                                  textColor: _deepPurple,
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        //  Submit
                        SizedBox(
                          width: double.infinity,
                          height: 60,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6B5B8E),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(32),
                              ),
                            ),
                            onPressed:
                                (selectedIds.isEmpty &&
                                    selectedHopeSymptoms.isEmpty)
                                ? null
                                : () async {
                                    final member =
                                        SessionManager().currentMember;
                                    final teamId =
                                        SessionManager().currentCareTeam?.id;
                                    if (teamId == null) return;

                                    // Build symptom strings with values and per-symptom notes
                                    final symptoms = <String>[];
                                    for (final id in selectedIds) {
                                      final def = kSymptomById[id];
                                      if (def == null) continue;
                                      final symptomSeverity =
                                          selectedRatings[id] ??
                                          ratingOptions[1];
                                      final parts = <String>[def.name];
                                      parts[0] =
                                          '${def.name}: $symptomSeverity';
                                      symptoms.add(parts.join(' '));
                                    }

                                    for (final symptom
                                        in selectedHopeSymptoms) {
                                      final hopeSeverity =
                                          selectedHopeRatings[symptom] ??
                                          ratingOptions[1];
                                      symptoms.add('$symptom: $hopeSeverity');
                                    }

                                    final hasAlert = selectedIds.any((id) {
                                      final def = kSymptomById[id];
                                      return def != null && def.isAlertTrigger;
                                    });

                                    // Derive severity from worst value
                                    String severity = 'Mild';
                                    final worstRank = [
                                      ...selectedRatings.values.map(
                                        severityRank,
                                      ),
                                      ...selectedHopeRatings.values.map(
                                        severityRank,
                                      ),
                                    ].fold<int>(1, (a, b) => a > b ? a : b);
                                    if (worstRank >= 3) {
                                      severity = 'Severe';
                                    } else if (worstRank >= 2) {
                                      severity = 'Moderate';
                                    }
                                    // Alert symptoms always Severe
                                    if (hasAlert) severity = 'Severe';

                                    final additionalNotes = additionalNotesCtrl
                                        .text
                                        .trim();

                                    final encodedNotes = NoteVoiceCodec.encode(
                                      text: additionalNotes,
                                      audioPath: voiceNotePath,
                                    );

                                    try {
                                      final now = DateTime.now();
                                      final event = SymptomEvent(
                                        id: _uuid.v4(),
                                        careTeamId: teamId,
                                        symptoms: symptoms,
                                        severity: severity,
                                        whatHappened: encodedNotes,
                                        eventTime: now,
                                        createdByMemberId: member?.id,
                                        createdByMemberName: member?.name,
                                        editableUntil: now.add(
                                          const Duration(hours: 1),
                                        ),
                                      );
                                      await _service.logSymptomEvent(event);
                                      final symptomType = symptoms.isEmpty
                                          ? 'Symptom'
                                          : symptoms.first
                                                .split(':')
                                                .first
                                                .trim();
                                      await _calendarService.safeInsertEvent(
                                        {
                                          'id': const Uuid().v4(),
                                          'care_team_id': teamId,
                                          'title': '$symptomType - $severity',
                                          'event_type': 'symptom',
                                          'date': now,
                                          'source': 'symptom',
                                          'related_id': event.id,
                                          'is_auto': true,
                                          'is_overridden': false,
                                        },
                                        operationType: 'insert_symptom_event',
                                      );
                                      debugPrint('Saved event: ${event.id}');
                                    } catch (error) {
                                      debugPrint('[Symptoms][save_event] $error');
                                      if (!ctx.mounted) return;
                                      ScaffoldMessenger.of(ctx).showSnackBar(
                                        SnackBar(
                                          content: Text(error.toString()),
                                        ),
                                      );
                                      return;
                                    }
                                    if (!mounted) return;

                                    if (Navigator.canPop(context)) {
                                      Navigator.of(context).pop();
                                    }

                                    await _loadEvents();
                                  },
                            child: Text(
                              'Log Symptoms',
                              style: GoogleFonts.nunito(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ).whenComplete(() {
      // Don't dispose immediately on pop: the bottom sheet can still rebuild
      // during its dismiss animation, and a TextField will assert if its
      // controller has already been disposed.
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        searchCtrl.dispose();
        additionalNotesCtrl.dispose();
      });
    });
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
              // Ã¢â€â‚¬Ã¢â€â‚¬ Header Ã¢â€â‚¬Ã¢â€â‚¬
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/dashboard');
                        }
                      },
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
                            'Symptoms',
                            style: GoogleFonts.nunito(
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "${SessionManager().currentCareTeam?.patientFirstName ?? 'Your'}'s Care Space",
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: _moduleCard(
                        title: "Symptoms",
                        icon: Icons.monitor_heart_outlined,
                        isActive: true,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _moduleCard(
                        title: "Skin & Wounds",
                        icon: Icons.healing_outlined,
                        isActive: false,
                        onTap: () {
                          context.go('/skin-wounds');
                        },
                      ),
                    ),
                  ],
                ),
              ),

              // Ã¢â€â‚¬Ã¢â€â‚¬ Body Ã¢â€â‚¬Ã¢â€â‚¬
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: _purple),
                      )
                    : _events.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                        itemCount: _events.length,
                        itemBuilder: (_, i) => SymptomEventCard(
                          event: _events[i],
                          onEdit: () => _showEditEventModal(_events[i]),
                          onDelete: () => _confirmDeleteEvent(_events[i]),
                        ),
                      ),
              ),

              const PremiumBottomNav(currentIndex: 0),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: GestureDetector(
          onTap: _showLogSymptomModal,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF6B5B8E),
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: _purple.withOpacity(0.5),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Center(
              child: Icon(Icons.add, color: Colors.white, size: 26),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmDeleteEvent(SymptomEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF0EDF6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Entry?',
          style: GoogleFonts.nunito(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: _deepPurple,
          ),
        ),
        content: Text(
          'This will remove the symptom log from your list, but it will remain in History.',
          style: GoogleFonts.nunito(fontSize: 16, color: Colors.black),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunito(color: Colors.black),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade400,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: GoogleFonts.nunito(color: Colors.white),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _service.archiveSymptomEvent(event.id);
      } catch (_) {
        // Fallback if the backend doesn't have a deleted_at column yet.
        await _hideEventLocally(event.id);
      }
      if (!mounted) return;
      _loadEvents();
    }
  }

  Future<void> _showEditEventModal(SymptomEvent event) async {
    final severityOptions = ['Mild', 'Moderate', 'Severe'];
    String currentSeverity = event.severity ?? 'Mild';

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          height: MediaQuery.of(ctx).size.height * 0.45,
          decoration: const BoxDecoration(
            color: Color(0xFFF0EDF6),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Edit Symptom Entry',
                  style: GoogleFonts.nunito(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _deepPurple,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Severity',
                  style: GoogleFonts.nunito(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: severityOptions.map((opt) {
                    final isSel = currentSeverity == opt;
                    final isSevere = opt == 'Severe';
                    return GestureDetector(
                      onTap: () => setModal(() => currentSeverity = opt),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? (isSevere ? Colors.red.shade400 : _purple)
                              : Colors.white.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSel
                                ? (isSevere ? Colors.red.shade400 : _purple)
                                : _borderColor,
                            width: isSel ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          opt,
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: isSel
                                ? FontWeight.w700
                                : FontWeight.w400,
                            color: isSel ? Colors.white : Colors.black,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                    onPressed: () async {
                      final updated = SymptomEvent(
                        id: event.id,
                        careTeamId: event.careTeamId,
                        symptoms: event.symptoms,
                        severity: currentSeverity,
                        whatHappened: event.whatHappened,
                        eventTime: event.eventTime,
                        createdByMemberId: event.createdByMemberId,
                        createdByMemberName: event.createdByMemberName,
                        editableUntil: event.editableUntil,
                      );
                      await _service.updateSymptomEvent(updated);
                      if (!mounted) return;

                      if (Navigator.canPop(context)) {
                        Navigator.of(context).pop();
                      }

                      await _loadEvents();
                    },
                    child: Text(
                      'Save Changes',
                      style: GoogleFonts.nunito(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
              color: const Color.fromARGB(255, 255, 255, 255).withOpacity(0.4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.monitor_heart_outlined,
              size: 32,
              color: Color.fromARGB(255, 132, 89, 192),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No symptoms logged',
            style: GoogleFonts.nunito(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: const Color.fromARGB(255, 9, 9, 9),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "+" to get started',
            style: GoogleFonts.nunito(
              fontSize: 16,
              color: const Color.fromARGB(255, 5, 5, 5).withOpacity(0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _moduleCard({
    required String title,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? _purple : Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor),
        ),
        child: Column(
          children: [
            Icon(icon, color: isActive ? Colors.white : _deepPurple, size: 20),
            const SizedBox(height: 6),
            Text(
              title,
              style: GoogleFonts.nunito(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isActive ? Colors.white : _deepPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SymptomEventCard extends StatefulWidget {
  final SymptomEvent event;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const SymptomEventCard({
    super.key,
    required this.event,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<SymptomEventCard> createState() => _SymptomEventCardState();
}

class _SymptomEventCardState extends State<SymptomEventCard> {
  bool _expanded = false;

  String _extractSymptomName(String symptom) {
    final colonIndex = symptom.indexOf(':');
    final rawName = colonIndex >= 0
        ? symptom.substring(0, colonIndex)
        : symptom;
    return rawName.trim();
  }

  bool _containsHopeSymptom(String symptom) {
    final name = _extractSymptomName(symptom);
    if (_isHopeSymptomName(name)) return true;

    // Backward compatibility if data is stored without a clean "<Name>: <Severity>" format.
    return kHopeSymptomNames.any((hope) => symptom.contains(hope));
  }

  String? _extractSeverity(String symptom) {
    final colonIndex = symptom.indexOf(':');
    if (colonIndex < 0) return null;
    final rest = symptom.substring(colonIndex + 1).trim();
    if (rest.isEmpty) return null;
    final withoutNote = rest.split('(').first.trim();

    // Current format: "<Symptom>: <Severity>"
    if (withoutNote == 'Not at all' ||
        withoutNote == 'Mild' ||
        withoutNote == 'Moderate' ||
        withoutNote == 'Severe') {
      return withoutNote;
    }

    // Backward compatibility: "<Symptom>: 2 — Moderate" or "2 - Moderate"
    final normalized = withoutNote.replaceAll('—', '-');
    final parts = normalized.split('-').map((s) => s.trim()).toList();
    if (parts.length >= 2 && int.tryParse(parts.first) != null) {
      final label = parts.sublist(1).join(' - ').trim();
      if (label.isNotEmpty) return label;
    }

    return null;
  }

  int _severityRank(String severity) {
    switch (severity) {
      case 'Not at all':
        return 0;
      case 'Mild':
        return 1;
      case 'Moderate':
        return 2;
      case 'Severe':
        return 3;
      default:
        return 1;
    }
  }

  bool _isSfvTriggered(String symptom) {
    if (!_containsHopeSymptom(symptom)) return false;
    final severity = _extractSeverity(symptom);
    if (severity != null) return _severityRank(severity) >= 2;
    return symptom.contains('Moderate') || symptom.contains('Severe');
  }

  bool _isSevere(String symptom) {
    final severity = _extractSeverity(symptom);
    if (severity != null) return _severityRank(severity) >= 3;
    return symptom.contains('Severe');
  }

  String _eventTimeValue() {
    final eventTime = widget.event.eventTime;
    if (eventTime == null) return 'Not yet logged';
    return DateFormat('MMM d, yyyy h:mm a').format(eventTime);
  }

  List<TextSpan> _buildSymptomTitleSpans(List<String> symptoms) {
    final spans = <TextSpan>[];

    for (var i = 0; i < symptoms.length; i++) {
      final symptom = symptoms[i];
      final colonIndex = symptom.indexOf(':');
      final name = colonIndex >= 0 ? symptom.substring(0, colonIndex) : symptom;

      spans.add(
        TextSpan(
          text: name,
          style: GoogleFonts.nunito(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: _deepPurple,
          ),
        ),
      );

      if (i < symptoms.length - 1) {
        spans.add(
          TextSpan(
            text: ', ',
            style: GoogleFonts.nunito(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: _deepPurple,
            ),
          ),
        );
      }
    }

    return spans;
  }

  Widget _infoChip(
    String label, {
    Color? textColor,
    Color? borderColor,
    Color? backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor ?? _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (borderColor ?? _borderColor).withOpacity(0.5),
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.nunito(
          fontSize: 17,
          color: textColor ?? _deepPurple,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final event = widget.event;
    final decodedNotes = NoteVoiceCodec.decode(event.whatHappened);
    final noteText = decodedNotes.text.trim();
    final voicePath = decodedNotes.audioPath;
    final symptoms = event.symptoms ?? const <String>[];
    final title = symptoms.isEmpty ? 'Symptom log' : symptoms.join(', ');
    final hasAlertSymptom = symptoms.any(
      (s) => kAlertSymptomNames.any((sv) => s.contains(sv)),
    );
    final hasHopeSymptom = symptoms.any(_containsHopeSymptom);
    final hasSfv =
        symptoms.any(_isSfvTriggered) ||
        (hasHopeSymptom &&
            (event.severity == 'Moderate' || event.severity == 'Severe'));
    final hasSevere =
        symptoms.any(_isSevere) ||
        event.severity == 'Severe' ||
        hasAlertSymptom;
    final isEditable =
        event.editableUntil != null &&
        DateTime.now().isBefore(event.editableUntil!);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: hasSevere ? Colors.red.shade200 : _borderColor,
        ),
        boxShadow: _expanded
            ? [
                BoxShadow(
                  color: _purple.withOpacity(0.1),
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
                    color: hasSevere
                        ? Colors.red.withOpacity(0.12)
                        : const Color(0xFF8E7CB1).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.monitor_heart_outlined,
                    size: 20,
                    color: hasSevere ? Colors.red.shade600 : _purple,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        text: TextSpan(
                          children: symptoms.isEmpty
                              ? [
                                  TextSpan(
                                    text: title,
                                    style: GoogleFonts.nunito(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w800,
                                      color: _deepPurple,
                                    ),
                                  ),
                                ]
                              : _buildSymptomTitleSpans(symptoms),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Symptom logged',
                        style: GoogleFonts.nunito(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: Colors.black,
                        ),
                      ),
                      Text(
                        _eventTimeValue(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 16,
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
                      color: _lightPurple.withOpacity(0.7),
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
            if (!_expanded && hasSfv) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _infoChip(
                    'In-Person Follow Up Required',
                    textColor: Colors.white,
                    borderColor: Colors.red.shade400,
                    backgroundColor: Colors.red.shade400,
                  ),
                ],
              ),
            ],
            if (_expanded) ...[
              const SizedBox(height: 16),
              const Divider(color: _borderColor),
              const SizedBox(height: 16),
              if (symptoms.isNotEmpty || hasSfv) ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    ...symptoms.map((symptom) {
                      final isAlertSymptom = kAlertSymptomNames.any(
                        (sv) => symptom.contains(sv),
                      );
                      final isSfvSymptom = _isSfvTriggered(symptom);
                      return _infoChip(
                        symptom,
                        textColor: _deepPurple,
                        borderColor: isSfvSymptom || isAlertSymptom
                            ? Colors.red.shade300
                            : _borderColor,
                      );
                    }),
                    if (hasSfv)
                      _infoChip(
                        'In-Person Follow Up Required',
                        textColor: Colors.white,
                        borderColor: Colors.red.shade400,
                        backgroundColor: Colors.red.shade400,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              if (noteText.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Text(
                    noteText,
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      color: Colors.black,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (voicePath != null && voicePath.trim().isNotEmpty) ...[
                VoiceNotePlaybackButton(
                  path: voicePath,
                  borderColor: _borderColor,
                  textColor: _deepPurple,
                ),
                const SizedBox(height: 12),
              ],
              Text(
                'Logged by ${event.createdByMemberName ?? 'Unknown'}',
                style: GoogleFonts.nunito(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _lightPurple,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: _borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => context.push('/symptom-history'),
                      child: Text(
                        'History',
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _deepPurple,
                        ),
                      ),
                    ),
                  ),
                  if (isEditable) ...[
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
                        onPressed: widget.onEdit,
                        child: Text(
                          'Edit',
                          style: GoogleFonts.nunito(
                            fontSize: 16,
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
                          side: BorderSide(color: Colors.red.shade200),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: widget.onDelete,
                        child: Text(
                          'Delete',
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ),
                  ] else ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.16),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: Colors.grey.shade600,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Locked',
                              style: GoogleFonts.nunito(
                                fontSize: 16,
                                color: Colors.grey.shade700,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
