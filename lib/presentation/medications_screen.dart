import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

import '../core/session_manager.dart';
import '../core/medication_image_extractor.dart';
import '../core/note_voice_codec.dart';
import '../core/supabase_service.dart';
import '../domain/models.dart';
import '../domain/medication_data.dart';
import 'premium_bottom_nav.dart';
import 'widgets/animated_border_field.dart';
import 'widgets/voice_note_attachment.dart';
import 'history_screen.dart';
import 'calendar_service.dart';

// ─── Colors ───────────────────────────────────────────────────────────────────
const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _mutedPurple = Color(0xFF6C648B);
const _borderColor = Color(0xFFD4CDDF);
const _cardBg = Color(0xFFF0EDF6);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

String _normalizeMedicationUnit(String unit) {
  final u = unit.trim();
  if (u.isEmpty) return u;
  final lower = u.toLowerCase();
  if (lower.startsWith('ml')) return 'mL';
  if (lower.startsWith('mcg')) return 'mcg';
  if (lower.startsWith('mg')) return 'mg';
  if (RegExp(r'^g\b').hasMatch(lower)) return 'g';
  if (lower == 'iu' || lower == 'i.u.' || lower == 'units') return 'units';
  return u;
}

String _medicationKeyLower({
  required String name,
  required String? strengthAmount,
  required String? strengthUnit,
}) {
  final n = name.trim().toLowerCase();
  final a = (strengthAmount ?? '').trim().toLowerCase();
  final u = _normalizeMedicationUnit((strengthUnit ?? '')).trim().toLowerCase();
  return '$n|$a|$u';
}

class MedicationsScreen extends StatefulWidget {
  const MedicationsScreen({super.key});

  @override
  State<MedicationsScreen> createState() => _MedicationsScreenState();
}

