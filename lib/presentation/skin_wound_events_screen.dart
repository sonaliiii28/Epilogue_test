import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../core/note_voice_codec.dart';
import '../core/session_manager.dart';
import '../core/supabase_service.dart';
import '../domain/models.dart';
import 'premium_bottom_nav.dart';
import 'widgets/voice_note_attachment.dart';

const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _lightPurple = Color(0xFFB0A8C8);
const _borderColor = Color(0xFFD4CDDF);
const _cardBg = Color(0xFFF0EDF6);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

class SkinWoundEventsScreen extends StatefulWidget {
  const SkinWoundEventsScreen({super.key});

  @override
  State<SkinWoundEventsScreen> createState() => _SkinWoundEventsScreenState();
}

class _SkinWoundEventsScreenState extends State<SkinWoundEventsScreen> {
  final _service = SupabaseService();
  List<SkinWoundEvent> _events = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final teamId = SessionManager().currentCareTeam?.id;
      if (teamId == null) return;
      final result = await _service.getSkinWoundEvents(teamId);
      final visible = result.where((e) => e.deletedAt == null).toList();
      if (mounted) setState(() => _events = visible);
    } catch (e) {
      debugPrint('Error loading skin records: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _openCreateForm() async {
    await context.push('/skin-wounds/new');
    if (!mounted) return;
    await _loadEvents();
  }

  Future<void> _confirmDeleteEvent(SkinWoundEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
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
          'This will remove the skin record from your list, but it will remain in History.',
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
      await _service.archiveSkinWoundEvent(event.id);
      if (!mounted) return;
      await _loadEvents();
    }
  }

  String _stripLocationFromNotes(String? notes) {
    final decoded = NoteVoiceCodec.decode(notes);
    if (decoded.text.isEmpty) return '';
    return decoded.text
        .split('\n')
        .where((line) => !line.startsWith('Location: '))
        .join('\n')
        .trim();
  }

  String? _extractLocationFromText(String text) {
    final lines = text.split('\n');
    for (final line in lines) {
      if (line.startsWith('Location: ')) {
        final value = line.substring('Location: '.length).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  Future<void> _showEditEventModal(SkinWoundEvent event) async {
    var hasCondition = event.hasSkinCondition;
    final decoded = NoteVoiceCodec.decode(event.notes);
    final conditionCtrl = TextEditingController(
      text: event.skinCondition ?? '',
    );
    final treatmentsCtrl = TextEditingController(
      text: event.treatments.join(', '),
    );
    final locationCtrl = TextEditingController(
      text: _extractLocationFromText(decoded.text) ?? '',
    );
    final notesCtrl = TextEditingController(
      text: _stripLocationFromNotes(event.notes),
    );
    String? voiceNotePath = decoded.audioPath;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => Container(
          height: MediaQuery.of(ctx).size.height * 0.62,
          decoration: const BoxDecoration(
            color: _cardBg,
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
                  'Edit Skin Entry',
                  style: GoogleFonts.nunito(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _deepPurple,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Any skin or wound issues?',
                  style: GoogleFonts.nunito(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _pillChoice(
                      label: 'No',
                      isSelected: hasCondition == false,
                      onTap: () => setModal(() => hasCondition = false),
                    ),
                    _pillChoice(
                      label: 'Yes',
                      isSelected: hasCondition == true,
                      onTap: () => setModal(() => hasCondition = true),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (hasCondition) ...[
                  _textField(label: 'Condition', controller: conditionCtrl),
                  const SizedBox(height: 10),
                  _textField(
                    label: 'Treatments (comma-separated)',
                    controller: treatmentsCtrl,
                  ),
                  const SizedBox(height: 10),
                ],
                _textField(label: 'Location', controller: locationCtrl),
                const SizedBox(height: 10),
                _textField(label: 'Notes', controller: notesCtrl, maxLines: 4),
                const SizedBox(height: 10),
                VoiceNoteAttachment(
                  initialPath: voiceNotePath,
                  onChanged: (p) => setModal(() => voiceNotePath = p),
                  primaryColor: _purple,
                  borderColor: _borderColor,
                  textColor: _deepPurple,
                ),
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
                      final cleanedTreatments = treatmentsCtrl.text
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList();

                      final noteBody = _stripLocationFromNotes(
                        notesCtrl.text,
                      ).trim();

                      final location = locationCtrl.text.trim();
                      final noteParts = <String>[];
                      if (location.isNotEmpty) {
                        noteParts.add('Location: $location');
                      }
                      if (noteBody.isNotEmpty) {
                        noteParts.add(noteBody);
                      }

                      final encodedNotes = NoteVoiceCodec.encode(
                        text: noteParts.join('\n'),
                        audioPath: voiceNotePath,
                      );

                      final updated = SkinWoundEvent(
                        id: event.id,
                        careTeamId: event.careTeamId,
                        hasSkinCondition: hasCondition,
                        skinCondition: hasCondition
                            ? conditionCtrl.text.trim().isEmpty
                                  ? null
                                  : conditionCtrl.text.trim()
                            : null,
                        treatments: hasCondition ? cleanedTreatments : const [],
                        imageUrls: event.imageUrls,
                        notes: encodedNotes,
                        eventTime: event.eventTime,
                        deletedAt: event.deletedAt,
                        createdByMemberId: event.createdByMemberId,
                        createdByMemberName: event.createdByMemberName,
                        editableUntil: event.editableUntil,
                      );

                      await _service.updateSkinWoundEvent(updated);
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

  Widget _pillChoice({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? _purple : Colors.white.withOpacity(0.5),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _purple : _borderColor,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
            color: isSelected ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  Widget _textField({
    required String label,
    required TextEditingController controller,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.nunito(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withOpacity(0.6),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _purple, width: 1.5),
            ),
          ),
        ),
      ],
    );
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
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: _moduleCard(
                        title: 'Symptoms',
                        icon: Icons.monitor_heart_outlined,
                        isActive: false,
                        onTap: () => context.go('/symptoms'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _moduleCard(
                        title: 'Skin & Wounds',
                        icon: Icons.healing_outlined,
                        isActive: true,
                        onTap: () {},
                      ),
                    ),
                  ],
                ),
              ),
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
                        itemBuilder: (_, i) => SkinWoundEventCard(
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
          onTap: _openCreateForm,
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: const Color(0xFF6B5B8E),
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: _purple.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '+',
                  style: GoogleFonts.nunito(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
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
              color: Colors.white.withOpacity(0.4),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.healing_outlined, size: 32, color: _purple),
          ),
          const SizedBox(height: 16),
          Text(
            'No skin records logged',
            style: GoogleFonts.nunito(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "Log" to add a skin or wound record',
            style: GoogleFonts.nunito(
              fontSize: 16,
              color: Colors.black.withOpacity(0.9),
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

class SkinWoundEventCard extends StatefulWidget {
  final SkinWoundEvent event;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const SkinWoundEventCard({
    super.key,
    required this.event,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<SkinWoundEventCard> createState() => _SkinWoundEventCardState();
}

class _SkinWoundEventCardState extends State<SkinWoundEventCard> {
  bool _expanded = false;

  String? _extractLocationFromText(String text) {
    final lines = text.split('\n');
    for (final line in lines) {
      if (line.startsWith('Location: ')) {
        final value = line.substring('Location: '.length).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  String _conditionTitle() {
    if (widget.event.hasSkinCondition == false) return 'No skin issues';
    if (widget.event.skinCondition != null &&
        widget.event.skinCondition!.isNotEmpty) {
      return widget.event.skinCondition!;
    }
    return 'Skin record';
  }

  String _eventTimeValue() {
    return DateFormat('MMM d, yyyy h:mm a').format(widget.event.eventTime);
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
    final decoded = NoteVoiceCodec.decode(event.notes);
    final location = _extractLocationFromText(decoded.text);
    final notes = decoded.text
        .split('\n')
        .where((line) => !line.startsWith('Location: '))
        .join('\n')
        .trim();
    final voiceNotePath = decoded.audioPath;
    final isEditable =
        event.editableUntil != null &&
        DateTime.now().isBefore(event.editableUntil!);

    final chips = <Widget>[];
    if (location != null && location.isNotEmpty) {
      chips.add(_infoChip('Location: $location'));
    }
    for (final treatment in event.treatments) {
      final trimmed = treatment.trim();
      if (trimmed.isEmpty) continue;
      chips.add(_infoChip(trimmed));
    }
    if (event.imageUrls.isNotEmpty) {
      chips.add(_infoChip('Photo attached'));
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderColor),
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
                    color: const Color(0xFF8E7CB1).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.healing_outlined,
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
                        _conditionTitle(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.nunito(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: _deepPurple,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Skin record logged',
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
            if (chips.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 6, children: chips),
            ],
            if (_expanded) ...[
              const SizedBox(height: 16),
              const Divider(color: _borderColor),
              const SizedBox(height: 16),
              if (notes.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _cardBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _borderColor),
                  ),
                  child: Text(
                    notes,
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      color: Colors.black,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (voiceNotePath != null && voiceNotePath.trim().isNotEmpty) ...[
                VoiceNotePlaybackButton(
                  path: voiceNotePath,
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
                      onPressed: () => context.push('/skin-wounds/history'),
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
