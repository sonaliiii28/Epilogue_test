import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../core/session_manager.dart';
import '../core/note_voice_codec.dart';
import '../core/supabase_service.dart';
import '../domain/models.dart';
import 'widgets/voice_note_attachment.dart';

const _purple = Color(0xFF7A64A4);
const _borderColor = Color(0xFFD4CDDF);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

class SkinWoundsScreen extends StatefulWidget {
  const SkinWoundsScreen({super.key});

  @override
  State<SkinWoundsScreen> createState() => _SkinWoundsScreenState();
}

class _SkinWoundsScreenState extends State<SkinWoundsScreen> {
  final _service = SupabaseService();
  final _uuid = const Uuid();
  final _picker = ImagePicker();
  bool? hasSkinIssue;

  final Set<String> selectedConditions = {};
  final Set<String> selectedTreatments = {};
  XFile? selectedPhoto;
  final TextEditingController locationCtrl = TextEditingController();
  final TextEditingController notesCtrl = TextEditingController();
  String? _voiceNotePath;

  @override
  void dispose() {
    locationCtrl.dispose();
    notesCtrl.dispose();
    super.dispose();
  }

  // M1195
  final conditions = [
    'Diabetic foot ulcer',
    'Open lesions',
    'Pressure injury',
    'Rash',
    'Skin tear',
    'Surgical wound',
    'Other ulcers',
    'Moisture skin damage',
  ];

  // M1200
  final treatments = [
    'Chair pressure device',
    'Bed pressure device',
    'Repositioning program',
    'Nutrition / hydration',
    'Pressure injury care',
    'Surgical wound care',
    'Dressings (non-foot)',
    'Ointments / medications',
    'Foot dressings',
    'Incontinence care',
  ];

  bool get showAlert {
    return selectedConditions.any(
      (c) =>
          c.contains('Pressure') ||
          c.contains('Skin tear') ||
          c.contains('Surgical'),
    );
  }

  void toggleTreatmentSelection(String value) {
    setState(() {
      if (selectedTreatments.contains(value)) {
        selectedTreatments.remove(value);
      } else {
        selectedTreatments.add(value);
      }
    });
  }

  void selectCondition(String value) {
    setState(() {
      selectedConditions
        ..clear()
        ..add(value);
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final file = await _picker.pickImage(source: source, imageQuality: 85);
    if (file == null || !mounted) return;
    setState(() => selectedPhoto = file);
  }

  Widget buildChip(String label, Set<String> set, void Function() onTap) {
    final isSelected = set.contains(label);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _purple : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isSelected ? _purple : _borderColor),
        ),
        child: Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (hasSkinIssue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose Yes or No first.')),
      );
      return;
    }

    final selectedSkinConditions = selectedConditions.toList();
    final selectedSkinTreatments = selectedTreatments.toList();

    if (hasSkinIssue == true && selectedSkinConditions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one skin condition.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          "Confirm",
          style: GoogleFonts.nunito(fontWeight: FontWeight.w800),
        ),
        content: Text("Save this skin record?", style: GoogleFonts.nunito()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Save"),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (confirmed != true) return;

    final teamId = SessionManager().currentCareTeam?.id;
    final member = SessionManager().currentMember;
    if (teamId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active care team found.')),
      );
      return;
    }

    final now = DateTime.now();
    final noteTextParts = <String>[];
    final location = locationCtrl.text.trim();
    if (location.isNotEmpty) {
      noteTextParts.add('Location: $location');
    }
    final additionalNotes = notesCtrl.text.trim();
    if (additionalNotes.isNotEmpty) {
      noteTextParts.add(additionalNotes);
    }
    final encodedNotes = NoteVoiceCodec.encode(
      text: noteTextParts.join('\n'),
      audioPath: _voiceNotePath,
    );
    final eventNotes =
        encodedNotes ??
        (hasSkinIssue == false
            ? 'Skin check recorded with no current issues.'
            : null);