class _MedicationsScreenState extends State<MedicationsScreen>
    with SingleTickerProviderStateMixin {
  final _service = SupabaseService();
  final _calendarService = CalendarService();
  final _uuid = const Uuid();
  final _imagePicker = ImagePicker();
  List<Medication> _medications = [];
  Map<String, DateTime> _lastAdministeredByMedicationId = {};
  bool _isLoading = true;
  String? _careTeamId;

  static const String _backendBaseUrl = String.fromEnvironment(
    'BACKEND_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  // Optional: only used when provided at build time.
  // If empty, the app will use the backend extraction endpoint instead.
  static const String _geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  void _safePopTopRoute() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      Navigator.of(context).pop();
    }
  }

  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _loadMedications();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  ThemeData _pickerTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      colorScheme: const ColorScheme.light(
        primary: _purple,
        onPrimary: Colors.white,
        surface: _cardBg,
        onSurface: _deepPurple,
      ),
      dialogBackgroundColor: _cardBg,
      timePickerTheme: TimePickerThemeData(
        backgroundColor: _cardBg,
        hourMinuteColor: _purple.withOpacity(0.12),
        hourMinuteTextColor: _deepPurple,
        dayPeriodColor: _purple.withOpacity(0.12),
        dayPeriodTextColor: _deepPurple,
        dialBackgroundColor: _purple.withOpacity(0.08),
        dialHandColor: _purple,
        dialTextColor: _deepPurple,
        entryModeIconColor: _purple,
        helpTextStyle: GoogleFonts.nunito(
          color: _mutedPurple,
          fontWeight: FontWeight.w700,
        ),
        hourMinuteTextStyle: GoogleFonts.nunito(
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: _deepPurple,
        ),
        dayPeriodTextStyle: GoogleFonts.nunito(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: _purple,
          textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Future<void> _loadMedications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final careTeamId = SessionManager().currentCareTeam?.id;
      if (careTeamId == null) return;
      _careTeamId = careTeamId;
      final results = await Future.wait([
        _service.getMedications(careTeamId),
        _service.getDoseLogs(careTeamId),
      ]);
      final response = results[0] as List<Medication>;
      final doseLogs = results[1] as List<DoseLog>;
      final lastAdministeredByMedicationId = <String, DateTime>{};

      for (final log in doseLogs) {
        final medicationId = log.medicationId;
        final doseTime = log.doseTime;
        if (medicationId == null || doseTime == null) continue;
        lastAdministeredByMedicationId.putIfAbsent(
          medicationId,
          () => doseTime,
        );
      }

      if (!mounted) return;
      setState(() {
        _medications = response;
        _lastAdministeredByMedicationId = lastAdministeredByMedicationId;
      });
      _animCtrl.forward(from: 0);
    } catch (e) {
      debugPrint('Error loading medications: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String? _calendarFrequencyForMedication(String? pattern) {
    final normalized = (pattern ?? '').trim().toLowerCase();
    switch (normalized) {
      case 'once daily':
        return 'daily';
      case 'twice daily':
        return 'twice_daily';
      case 'every 7 days':
        return 'weekly';
      default:
        return null;
    }
  }

  Future<void> _saveMedicationWithSchedule(
    Medication medication, {
    required DateTime? medicationStart,
    bool addToCalendar = true,
    String? calendarFrequencyOverride,
  }) async {
    final generatedFrequency =
        calendarFrequencyOverride ??
        _calendarFrequencyForMedication(medication.pattern);
    final safeStart = medicationStart ?? DateTime.now();

    try {
      await _service.addMedication(medication);

      if (addToCalendar && _careTeamId != null && generatedFrequency != null) {
        await _calendarService.generateMedicationEvents(
          careTeamId: _careTeamId!,
          medicationId: medication.id,
          name: medication.name ?? 'Medication',
          start: safeStart,
          frequency: generatedFrequency,
        );
      }

      if (!mounted) return;
      _safePopTopRoute();
      await _loadMedications();
    } on CalendarOperationException catch (error) {
      debugPrint(
        '[Medications][save_with_schedule] ${error.operationType}: $error',
      );
      try {
        await _service.deleteMedication(medication.id);
      } catch (rollbackError) {
        debugPrint('[Medications][rollback_add] $rollbackError');
      }

      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.userMessage),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          action: error.retryable
              ? SnackBarAction(
                  label: 'Retry',
                  textColor: Colors.white,
                  onPressed: () {
                    _saveMedicationWithSchedule(
                      medication,
                      medicationStart: medicationStart,
                      calendarFrequencyOverride: calendarFrequencyOverride,
                    );
                  },
                )
              : null,
        ),
      );
    } catch (error) {
      debugPrint('[Medications][save_with_schedule] $error');
      try {
        await _service.deleteMedication(medication.id);
      } catch (rollbackError) {
        debugPrint('[Medications][rollback_add] $rollbackError');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Something went wrong. Please try again later'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  // ---------- Just Administered (Log Medication Given) ----------
  Future<void> _showAdministerDialog(Medication med) async {
    DateTime selectedTime = DateTime.now();
    final member = SessionManager().currentMember;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final dateStr = DateFormat('MMM d, yyyy').format(selectedTime);
            final timeStr = DateFormat('h:mm a').format(selectedTime);
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _borderColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Log Administration',
                    style: GoogleFonts.nunito(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: _deepPurple,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    med.name ?? '',
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _deepPurple,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Timestamp row — tappable to edit
                  GestureDetector(
                    onTap: () async {
                      final pickedDate = await showDatePicker(
                        context: ctx,
                        initialDate: selectedTime,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                        builder: (context, child) =>
                            Theme(data: _pickerTheme(context), child: child!),
                      );
                      if (pickedDate == null) return;
                      if (!ctx.mounted) return;
                      final pickedTime = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(selectedTime),
                        builder: (context, child) =>
                            Theme(data: _pickerTheme(context), child: child!),
                      );
                      if (pickedTime == null) return;
                      if (!ctx.mounted) return;
                      setModalState(() {
                        selectedTime = DateTime(
                          pickedDate.year,
                          pickedDate.month,
                          pickedDate.day,
                          pickedTime.hour,
                          pickedTime.minute,
                        );
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _purple.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _purple.withOpacity(0.20)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 20,
                            color: _purple,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$dateStr  ·  $timeStr',
                              style: GoogleFonts.nunito(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _deepPurple,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.edit_outlined,
                            size: 18,
                            color: _mutedPurple,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Tap to change date/time',
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        color: _mutedPurple,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () async {
                        final log = DoseLog(
                          id: _uuid.v4(),
                          careTeamId: _careTeamId,
                          medicationId: med.id,
                          medicationName: med.name,
                          doseTime: selectedTime,
                          amountGiven: med.typicalDose,
                          whoGave: member?.name,
                          loggedByMemberId: member?.id,
                          loggedByMemberName: member?.name,
                        );
                        try {
                          await _service.logDose(log);
                          if (!ctx.mounted) return;
                          await _loadMedications();
                          if (!mounted) return;
                          _safePopTopRoute();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Dose logged for ${med.name}',
                                style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              backgroundColor: _purple,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        } catch (e) {
                          debugPrint('Error logging dose: $e');
                          if (!mounted) return;
                          _safePopTopRoute();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed to log dose: $e',
                                style: GoogleFonts.nunito(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              backgroundColor: Colors.red.shade700,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          );
                        }
                      },
                      child: Text(
                        'Confirm Administration',
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ---------- Deprescribe ----------
  Future<void> _showDeprescribeDialog(Medication med) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Deprescribe Medication',
          style: GoogleFonts.nunito(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: _deepPurple,
          ),
        ),
        content: Text(
          'This will deprescribe "${med.name}" and preserve its history. You can add a new entry to replace it.',
          style: GoogleFonts.nunito(
            fontSize: 16,
            color: _deepPurple,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunito(
                fontSize: 16,
                color: _deepPurple,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _purple,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Remove',
              style: GoogleFonts.nunito(
                fontSize: 16,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _calendarService.deleteFutureMedicationEvents(med.id);
        final updated = Medication(
          id: med.id,
          careTeamId: med.careTeamId,
          name: med.name,
          strength: med.strength,
          typicalDose: med.typicalDose,
          route: med.route,
          pattern: 'inactive',
          scheduleDetails: med.scheduleDetails,
          createdAt: med.createdAt,
          createdByMemberId: med.createdByMemberId,
          deprescribedAt: DateTime.now(),
        );
        await _service.updateMedication(updated);
        _loadMedications();
      } catch (e) {
        debugPrint('Error deactivating medication: $e');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to deactivate: $e',
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    }
  }

  Future<bool> _confirmMedicationDetails({
    required String patientName,
    required Medication medication,
  }) async {
    final decodedNotes = NoteVoiceCodec.decode(medication.notes);
    final noteText = decodedNotes.text.trim();
    final voicePath = decodedNotes.audioPath;

    final details = <MapEntry<String, String>>[
      MapEntry('Medication name', medication.name ?? 'Unknown'),
      if ((medication.strength ?? '').isNotEmpty)
        MapEntry('Dosage', medication.strength!),
      if ((medication.typicalDose ?? '').isNotEmpty)
        MapEntry('Unit', medication.typicalDose!),
      if ((medication.route ?? '').isNotEmpty)
        MapEntry('Route', medication.route!),
      if ((medication.pattern ?? '').isNotEmpty)
        MapEntry('Frequency', medication.pattern!),
      if ((medication.scheduleDetails ?? '').isNotEmpty)
        MapEntry('Prescribed Date', medication.scheduleDetails!),
      if (noteText.isNotEmpty) MapEntry('Notes', noteText),
    ];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
        contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        title: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _purple.withOpacity(0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _purple.withOpacity(0.25)),
              ),
              child: const Icon(
                Icons.medication_outlined,
                color: _purple,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Confirm medication',
                    style: GoogleFonts.nunito(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _deepPurple,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'For $patientName',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _mutedPurple,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.75),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _borderColor),
                ),
                child: Text(
                  'Review these details before saving.',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _deepPurple,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              ...details.map(
                (entry) => Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 4,
                        child: Text(
                          entry.key,
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _mutedPurple,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 6,
                        child: Text(
                          entry.value,
                          textAlign: TextAlign.right,
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _deepPurple,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (voicePath != null && voicePath.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                VoiceNotePlaybackButton(
                  path: voicePath,
                  borderColor: _borderColor,
                  textColor: _deepPurple,
                ),
              ],
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _borderColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    'Edit',
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _deepPurple,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(
                    'Confirm',
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  void _showAddMedicationEntrySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFEDE8F5), Color(0xFFDAD4E6)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _borderColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Add medication',
                    style: GoogleFonts.nunito(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _deepPurple,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: _chooserPillButton(
                        label: 'Camera',
                        icon: Icons.photo_camera_outlined,
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          _pickMedicationImage(ImageSource.camera);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _chooserPillButton(
                        label: 'Photos',
                        icon: Icons.photo_library_outlined,
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          _pickMedicationImage(ImageSource.gallery);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6B5B8E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(sheetCtx).pop();
                      _showAddMedicationModal();
                    },
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    label: Text(
                      'Add manually',
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chooserPillButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFBEB8C7).withOpacity(0.55),
          foregroundColor: _deepPurple,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: GoogleFonts.nunito(fontSize: 14, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  String _patientNameForDialog() {
    final candidate = (SessionManager().currentCareTeam?.patientFirstName ?? '')
        .trim();
    return candidate.isEmpty ? 'Patient' : candidate;
  }

  String? _scheduleDetailsFromPrescribedDate(DateTime? date) {
    if (date == null) return null;
    try {
      return 'Prescribed: ${DateFormat('MMM d, yyyy').format(date)}';
    } catch (_) {
      return null;
    }
  }

  Medication? _medicationFromExtraction(MedicationImageExtraction extraction) {
    final name = (extraction.name ?? '').trim();
    if (name.isEmpty) return null;

    final strengthAmount = (extraction.dosageAmount ?? '').trim();
    final strengthUnit = _normalizeMedicationUnit(
      (extraction.dosageUnit ?? '').trim(),
    );

    final isPrn = extraction.isPrn == true;
    final frequency = (extraction.frequency ?? '').trim();

    final scheduleDetails = _scheduleDetailsFromPrescribedDate(
      extraction.prescribedDate,
    );

    final notes = NoteVoiceCodec.encode(
      text: (extraction.instructions ?? '').trim(),
      audioPath: null,
    );

    return Medication(
      id: _uuid.v4(),
      careTeamId: SessionManager().currentCareTeam?.id,
      name: name,
      strength: strengthAmount.isEmpty ? null : strengthAmount,
      typicalDose: strengthUnit.isEmpty ? null : strengthUnit,
      route: (extraction.route ?? '').trim().isEmpty ? null : extraction.route,
      pattern: isPrn ? 'As needed' : (frequency.isEmpty ? null : frequency),
      scheduleDetails: scheduleDetails,
      notes: notes,
      createdAt: DateTime.now(),
      createdByMemberId: SessionManager().currentMember?.id,
    );
  }

  bool _isDuplicateActiveMedication(Medication medication) {
    final name = (medication.name ?? '').trim();
    if (name.isEmpty) return false;

    final candidateKey = _medicationKeyLower(
      name: name,
      strengthAmount: medication.strength,
      strengthUnit: medication.typicalDose,
    );

    final existingKeys = _medications
        .where((m) => m.pattern != 'inactive')
        .map(
          (m) => _medicationKeyLower(
            name: m.name ?? '',
            strengthAmount: m.strength,
            strengthUnit: m.typicalDose,
          ),
        )
        .where((s) => s.split('|').first.trim().isNotEmpty)
        .toSet();

    return existingKeys.contains(candidateKey);
  }

  Future<MedicationImageExtraction> _extractMedicationViaBackend({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final uri = Uri.parse('$_backendBaseUrl/api/medications/extract');

    final boundary = '----epilogue_${DateTime.now().microsecondsSinceEpoch}';
    final header = <int>[];
    header.addAll(utf8.encode('--$boundary\r\n'));
    header.addAll(
      utf8.encode(
        'Content-Disposition: form-data; name="image"; filename="upload"\r\n',
      ),
    );
    header.addAll(utf8.encode('Content-Type: $mimeType\r\n\r\n'));

    final footer = utf8.encode('\r\n--$boundary--\r\n');

    final body = BytesBuilder(copy: false)
      ..add(header)
      ..add(imageBytes)
      ..add(footer);

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);

    try {
      final request = await client.postUrl(uri);
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        'multipart/form-data; boundary=$boundary',
      );
      request.add(body.takeBytes());

      final response = await request.close();
      final responseText = await response.transform(utf8.decoder).join();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Backend extraction failed (${response.statusCode}): $responseText',
        );
      }

      final decoded = jsonDecode(responseText);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid backend response');
      }

      return MedicationImageExtraction.fromJson(decoded);
    } finally {
      client.close(force: true);
    }
  }

  Future<MedicationImageExtraction> _extractMedicationViaGeminiSdk({
    required Uint8List imageBytes,
    required String mimeType,
  }) async {
    final extractor = GeminiMedicationImageExtractor(apiKey: _geminiApiKey);
    return extractor.extract(imageBytes: imageBytes, mimeType: mimeType);
  }

  Future<void> _pickMedicationImage(ImageSource source) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        imageQuality: 85,
      );
      if (file == null) return;

      if (!mounted) return;
      _showProcessingDialog();

      final bytes = await file.readAsBytes();
      final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';

      final imageBytes = Uint8List.fromList(bytes);
      final hasGeminiKey = _geminiApiKey.trim().isNotEmpty;

      MedicationImageExtraction extraction;
      if (hasGeminiKey) {
        try {
          extraction = await _extractMedicationViaGeminiSdk(
            imageBytes: imageBytes,
            mimeType: mimeType,
          );
        } catch (e) {
          debugPrint('[Medications][image_extract][sdk_failed] $e');
          extraction = await _extractMedicationViaBackend(
            imageBytes: imageBytes,
            mimeType: mimeType,
          );
        }
      } else {
        extraction = await _extractMedicationViaBackend(
          imageBytes: imageBytes,
          mimeType: mimeType,
        );
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final medication = _medicationFromExtraction(extraction);
      if (medication == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not read a medication name. Please edit and save manually.',
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        _showAddMedicationModal(prefill: extraction);
        return;
      }

      if (_isDuplicateActiveMedication(medication)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'This medication is already added.',
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
        _showAddMedicationModal(prefill: extraction);
        return;
      }

      final confirmed = await _confirmMedicationDetails(
        patientName: _patientNameForDialog(),
        medication: medication,
      );

      if (!confirmed) {
        _showAddMedicationModal(prefill: extraction);
        return;
      }

      final isPrn =
          (medication.pattern ?? '').trim().toLowerCase() == 'as needed';

      await _saveMedicationWithSchedule(
        medication,
        medicationStart: extraction.prescribedDate,
        addToCalendar: !isPrn,
      );
    } catch (e) {
      debugPrint('[Medications][image_extract] $e');
      if (!mounted) return;
      await Navigator.of(context, rootNavigator: true).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not read medication details from this image.',
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
    }
  }

  void _showProcessingDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          backgroundColor: _cardBg,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(color: _purple),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Reading medication details…',
                    style: GoogleFonts.nunito(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _deepPurple,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- Add Medication Modal ----------
  void _showAddMedicationModal({MedicationImageExtraction? prefill}) {
    final nameCtrl = TextEditingController();
    final scheduleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    String? voiceNotePath;
    String? notesPhotoPath;
    bool notesExpanded = false;
    // Only block duplicates for ACTIVE meds.
    // If a medication is deprescribed (pattern == 'inactive'), it can be added again.
    final existingMedicationKeysLower = _medications
        .where((m) => m.pattern != 'inactive')
        .map(
          (m) => _medicationKeyLower(
            name: m.name ?? '',
            strengthAmount: m.strength,
            strengthUnit: m.typicalDose,
          ),
        )
        .where((s) => s.split('|').first.trim().isNotEmpty)
        .toSet();
    List<String> routeOptions = [
      'By mouth',
      'Sublingual',
      'Topical',
      'Injection',
      'Suppository',
      'Inhaled',
      'Other',
    ];
    String route = 'By mouth';
    String? selectedStrengthAmount;
    String? selectedStrengthUnit;

    // As needed is mutually exclusive
    bool isPrn = false;

    bool addToCalendar = true;

    String? selectedFreqType = 'hour'; // 'hour', 'daily', 'day'
    int hoursValue = 4;
    int daysValue = 2;
    String dailyFrequency = 'Once daily';
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    DateTime prescribedDate = todayDate;
    TimeOfDay startTime = const TimeOfDay(hour: 9, minute: 0);

    // Daily dose times
    TimeOfDay doseTime1 = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay doseTime2 = const TimeOfDay(hour: 21, minute: 0);
    TimeOfDay doseTime3 = const TimeOfDay(hour: 15, minute: 0);

    if (prefill != null) {
      if ((prefill.name ?? '').trim().isNotEmpty) {
        nameCtrl.text = prefill.name!.trim();

        final matches = searchMedications(nameCtrl.text);
        if (matches.isNotEmpty) {
          final best = matches.first;
          routeOptions = best.routeOptions;
          route = routeOptions.first;
        }
      }

      if ((prefill.dosageAmount ?? '').trim().isNotEmpty) {
        selectedStrengthAmount = prefill.dosageAmount!.trim();
      }
      if ((prefill.instructions ?? '').trim().isNotEmpty) {
        notesCtrl.text = prefill.instructions!.trim();
      }

      if ((prefill.route ?? '').trim().isNotEmpty) {
        final candidate = prefill.route!.trim();
        if (routeOptions.contains(candidate)) {
          route = candidate;
        }
      }
      if ((prefill.dosageUnit ?? '').trim().isNotEmpty) {
        selectedStrengthUnit = _normalizeMedicationUnit(prefill.dosageUnit!);
      }

      if (prefill.isPrn == true) {
        isPrn = true;
      }
      if (prefill.prescribedDate != null) {
        final d = prefill.prescribedDate!;
        final normalized = DateTime(d.year, d.month, d.day);
        prescribedDate = normalized;
      }
      if ((prefill.frequency ?? '').trim().isNotEmpty) {
        final f = prefill.frequency!.trim().toLowerCase();
        if (f.contains('as needed') || f.contains('prn')) {
          isPrn = true;
        } else {
          // Common “every N hours” patterns.
          final hoursMatch = RegExp(
            r'(?:every\s+)?(\d{1,2})\s*(?:h|hr|hrs|hour|hours)\b',
          ).firstMatch(f);
          final qHoursMatch = RegExp(r'\bq(\d{1,2})h\b').firstMatch(f);
          final parsedHours = int.tryParse(
            (hoursMatch?.group(1) ?? qHoursMatch?.group(1) ?? '').trim(),
          );

          // Common “every N days” patterns.
          final daysMatch = RegExp(
            r'(?:every\s+)?(\d{1,2})\s*(?:d|day|days)\b',
          ).firstMatch(f);
          final qDaysMatch = RegExp(r'\bq(\d{1,2})d\b').firstMatch(f);
          final parsedDays = int.tryParse(
            (daysMatch?.group(1) ?? qDaysMatch?.group(1) ?? '').trim(),
          );

          // Times per day.
          final timesMatch = RegExp(
            r'\b(\d)\s*(?:x|times)\s*(?:a\s*)?day\b',
          ).firstMatch(f);
          final parsedTimesPerDay = int.tryParse(
            (timesMatch?.group(1) ?? '').trim(),
          );

          if (parsedHours != null && parsedHours > 0) {
            selectedFreqType = 'hour';
            hoursValue = parsedHours.clamp(1, 24);
          } else if (parsedDays != null && parsedDays > 0) {
            selectedFreqType = 'day';
            daysValue = parsedDays.clamp(1, 30);
          } else if (f.contains('once daily') || f == 'daily' || f == 'once') {
            selectedFreqType = 'daily';
            dailyFrequency = 'Once daily';
          } else if (f.contains('twice daily') || f.contains('two times')) {
            selectedFreqType = 'daily';
            dailyFrequency = 'Twice daily';
          } else if (f.contains('thrice daily') || f.contains('three times')) {
            selectedFreqType = 'daily';
            dailyFrequency = 'Thrice daily';
          } else if (parsedTimesPerDay == 1) {
            selectedFreqType = 'daily';
            dailyFrequency = 'Once daily';
          } else if (parsedTimesPerDay == 2) {
            selectedFreqType = 'daily';
            dailyFrequency = 'Twice daily';
          } else if (parsedTimesPerDay == 3) {
            selectedFreqType = 'daily';
            dailyFrequency = 'Thrice daily';
          }
        }
      }
    }

    String getFreqPattern() {
      if (isPrn) return 'As needed';
      switch (selectedFreqType) {
        case 'hour':
          return 'Every $hoursValue hours';
        case 'daily':
          return dailyFrequency;
        case 'day':
          return 'Every $daysValue days';
        default:
          return 'Not set';
      }
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (ctx, setModal) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFEDE8F5), Color(0xFFDAD4E6)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                  left: 24,
                  right: 24,
                  top: 16,
                ),
                child: SingleChildScrollView(
                  controller: scrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _borderColor,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Text(
                        'Add medication',
                        style: GoogleFonts.nunito(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: _deepPurple,
                        ),
                      ),
                      const SizedBox(height: 24),

                      _modalLabel('Medication name'),
                      _MedicationAutocomplete(
                        controller: nameCtrl,
                        existingMedicationKeysLower:
                            existingMedicationKeysLower,
                        onSelected: (suggestion) {
                          nameCtrl.text = suggestion.name;
                          selectedStrengthAmount =
                              (suggestion.strengthAmount ?? '').trim().isEmpty
                              ? null
                              : suggestion.strengthAmount!.trim();
                          final unitRaw = (suggestion.strengthUnit ?? '')
                              .trim();
                          selectedStrengthUnit = unitRaw.isEmpty
                              ? null
                              : _normalizeMedicationUnit(unitRaw);

                          final matched = searchMedications(suggestion.name);
                          if (matched.isNotEmpty) {
                            final med = matched.first;
                            setModal(() {
                              routeOptions = med.routeOptions;
                              route = routeOptions.first;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      const SizedBox(height: 8),

                      // As Needed Toggle
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isPrn ? _purple : _borderColor,
                          ),
                        ),
                        child: SwitchListTile(
                          title: Text(
                            'As needed (PRN)',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _deepPurple,
                            ),
                          ),
                          subtitle: Text(
                            'No schedule: give only when needed',
                            style: GoogleFonts.nunito(
                              fontSize: 15,
                              color: _mutedPurple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          value: isPrn,
                          activeColor: _purple,
                          onChanged: (val) => setModal(() => isPrn = val),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Add to calendar toggle
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: addToCalendar ? _purple : _borderColor,
                          ),
                        ),
                        child: SwitchListTile(
                          title: Text(
                            'Add to calendar',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: _deepPurple,
                            ),
                          ),
                          subtitle: Text(
                            'Create scheduled reminders for this medication',
                            style: GoogleFonts.nunito(
                              fontSize: 15,
                              color: _mutedPurple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          value: addToCalendar,
                          activeColor: _purple,
                          onChanged: (val) =>
                              setModal(() => addToCalendar = val),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Frequency Fields - Grayed out if As needed
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _modalLabel('Frequency'),
                          const SizedBox(height: 8),
                          Opacity(
                            opacity: isPrn ? 0.35 : 1.0,
                            child: IgnorePointer(
                              ignoring: isPrn,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _buildFrequencyOption(
                                          title: 'Every few hours',
                                          isSelected:
                                              selectedFreqType == 'hour',
                                          onTap: () => setModal(
                                            () => selectedFreqType = 'hour',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _buildFrequencyOption(
                                          title: 'Same day',
                                          isSelected:
                                              selectedFreqType == 'daily',
                                          onTap: () => setModal(
                                            () => selectedFreqType = 'daily',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: _buildFrequencyOption(
                                          title: 'Every few days',
                                          isSelected: selectedFreqType == 'day',
                                          onTap: () => setModal(
                                            () => selectedFreqType = 'day',
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),

                                  const SizedBox(height: 16),
                                  if (selectedFreqType == 'hour') ...[
                                    _buildFriendlyStepper(
                                      label: 'hours',
                                      value: hoursValue,
                                      onDecrement: () {
                                        if (hoursValue > 1)
                                          setModal(() => hoursValue--);
                                      },
                                      onIncrement: () =>
                                          setModal(() => hoursValue++),
                                    ),
                                  ],
                                  if (selectedFreqType == 'daily') ...[
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.8),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: _borderColor),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Give this medicine',
                                            style: GoogleFonts.nunito(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                              color: _deepPurple,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: _borderColor,
                                              ),
                                            ),
                                            child: DropdownButtonHideUnderline(
                                              child: DropdownButton<String>(
                                                value: dailyFrequency,
                                                isExpanded: true,
                                                icon: const Icon(
                                                  Icons.keyboard_arrow_down,
                                                  color: _deepPurple,
                                                ),
                                                style: GoogleFonts.nunito(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w700,
                                                  color: _deepPurple,
                                                ),
                                                items: const [
                                                  DropdownMenuItem(
                                                    value: 'Once daily',
                                                    child: Text('Once daily'),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'Twice daily',
                                                    child: Text('Twice daily'),
                                                  ),
                                                  DropdownMenuItem(
                                                    value: 'Three times daily',
                                                    child: Text(
                                                      'Three times daily',
                                                    ),
                                                  ),
                                                ],
                                                onChanged: (value) {
                                                  if (value == null) return;
                                                  setModal(
                                                    () =>
                                                        dailyFrequency = value,
                                                  );
                                                },
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 14),
                                          Text(
                                            'Dose time',
                                            style: GoogleFonts.nunito(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: _deepPurple,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          GestureDetector(
                                            onTap: () async {
                                              final picked =
                                                  await showTimePicker(
                                                    context: ctx,
                                                    initialTime: doseTime1,
                                                    builder: (context, child) =>
                                                        Theme(
                                                          data: _pickerTheme(
                                                            context,
                                                          ),
                                                          child: child!,
                                                        ),
                                                  );
                                              if (picked == null) return;
                                              setModal(
                                                () => doseTime1 = picked,
                                              );
                                            },
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 15,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(
                                                  0.75,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: _borderColor,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                    Icons.access_time,
                                                    size: 20,
                                                    color: _deepPurple,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    doseTime1.format(ctx),
                                                    style: GoogleFonts.nunito(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: _deepPurple,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (dailyFrequency == 'Twice daily' ||
                                              dailyFrequency ==
                                                  'Thrice daily') ...[
                                            const SizedBox(height: 10),
                                            GestureDetector(
                                              onTap: () async {
                                                final picked =
                                                    await showTimePicker(
                                                      context: ctx,
                                                      initialTime: doseTime2,
                                                      builder:
                                                          (
                                                            context,
                                                            child,
                                                          ) => Theme(
                                                            data: _pickerTheme(
                                                              context,
                                                            ),
                                                            child: child!,
                                                          ),
                                                    );
                                                if (picked == null) return;
                                                setModal(
                                                  () => doseTime2 = picked,
                                                );
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 15,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.75),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  border: Border.all(
                                                    color: _borderColor,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.access_time,
                                                      size: 20,
                                                      color: _deepPurple,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      doseTime2.format(ctx),
                                                      style: GoogleFonts.nunito(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: _deepPurple,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                          if (dailyFrequency ==
                                              'Thrice daily') ...[
                                            const SizedBox(height: 10),
                                            GestureDetector(
                                              onTap: () async {
                                                final picked =
                                                    await showTimePicker(
                                                      context: ctx,
                                                      initialTime: doseTime3,
                                                      builder:
                                                          (
                                                            context,
                                                            child,
                                                          ) => Theme(
                                                            data: _pickerTheme(
                                                              context,
                                                            ),
                                                            child: child!,
                                                          ),
                                                    );
                                                if (picked == null) return;
                                                setModal(
                                                  () => doseTime3 = picked,
                                                );
                                              },
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 16,
                                                      vertical: 15,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white
                                                      .withOpacity(0.75),
                                                  borderRadius:
                                                      BorderRadius.circular(14),
                                                  border: Border.all(
                                                    color: _borderColor,
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.access_time,
                                                      size: 20,
                                                      color: _deepPurple,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      doseTime3.format(ctx),
                                                      style: GoogleFonts.nunito(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: _deepPurple,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                  if (selectedFreqType == 'day') ...[
                                    _buildFriendlyStepper(
                                      label: 'days',
                                      value: daysValue,
                                      onDecrement: () {
                                        if (daysValue > 1)
                                          setModal(() => daysValue--);
                                      },
                                      onIncrement: () =>
                                          setModal(() => daysValue++),
                                    ),
                                  ],

                                  if (selectedFreqType != 'daily') ...[
                                    const SizedBox(height: 12),
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withOpacity(0.75),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: _borderColor),
                                      ),
                                      child: InkWell(
                                        onTap: () async {
                                          final firstDate = DateTime(1900);
                                          final lastDate = todayDate.add(
                                            const Duration(days: 3650),
                                          );
                                          final pickedDate =
                                              await showDatePicker(
                                                context: ctx,
                                                initialDate: prescribedDate,
                                                firstDate: firstDate,
                                                lastDate: lastDate,
                                                builder: (context, child) =>
                                                    Theme(
                                                      data: _pickerTheme(
                                                        context,
                                                      ),
                                                      child: child!,
                                                    ),
                                              );
                                          if (pickedDate == null) return;

                                          setModal(
                                            () => prescribedDate = DateTime(
                                              pickedDate.year,
                                              pickedDate.month,
                                              pickedDate.day,
                                            ),
                                          );

                                          if (!ctx.mounted) return;
                                          final pickedTime =
                                              await showTimePicker(
                                                context: ctx,
                                                initialTime: startTime,
                                                builder: (context, child) =>
                                                    Theme(
                                                      data: _pickerTheme(
                                                        context,
                                                      ),
                                                      child: child!,
                                                    ),
                                              );
                                          if (pickedTime == null) return;
                                          setModal(
                                            () => startTime = pickedTime,
                                          );
                                        },
                                        child: Row(
                                          children: [
                                            const Icon(
                                              Icons.access_time,
                                              size: 20,
                                              color: _deepPurple,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Start time',
                                                    style: GoogleFonts.nunito(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: _mutedPurple,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    '${DateFormat('MMM d, yyyy').format(prescribedDate)}  ·  ${startTime.format(ctx)}',
                                                    style: GoogleFonts.nunito(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: _deepPurple,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const Icon(
                                              Icons.edit_outlined,
                                              size: 18,
                                              color: _mutedPurple,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Prescribed date (defaults to today; allow past dates)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.75),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _borderColor),
                        ),
                        child: InkWell(
                          onTap: () async {
                            final firstDate = DateTime(1900);
                            final lastDate = todayDate.add(
                              const Duration(days: 3650),
                            );
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: prescribedDate,
                              firstDate: firstDate,
                              lastDate: lastDate,
                              builder: (context, child) => Theme(
                                data: _pickerTheme(context),
                                child: child!,
                              ),
                            );
                            if (picked == null) return;
                            setModal(
                              () => prescribedDate = DateTime(
                                picked.year,
                                picked.month,
                                picked.day,
                              ),
                            );
                          },
                          child: Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_outlined,
                                size: 20,
                                color: _deepPurple,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Prescribed date',
                                      style: GoogleFonts.nunito(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        color: _mutedPurple,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat(
                                        'MMM d, yyyy',
                                      ).format(prescribedDate),
                                      style: GoogleFonts.nunito(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                        color: _deepPurple,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.edit_outlined,
                                size: 18,
                                color: _mutedPurple,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      GestureDetector(
                        onTap: () =>
                            setModal(() => notesExpanded = !notesExpanded),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.78),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Notes (Optional)',
                                  style: GoogleFonts.nunito(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: _deepPurple,
                                  ),
                                ),
                              ),
                              Icon(
                                notesExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                color: _mutedPurple,
                                size: 26,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (notesExpanded) ...[
                        const SizedBox(height: 12),
                        _modalField(
                          controller: notesCtrl,
                          hint: 'Write something…',
                        ),
                        const SizedBox(height: 10),
                        VoiceNoteAttachment(
                          initialPath: voiceNotePath,
                          onChanged: (path) =>
                              setModal(() => voiceNotePath = path),
                          borderColor: _borderColor,
                          primaryColor: _purple,
                          textColor: _deepPurple,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _chooserPillButton(
                                label: 'Camera',
                                icon: Icons.photo_camera_outlined,
                                onTap: () async {
                                  final file = await _imagePicker.pickImage(
                                    source: ImageSource.camera,
                                    imageQuality: 85,
                                  );
                                  if (file == null) return;
                                  setModal(() => notesPhotoPath = file.path);
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _chooserPillButton(
                                label: 'Photos',
                                icon: Icons.photo_library_outlined,
                                onTap: () async {
                                  final file = await _imagePicker.pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 85,
                                  );
                                  if (file == null) return;
                                  setModal(() => notesPhotoPath = file.path);
                                },
                              ),
                            ),
                          ],
                        ),
                        if ((notesPhotoPath ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _borderColor),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.file(
                                    File(notesPhotoPath!),
                                    width: 84,
                                    height: 84,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Photo attached',
                                    style: GoogleFonts.nunito(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                      color: _deepPurple,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () =>
                                      setModal(() => notesPhotoPath = null),
                                  icon: const Icon(
                                    Icons.close,
                                    color: _mutedPurple,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                      ],
                      const SizedBox(height: 28),

                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6B5B8E),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(32),
                            ),
                          ),
                          onPressed: () async {
                            if (nameCtrl.text.trim().isEmpty) return;
                            if (_careTeamId == null) return;

                            final enteredKey = _medicationKeyLower(
                              name: nameCtrl.text,
                              strengthAmount: selectedStrengthAmount,
                              strengthUnit: selectedStrengthUnit,
                            );
                            if (existingMedicationKeysLower.contains(
                              enteredKey,
                            )) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'This medication is already added',
                                    style: GoogleFonts.nunito(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                  backgroundColor: Colors.red.shade700,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                              );
                              return;
                            }

                            final member = SessionManager().currentMember;
                            final patientName =
                                SessionManager()
                                    .currentCareTeam
                                    ?.patientFirstName ??
                                'Patient';

                            final prescribedLabel = DateFormat(
                              'MMM d, yyyy',
                            ).format(prescribedDate);

                            final doseTimes = <TimeOfDay>[];
                            if (selectedFreqType == 'daily') {
                              doseTimes.add(doseTime1);
                              if (dailyFrequency == 'Twice daily' ||
                                  dailyFrequency == 'Thrice daily') {
                                doseTimes.add(doseTime2);
                              }
                              if (dailyFrequency == 'Thrice daily') {
                                doseTimes.add(doseTime3);
                              }
                            }

                            final baseTime = selectedFreqType == 'daily'
                                ? doseTime1
                                : startTime;
                            final medicationStart = DateTime(
                              prescribedDate.year,
                              prescribedDate.month,
                              prescribedDate.day,
                              baseTime.hour,
                              baseTime.minute,
                            );

                            String? calendarFrequencyOverride;
                            if (!isPrn && addToCalendar) {
                              if (selectedFreqType == 'hour') {
                                calendarFrequencyOverride =
                                    'every_hours:$hoursValue';
                              } else if (selectedFreqType == 'day') {
                                calendarFrequencyOverride =
                                    'every_days:$daysValue';
                              } else if (selectedFreqType == 'daily') {
                                final minutes = doseTimes
                                    .map((t) => t.hour * 60 + t.minute)
                                    .toList();
                                calendarFrequencyOverride =
                                    'daily_times:${minutes.join(',')}';
                              }
                            }

                            final scheduleParts = <String>[
                              'Prescribed: $prescribedLabel',
                            ];
                            if (selectedFreqType == 'daily') {
                              scheduleParts.add(
                                'Dose time(s): ${doseTimes.map((t) => t.format(ctx)).join(', ')}',
                              );
                            } else {
                              scheduleParts.add(
                                'Start: $prescribedLabel ${startTime.format(ctx)}',
                              );
                            }

                            final scheduleDetails =
                                scheduleCtrl.text.trim().isEmpty
                                ? scheduleParts.join(' · ')
                                : '${scheduleCtrl.text.trim()} · ${scheduleParts.join(' · ')}';

                            final newMed = Medication(
                              id: _uuid.v4(),
                              careTeamId: _careTeamId,
                              name: nameCtrl.text.trim(),
                              strength: selectedStrengthAmount,
                              typicalDose: selectedStrengthUnit,
                              route: route,
                              pattern: getFreqPattern(),
                              scheduleDetails: scheduleDetails,
                              notes: NoteVoiceCodec.encodeWithPhoto(
                                text: notesCtrl.text.trim(),
                                audioPath: voiceNotePath,
                                photoPath: notesPhotoPath,
                              ),
                              createdAt: DateTime.now(),
                              createdByMemberId: member?.id,
                            );
                            try {
                              final confirmed = await _confirmMedicationDetails(
                                patientName: patientName,
                                medication: newMed,
                              );
                              if (!confirmed) return;
                              await _saveMedicationWithSchedule(
                                newMed,
                                medicationStart: medicationStart,
                                addToCalendar: addToCalendar,
                                calendarFrequencyOverride:
                                    calendarFrequencyOverride,
                              );
                            } catch (e) {
                              debugPrint('Error adding medication: $e');
                            }
                          },
                          child: Text(
                            'Save Medication',
                            style: GoogleFonts.nunito(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFriendlyStepper({
    required String label,
    required int value,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Give every',
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _deepPurple,
            ),
          ),
          Row(
            children: [
              GestureDetector(
                onTap: onDecrement,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _cardBg,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.remove, color: _deepPurple),
                ),
              ),
              Container(
                width: 60,
                alignment: Alignment.center,
                child: Text(
                  '$value',
                  style: GoogleFonts.nunito(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: _deepPurple,
                  ),
                ),
              ),
              GestureDetector(
                onTap: onIncrement,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: _purple),
                ),
              ),
            ],
          ),
          SizedBox(
            width: 50,
            child: Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _deepPurple,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFrequencyOption({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? _purple : Colors.white.withOpacity(0.82),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _purple : _borderColor,
            width: 1.4,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.nunito(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: isSelected ? Colors.white : _deepPurple,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeMeds = _medications
        .where((m) => m.pattern != 'inactive')
        .toList();
    final inactiveMeds = _medications
        .where((m) => m.pattern == 'inactive')
        .toList();

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
                            'Medications',
                            style: GoogleFonts.nunito(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
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

              const SizedBox(height: 16),

              // ── Body with Pull-to-Refresh ──
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadMedications,
                  color: _purple,
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                      : _medications.isEmpty
                      ? _emptyState()
                      : FadeTransition(
                          opacity: _fadeAnim,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              if (activeMeds.isNotEmpty) ...[
                                Text(
                                  'Active Prescriptions',
                                  style: GoogleFonts.nunito(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...activeMeds.map(
                                  (m) => MedicationCard(
                                    med: m,
                                    isActive: true,
                                    lastAdministeredAt:
                                        _lastAdministeredByMedicationId[m.id],
                                    onDeprescribe: () =>
                                        _showDeprescribeDialog(m),
                                    onLogAdministered: () =>
                                        _showAdministerDialog(m),
                                  ),
                                ),
                              ],

                              // Deprescribed shown directly underneath in a different color
                              if (inactiveMeds.isNotEmpty) ...[
                                const SizedBox(height: 24),
                                Text(
                                  'Deprescribed',
                                  style: GoogleFonts.nunito(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: const Color.fromARGB(
                                      255,
                                      51,
                                      51,
                                      51,
                                    ).withOpacity(0.7),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ...inactiveMeds.map(
                                  (m) => MedicationCard(
                                    med: m,
                                    isActive: false,
                                    lastAdministeredAt:
                                        _lastAdministeredByMedicationId[m.id],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                ),
              ),
              const PremiumBottomNav(currentIndex: 0),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),

      // ── FAB ──
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 80),
        child: GestureDetector(
          onTap: _showAddMedicationEntrySheet,
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

  // ─── Modal & Empty State helpers ─────────────────────────────────────────
  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.28),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Icon(
              Icons.medication_outlined,
              size: 34,
              color: Color(0xFF6B5B8E),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No medications yet',
            style: GoogleFonts.nunito(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: const Color(0xFF1F1A2B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "+" to get started',
            style: GoogleFonts.nunito(
              fontSize: 16,
              color: const Color(0xFF1F1A2B).withOpacity(0.65),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _modalLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        text,
        style: GoogleFonts.nunito(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: _deepPurple,
        ),
      ),
    );
  }

  Widget _modalField({
    required TextEditingController controller,
    required String hint,
    TextInputType? type,
  }) {
    return AnimatedBorderField(
      controller: controller,
      hint: hint,
      keyboardType: type,
    );
  }
}

// ─── Medication Card (Stateful for Expansion) ───────────────────────────────
class MedicationCard extends StatefulWidget {
  final Medication med;
  final bool isActive;
  final DateTime? lastAdministeredAt;
  final VoidCallback? onDeprescribe;
  final VoidCallback? onLogAdministered;

  const MedicationCard({
    super.key,
    required this.med,
    required this.isActive,
    this.lastAdministeredAt,
    this.onDeprescribe,
    this.onLogAdministered,
  });

  @override
  State<MedicationCard> createState() => _MedicationCardState();
}

class _MedicationCardState extends State<MedicationCard> {
  bool _expanded = false;

  String _titleWithDosage(Medication med) {
    final name = (med.name ?? 'Unknown').trim();
    final amount = (med.strength ?? '').trim();
    final unit = (med.typicalDose ?? '').trim();
    final dosage = [amount, unit].where((s) => s.isNotEmpty).join('');
    if (dosage.isEmpty) return name;
    return '$name $dosage';
  }

  String? _extractPrescribedDateLabel(String? scheduleDetails) {
    final s = (scheduleDetails ?? '').trim();
    if (s.isEmpty) return null;

    final match = RegExp(
      r'Prescribed:\s*([A-Za-z]{3}\s+\d{1,2},\s+\d{4})',
    ).firstMatch(s);
    if (match != null) {
      final raw = match.group(1);
      if (raw != null && raw.trim().isNotEmpty) {
        try {
          final parsed = DateFormat('MMM d, yyyy').parseLoose(raw.trim());
          return DateFormat('MMM d, yyyy').format(parsed);
        } catch (_) {
          return raw.trim();
        }
      }
    }

    final iso = RegExp(r'(\d{4}-\d{2}-\d{2})').firstMatch(s);
    if (iso != null) return iso.group(1);
    return null;
  }

  bool _looksLikeDebugJson(String text) {
    final t = text.trim();
    if (t.length < 2) return false;
    if (!(t.startsWith('{') && t.endsWith('}'))) return false;
    final lower = t.toLowerCase();
    return lower.contains('"strength"') ||
        lower.contains('"typical_dose"') ||
        lower.contains('"route"') ||
        lower.contains('"pattern"') ||
        lower.contains('"schedule_details"');
  }

  String _lastAdministeredValue() {
    final lastAdministeredAt = widget.lastAdministeredAt;
    if (lastAdministeredAt == null) {
      return 'Not yet logged';
    }
    final formatted = DateFormat(
      'MMM d, yyyy h:mm a',
    ).format(lastAdministeredAt);
    return formatted;
  }

  Widget _infoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _borderColor.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: GoogleFonts.nunito(
          fontSize: 15,
          color: _deepPurple,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.med;
    final decodedNotes = NoteVoiceCodec.decode(med.notes);
    final noteText = decodedNotes.text.trim();
    final voicePath = decodedNotes.audioPath;
    final hasNotes = noteText.isNotEmpty && !_looksLikeDebugJson(noteText);
    final patternLower = med.pattern?.toLowerCase();
    final isAsNeeded =
        patternLower?.contains('prn') == true ||
        patternLower?.contains('as needed') == true;

    final patternLabel = isAsNeeded ? 'As needed' : (med.pattern ?? '');
    final prescribedDateChip = _extractPrescribedDateLabel(med.scheduleDetails);

    final cardColor = widget.isActive
        ? Colors.white.withOpacity(0.95)
        : const Color(0xFFE0E0E0);
    final inactiveTextColor = Colors.black87;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: widget.isActive ? _borderColor : const Color(0xFFB0B0B0),
        ),
        boxShadow: _expanded && widget.isActive
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
                    color: widget.isActive
                        ? const Color(0xFF8E7CB1).withOpacity(0.15)
                        : const Color(0xFFC6C6C6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.medication_outlined,
                    size: 20,
                    color: widget.isActive ? _purple : Colors.black87,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _titleWithDosage(med),
                        style: GoogleFonts.nunito(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: widget.isActive
                              ? _deepPurple
                              : inactiveTextColor,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Last administered',
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: const Color.fromARGB(255, 27, 27, 28),
                        ),
                      ),
                      Text(
                        _lastAdministeredValue(),
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
              if (med.route != null ||
                  (med.pattern != null && med.pattern != 'inactive') ||
                  (prescribedDateChip ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    // Order: route (tablet) -> frequency -> start date
                    if ((med.route ?? '').trim().isNotEmpty)
                      _infoChip(med.route!.trim()),
                    if (med.pattern != null && med.pattern != 'inactive')
                      _infoChip(patternLabel),
                    if ((prescribedDateChip ?? '').trim().isNotEmpty)
                      _infoChip(prescribedDateChip!.trim()),
                  ],
                ),
              ],
              if (hasNotes) ...[
                const SizedBox(height: 12),
                Text(
                  noteText,
                  style: GoogleFonts.nunito(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    height: 1.5,
                    color: Colors.black,
                  ),
                ),
              ],
              if (voicePath != null && voicePath.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                VoiceNotePlaybackButton(
                  path: voicePath,
                  borderColor: _borderColor,
                  textColor: _deepPurple,
                ),
              ],
              const SizedBox(height: 16),
              const Divider(color: _borderColor),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (widget.isActive) ...[
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
                        onPressed: widget.onLogAdministered,
                        child: Text(
                          'Administer',
                          style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: _borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const HistoryScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'History',
                        style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w700,
                          color: _deepPurple,
                        ),
                      ),
                    ),
                  ),
                  if (widget.isActive) ...[
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
                        onPressed: widget.onDeprescribe,
                        child: Text(
                          'Remove',
                          style: GoogleFonts.nunito(
                            fontWeight: FontWeight.w700,
                            color: Colors.red.shade700,
                          ),
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

// ─── Medication autocomplete ─────────────────────────────────────────────────

class _MedicationListSuggestion {
  final String name;
  final String? brand;
  final String? strengthLabel;
  final String? strengthAmount;
  final String? strengthUnit;

  const _MedicationListSuggestion({
    required this.name,
    required this.brand,
    required this.strengthLabel,
    required this.strengthAmount,
    required this.strengthUnit,
  });

  String get display {
    final strength = (strengthLabel ?? '').trim();
    if (strength.isEmpty) return name;
    return '$name $strength';
  }

  String get selectedDisplayName {
    final b = (brand ?? '').trim();
    if (b.isEmpty) return name;
    if (name.toLowerCase().contains('(${b.toLowerCase()})')) return name;
    return '$name ($b)';
  }
}

class _MedicationAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final void Function(_MedicationListSuggestion) onSelected;
  final Set<String> existingMedicationKeysLower;

  const _MedicationAutocomplete({
    required this.controller,
    this.existingMedicationKeysLower = const <String>{},
    required this.onSelected,
  });

  @override
  State<_MedicationAutocomplete> createState() =>
      _MedicationAutocompleteState();
}

class _MedicationAutocompleteState extends State<_MedicationAutocomplete>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<Color?> _borderTween;
  final FocusNode _focusNode = FocusNode();
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  bool _overlayUpdateScheduled = false;
  bool _focused = false;
  List<_MedicationListSuggestion> _suggestions = [];
  _MedicationListSuggestion? _selectedMedication;
  bool _isDuplicate = false;

  static final SupabaseClient _client = Supabase.instance.client;
  Timer? _debounce;
  bool _loading = false;
  String _lastFetchQuery = '';

  static const _violet = Color(0xFF7A64A4);
  static const _idle = Color(0xFFD4CDDF);
  static const _fieldBg = Color(0xFFF0EDF6);
  static const double _contentLeftInset = 48;

  String _formatStrengthLabel(String raw) {
    final trimmed = raw.trim();
    final match = RegExp(
      r'^(\d+(?:\.\d+)?)\s+([a-zA-Z%]+)(.*)$',
    ).firstMatch(trimmed);
    if (match == null) return trimmed;
    return '${match.group(1)}${match.group(2)}${match.group(3) ?? ''}'.trim();
  }

  String? _readOptionalString(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final v = row[key];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  String _normalizeFormSuffix(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return s;
    s = s.replaceAll(RegExp(r'^tabs\b', caseSensitive: false), 'tablet');
    s = s.replaceAll(RegExp(r'^tab\b', caseSensitive: false), 'tablet');
    s = s.replaceAll(RegExp(r'^tablets\b', caseSensitive: false), 'tablet');
    s = s.replaceAll(RegExp(r'^capsules\b', caseSensitive: false), 'capsule');
    s = s.replaceAll(RegExp(r'^caps\b', caseSensitive: false), 'capsule');
    s = s.replaceAll(RegExp(r'^cap\b', caseSensitive: false), 'capsule');
    return s.trim();
  }

  String? _extractQualifierFromPrefix(String prefix) {
    final p = prefix.trim();
    if (p.isEmpty) return null;
    final tokens = p
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return null;

    const known = <String>{
      'ir',
      'er',
      'xr',
      'sr',
      'cr',
      'dr',
      'odt',
      'sl',
      'la',
      'xl',
      'pr',
    };

    final last = tokens.last;
    if (!known.contains(last)) return null;
    return last.toUpperCase();
  }

  List<String> _expandStrengthLabels(Object? rawStrengths) {
    if (rawStrengths == null) return <String>[];

    // If the DB already stores strengths as a list, we still run it through
    // the same normalizer so shared suffixes like "tablets" become neat rows.
    final input = rawStrengths is List
        ? rawStrengths.map((e) => e.toString()).join('; ')
        : rawStrengths.toString();

    final cleaned = input.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
    if (cleaned.isEmpty) return <String>[];

    final results = <String>[];
    final groups = cleaned
        .split(';')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    for (final group in groups) {
      var content = group;
      String? qualifier;

      final colonIdx = content.indexOf(':');
      if (colonIdx >= 0) {
        final prefix = content.substring(0, colonIdx).trim();
        qualifier = _extractQualifierFromPrefix(prefix);
        content = content.substring(colonIdx + 1).trim();
      }

      if (content.isEmpty) continue;

      final pieces = content
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      if (pieces.isEmpty) continue;

      String? sharedSuffix;
      var lastPiece = pieces.last;
      final suffixMatch = RegExp(
        r'^(.*\d.*)\s+([^\d]+)$',
      ).firstMatch(lastPiece);
      if (suffixMatch != null) {
        final left = suffixMatch.group(1)?.trim() ?? '';
        final right = suffixMatch.group(2)?.trim() ?? '';
        if (left.isNotEmpty && right.isNotEmpty) {
          sharedSuffix = _normalizeFormSuffix(right);
          lastPiece = left;
          pieces[pieces.length - 1] = lastPiece;
        }
      }

      for (final piece in pieces) {
        var label = piece;
        if (qualifier != null && qualifier.isNotEmpty) {
          // Avoid duplicating qualifier if it already appears.
          if (!label.toLowerCase().contains(qualifier.toLowerCase())) {
            label = '$label $qualifier';
          }
        }
        if (sharedSuffix != null && sharedSuffix.isNotEmpty) {
          if (!label.toLowerCase().contains(sharedSuffix.toLowerCase())) {
            label = '$label $sharedSuffix';
          }
        }

        final formatted = _formatStrengthLabel(label);
        if (formatted.isNotEmpty) results.add(formatted);
      }
    }

    // De-dup while preserving order.
    final seen = <String>{};
    return results.where((s) => seen.add(s.toLowerCase())).toList();
  }

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _borderTween = ColorTween(
      begin: _idle,
      end: _violet,
    ).animate(CurvedAnimation(parent: _anim, curve: Curves.easeInOut));
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusNodeChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusNodeChanged);
    _removeOverlay();
    _focusNode.dispose();
    _anim.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onFocusNodeChanged() {
    _onFocus(_focusNode.hasFocus);
  }

  void _scheduleOverlayUpdate() {
    if (_overlayUpdateScheduled) return;
    _overlayUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayUpdateScheduled = false;
      if (!mounted) return;
      _updateOverlay();
    });
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _updateOverlay() {
    // Keep overlay in sync with focus + suggestions.
    if (!_focusNode.hasFocus || _suggestions.isEmpty) {
      _removeOverlay();
      return;
    }

    // Use the root overlay so the dropdown is never clipped/hidden by
    // bottom sheets/scroll views.
    final overlay = Overlay.of(context, rootOverlay: true);

    if (_overlayEntry == null) {
      _overlayEntry = OverlayEntry(
        builder: (context) {
          final renderBox =
              _fieldKey.currentContext?.findRenderObject() as RenderBox?;
          final size = renderBox?.size;
          final width = size?.width ?? 0;
          final height = size?.height ?? 0;

          final borderColor = _isDuplicate
              ? Colors.red.shade400
              : (_borderTween.value ?? _idle);
          final borderWidth = (_focusNode.hasFocus || _isDuplicate) ? 1.8 : 1.0;

          // If we can't measure yet, don't render.
          if (width <= 0 || height <= 0) {
            return const SizedBox.shrink();
          }

          // Explicit height prevents the follower from expanding to full-screen
          // constraints in the root overlay.
          const maxHeight = 200.0;
          const rowHeightEstimate = 56.0;
          final desired = (_suggestions.length * rowHeightEstimate) + 8.0;
          final dropdownHeight = math.min(maxHeight, desired);

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    _focusNode.unfocus();
                    _removeOverlay();
                  },
                  child: const SizedBox.expand(),
                ),
              ),
              CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                // Slight overlap so dropdown visually attaches to field.
                offset: Offset(0, height - borderWidth),
                child: Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: width,
                    height: dropdownHeight,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(14),
                        ),
                        border: Border(
                          left: BorderSide(
                            color: borderColor,
                            width: borderWidth,
                          ),
                          right: BorderSide(
                            color: borderColor,
                            width: borderWidth,
                          ),
                          bottom: BorderSide(
                            color: borderColor,
                            width: borderWidth,
                          ),
                          top: BorderSide.none,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(14),
                        ),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _suggestions.length,
                          itemBuilder: (context, i) {
                            final med = _suggestions[i];
                            final strengthText = (med.strengthLabel ?? '')
                                .trim();
                            return InkWell(
                              onTap: () {
                                final key = _medicationKeyLower(
                                  name: med.name,
                                  strengthAmount: med.strengthAmount,
                                  strengthUnit: med.strengthUnit,
                                );
                                final exists = widget
                                    .existingMedicationKeysLower
                                    .contains(key);

                                widget.controller.text = med.name;
                                widget.controller.selection =
                                    TextSelection.collapsed(
                                      offset: med.name.length,
                                    );

                                setState(() {
                                  _suggestions = [];
                                  _selectedMedication = exists ? null : med;
                                  _isDuplicate = exists;
                                });
                                _removeOverlay();
                                if (exists) return;
                                widget.onSelected(med);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    left: _contentLeftInset,
                                    right: 4,
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        med.name,
                                        style: GoogleFonts.nunito(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF2E2540),
                                        ),
                                      ),
                                      if (strengthText.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            top: 2,
                                          ),
                                          child: Text(
                                            _formatStrengthLabel(strengthText),
                                            style: GoogleFonts.nunito(
                                              fontSize: 14,
                                              color: const Color(0xFF6C648B),
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
      overlay.insert(_overlayEntry!);
    } else {
      _overlayEntry!.markNeedsBuild();
    }
  }

  // (Old) _parseStrengths removed in favor of _expandStrengthLabels.

  ({String? amount, String? unit}) _splitStrength(String strength) {
    final s = strength.trim();
    final match = RegExp(r'^(\d+(?:\.\d+)?)\s*([a-zA-Z%]+.*)?$').firstMatch(s);
    if (match == null) return (amount: null, unit: null);
    final amount = match.group(1);
    final unit = match.group(2);
    return (amount: amount, unit: unit?.trim());
  }

  Future<void> _fetchSuggestions(String query) async {
    final q = query.trim();
    if (q.length < 3) {
      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _loading = false;
      });
      _scheduleOverlayUpdate();
      return;
    }

    _lastFetchQuery = q;
    if (!mounted) return;
    setState(() => _loading = true);
    _scheduleOverlayUpdate();

    try {
      final response = await _client
          .from('medication_list')
          // Use '*' selection to avoid hard-failing when columns differ between
          // environments. Limit keeps payload small.
          .select()
          .ilike('name', '$q%')
          .limit(25);

      final rows = (response as List).cast<Map<String, dynamic>>();
      final suggestions = <_MedicationListSuggestion>[];

      for (final row in rows) {
        final name = (row['name'] ?? '').toString().trim();
        if (name.isEmpty) continue;

        final brand = _readOptionalString(row, const [
          'brand_name',
          'brand',
          'brandname',
          'trade_name',
          'trade',
        ]);

        // Schema note: this project uses `strengths` in Supabase, but older
        // schemas (or exports) may use `available_strengths`.
        final rawStrengths = row['strengths'] ?? row['available_strengths'];
        final strengths = _expandStrengthLabels(rawStrengths);

        if (strengths.isEmpty) {
          suggestions.add(
            _MedicationListSuggestion(
              name: name,
              brand: brand,
              strengthLabel: null,
              strengthAmount: null,
              strengthUnit: null,
            ),
          );
        } else {
          for (final strength in strengths) {
            final parts = _splitStrength(strength);
            suggestions.add(
              _MedicationListSuggestion(
                name: name,
                brand: brand,
                strengthLabel: strength,
                strengthAmount: parts.amount,
                strengthUnit: parts.unit,
              ),
            );
          }
        }
      }

      if (kDebugMode) {
        debugPrint(
          '[MedicationAutocomplete] q="$q" rows=${rows.length} suggestions=${suggestions.length}',
        );
      }

      if (!mounted) return;
      if (widget.controller.text.trim() != _lastFetchQuery) {
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _suggestions = suggestions;
        _loading = false;
      });
      _scheduleOverlayUpdate();
    } catch (e) {
      debugPrint('[MedicationAutocomplete] medication_list query failed: $e');
      if (!mounted) return;
      setState(() {
        _suggestions = [];
        _loading = false;
      });
      _scheduleOverlayUpdate();
    }
  }

  void _onTextChanged() {
    final query = widget.controller.text.trim().toLowerCase();

    // If the user edits the field away from a previously selected medication,
    // clear the persisted selection label.
    final selected = _selectedMedication;
    if (selected != null && widget.controller.text.trim() != selected.name) {
      if (mounted) {
        setState(() {
          _selectedMedication = null;
          _isDuplicate = false;
        });
      }
    }

    if (query.isEmpty) {
      setState(() {
        _suggestions = [];
        _isDuplicate = false;
        _loading = false;
      });
      _removeOverlay();
      return;
    }

    // If the current value exactly matches the selected medication, keep the
    // suggestions list hidden (prevents duplicate rendering).
    if (query == (_selectedMedication?.name.trim().toLowerCase() ?? '')) {
      setState(() => _suggestions = []);
      _removeOverlay();
      return;
    }

    // Rebuild to update suffix icon state while typing.
    if (mounted) setState(() {});

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _fetchSuggestions(widget.controller.text);
    });
  }

  void _onFocus(bool focused) {
    setState(() => _focused = focused);
    focused ? _anim.forward() : _anim.reverse();
    if (!focused) {
      // Delay hiding suggestions so tap on item registers first
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!mounted) return;
        setState(() => _suggestions = []);
        _removeOverlay();
      });
    } else {
      _scheduleOverlayUpdate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = _isDuplicate
        ? Colors.red.shade400
        : (_borderTween.value ?? _idle);
    final borderWidth = (_focused || _isDuplicate) ? 1.8 : 1.0;
    final showDropdown = _focusNode.hasFocus && _suggestions.isNotEmpty;

    // Keep the overlay aligned/rebuilt after layout changes.
    _scheduleOverlayUpdate();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        CompositedTransformTarget(
          link: _layerLink,
          child: AnimatedBuilder(
            animation: _anim,
            builder: (context, child) => Container(
              key: _fieldKey,
              decoration: BoxDecoration(
                color: _fieldBg,
                borderRadius: showDropdown
                    ? const BorderRadius.vertical(top: Radius.circular(14))
                    : BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: borderWidth),
                boxShadow: const [],
              ),
              child: child,
            ),
            child: TextField(
              controller: widget.controller,
              focusNode: _focusNode,
              style: GoogleFonts.nunito(
                fontSize: 16,
                color: const Color(0xFF2E2540),
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                hintText: 'Search medication name or brand...',
                hintStyle: GoogleFonts.nunito(
                  fontSize: 16,
                  color: const Color(0xFF6C648B).withOpacity(0.7),
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 22,
                  color: Color(0xFF6C648B),
                ),
                suffixIcon: widget.controller.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(
                          Icons.clear,
                          size: 20,
                          color: Color(0xFF6C648B),
                        ),
                        onPressed: () {
                          widget.controller.clear();
                          setState(() {
                            _suggestions = [];
                            _selectedMedication = null;
                            _isDuplicate = false;
                            _loading = false;
                          });
                          _removeOverlay();
                        },
                      )
                    : null,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 0,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),

        if (_selectedMedication != null && !_isDuplicate)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _fieldBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _idle),
              ),
              child: Padding(
                padding: const EdgeInsets.only(
                  left: _contentLeftInset,
                  right: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _selectedMedication!.selectedDisplayName,
                      style: GoogleFonts.nunito(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF2E2540),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((_selectedMedication!.strengthLabel ?? '')
                        .trim()
                        .isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _formatStrengthLabel(
                            _selectedMedication!.strengthLabel!.trim(),
                          ),
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            color: const Color(0xFF6C648B),
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

        if (_isDuplicate)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 4),
            child: Text(
              'This medicine is already added',
              style: GoogleFonts.nunito(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade700,
              ),
            ),
          ),

        if (_loading)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _purple,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Searching…',
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6C648B),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