    final event = SkinWoundEvent(
      id: _uuid.v4(),
      careTeamId: teamId,
      hasSkinCondition: hasSkinIssue == true,
      skinCondition: hasSkinIssue == true && selectedSkinConditions.isNotEmpty
          ? selectedSkinConditions.first
          : null,
      treatments: hasSkinIssue == true ? selectedSkinTreatments : const [],
      imageUrls: selectedPhoto != null ? [selectedPhoto!.path] : const [],
      notes: eventNotes,
      eventTime: now,
      createdByMemberId: member?.id,
      createdByMemberName: member?.name,
      editableUntil: now.add(const Duration(hours: 1)),
    );

    try {
      await _service.logSkinWoundEvent(event);
    } catch (e) {
      if (!mounted) return;

      var message = 'Failed to save skin record.';
      if (e is PostgrestException) {
        final parts = <String>[e.message];
        if ((e.details ?? '').toString().trim().isNotEmpty) {
          parts.add(e.details.toString());
        }
        message = parts.join(' ');
      } else {
        final raw = e.toString().trim();
        if (raw.isNotEmpty) message = raw;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    } else {
      context.go('/skin-wounds');
    }
  }

  @override
  Widget build(BuildContext context) {
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
              // ── HEADER ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/skin-wounds');
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
                            'Skin & Wounds',
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

              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0EDF6),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: ListView(
                    children: [
                      // M1190
                      Text(
                        "Any skin or wound issues?",
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: buildChip(
                              "No",
                              {if (hasSkinIssue == false) "No"},
                              () => setState(() {
                                hasSkinIssue = false;
                                selectedConditions.clear();
                                selectedTreatments.clear();
                                selectedPhoto = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: buildChip("Yes", {
                              if (hasSkinIssue == true) "Yes",
                            }, () => setState(() => hasSkinIssue = true)),
                          ),
                        ],
                      ),

                      if (hasSkinIssue == true) ...[
                        const SizedBox(height: 24),

                        // M1195
                        Text(
                          "Type of skin condition",
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: conditions.map((c) {
                            return buildChip(
                              c,
                              selectedConditions,
                              () => selectCondition(c),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 24),

                        // M1200
                        Text(
                          "Treatments in place",
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            buildChip('None', {
                              if (selectedTreatments.isEmpty) 'None',
                            }, () => setState(selectedTreatments.clear)),
                            ...treatments.map((t) {
                              return buildChip(
                                t,
                                selectedTreatments,
                                () => toggleTreatmentSelection(t),
                              );
                            }),
                          ],
                        ),

                        const SizedBox(height: 24),

                        Text(
                          "Upload skin condition photo",
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (selectedPhoto != null) ...[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(selectedPhoto!.path),
                              height: 220,
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () =>
                                  setState(() => selectedPhoto = null),
                              child: Text(
                                'Remove photo',
                                style: GoogleFonts.nunito(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.red.shade700,
                                ),
                              ),
                            ),
                          ),
                        ] else
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.8),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: _borderColor),
                            ),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.add_a_photo_outlined,
                                  color: _purple,
                                  size: 32,
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Attach a skin photo',
                                  style: GoogleFonts.nunito(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.black,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _purple,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () => _pickPhoto(ImageSource.camera),
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: Text(
                                  'Take Photo',
                                  style: GoogleFonts.nunito(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _purple,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                onPressed: () =>
                                    _pickPhoto(ImageSource.gallery),
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(
                                  'Upload Photo',
                                  style: GoogleFonts.nunito(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      if (showAlert) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.red.shade200),
                          ),
                          child: Text(
                            "This condition requires clinical monitoring",
                            style: GoogleFonts.nunito(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      Text(
                        'Location',
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),

                      TextField(
                        controller: locationCtrl,
                        decoration: const InputDecoration(
                          hintText: 'Optional',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // NOTES
                      Text(
                        "Additional notes",
                        style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),

                      TextField(
                        controller: notesCtrl,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: "Optional",
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 12),
                      VoiceNoteAttachment(
                        initialPath: _voiceNotePath,
                        onChanged: (p) => setState(() => _voiceNotePath = p),
                        primaryColor: _purple,
                        borderColor: _borderColor,
                        textColor: Colors.black,
                      ),

                      const SizedBox(height: 30),

                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _purple,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        onPressed: _submit,
                        child: Text(
                          'Save Skin Record',
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
