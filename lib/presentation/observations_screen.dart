import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/session_manager.dart';
import '../core/supabase_service.dart';
import '../domain/models.dart';
import 'premium_bottom_nav.dart';

const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _mutedPurple = Color(0xFF6C648B);
const _lightPurple = Color(0xFFB0A8C8);
const _borderColor = Color(0xFFD4CDDF);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

class ObservationsScreen extends StatefulWidget {
  const ObservationsScreen({super.key});

  @override
  State<ObservationsScreen> createState() => _ObservationsScreenState();
}

class _ObservationsScreenState extends State<ObservationsScreen> {
  final _service = SupabaseService();
  final _uuid = const Uuid();
  final _picker = ImagePicker();
  final _audioRecorder = AudioRecorder();
  final _audioPlayer = AudioPlayer();
  List<Observation> _notes = [];
  bool _isLoading = true;
  String? _playingAudioPath;
  StreamSubscription<void>? _playerCompleteSubscription;
  Set<String> _locallyHiddenNoteIds = <String>{};

  void _safePopTopRoute() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) {
      Navigator.of(context).pop();
    }
  }

  @override
  void initState() {
    super.initState();
    _playerCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _playingAudioPath = null);
    });
    _init();
  }

  Future<void> _init() async {
    await _loadLocallyHiddenIds();
    await _loadNotes();
  }

  String _hiddenIdsKey(String careTeamId) =>
      'observations_hidden_ids:$careTeamId';

  Future<void> _loadLocallyHiddenIds() async {
    final careTeamId = SessionManager().currentCareTeam?.id;
    if (careTeamId == null) return;
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_hiddenIdsKey(careTeamId)) ?? const [];
    _locallyHiddenNoteIds = list.toSet();
  }

  Future<void> _hideNoteLocally(String noteId) async {
    final careTeamId = SessionManager().currentCareTeam?.id;
    if (careTeamId == null) return;
    final prefs = await SharedPreferences.getInstance();
    _locallyHiddenNoteIds = {..._locallyHiddenNoteIds, noteId};
    await prefs.setStringList(
      _hiddenIdsKey(careTeamId),
      _locallyHiddenNoteIds.toList(),
    );
  }

  @override
  void dispose() {
    _playerCompleteSubscription?.cancel();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  Future<void> _loadNotes() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final teamId = SessionManager().currentCareTeam?.id;
      if (teamId == null) return;
      final result = await _service.getObservations(teamId);
      final visible = result
          .where((n) => n.deletedAt == null)
          .where((n) => !_locallyHiddenNoteIds.contains(n.id))
          .toList();

      visible.sort((a, b) {
        final aTime = a.createdAt ?? DateTime(2000);
        final bTime = b.createdAt ?? DateTime(2000);
        return bTime.compareTo(aTime);
      });
      if (mounted) setState(() => _notes = visible);
    } catch (e) {
      debugPrint('Error loading notes: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _confirmDeleteNote(Observation note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFF0EDF6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Note?',
          style: GoogleFonts.nunito(
            fontSize: 22,
            fontWeight: FontWeight.w600,
            color: _deepPurple,
          ),
        ),
        content: Text(
          'This will remove the note from your list, but it will remain in History.',
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

    if (confirmed != true) return;

    try {
      await _service.archiveObservation(note.id);
    } catch (_) {
      // Fallback if the backend doesn't have a deleted_at column yet.
      await _hideNoteLocally(note.id);
    }

    if (!mounted) return;
    _loadNotes();
  }

  Future<void> _showEditNoteModal(Observation note) async {
    if (note.category != 'note') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Editing is available for text notes only.',
            style: GoogleFonts.nunito(fontWeight: FontWeight.w600),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final ctrl = TextEditingController(text: (note.content ?? '').trim());
    const maxChars = 200;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                'Edit Note',
                style: GoogleFonts.nunito(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: const Color.fromARGB(255, 0, 0, 0),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _borderColor),
                ),
                child: TextField(
                  controller: ctrl,
                  maxLength: maxChars,
                  maxLines: 5,
                  style: GoogleFonts.nunito(fontSize: 18, color: Colors.black),
                  onChanged: (_) => setModal(() {}),
                  decoration: InputDecoration(
                    hintText: 'Update your note',
                    hintStyle: GoogleFonts.nunito(
                      fontSize: 18,
                      color: const Color.fromARGB(255, 0, 0, 0),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${ctrl.text.length}/$maxChars',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    color: ctrl.text.length > 180
                        ? Colors.red.shade400
                        : _mutedPurple,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B5B8E),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  onPressed: ctrl.text.trim().isEmpty
                      ? null
                      : () async {
                          final updated = Observation(
                            id: note.id,
                            careTeamId: note.careTeamId,
                            content: ctrl.text.trim(),
                            category: note.category,
                            createdAt: note.createdAt,
                            createdByMemberId: note.createdByMemberId,
                            createdByMemberName: note.createdByMemberName,
                            deletedAt: note.deletedAt,
                          );

                          await _service.updateObservation(updated);
                          if (!mounted) return;
                          _safePopTopRoute();
                          _loadNotes();
                        },
                  child: Text(
                    'Save Changes',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
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
    );
  }

  Future<String?> _startVoiceRecording() async {
    if (!await _audioRecorder.hasPermission()) return null;
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _audioRecorder.start(
      RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    return path;
  }

  Future<String?> _stopVoiceRecording() async {
    return _audioRecorder.stop();
  }

  Future<void> _deleteAudioFile(String? path) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> _toggleAudioPlayback(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Voice note file is unavailable on this device.',
            style: GoogleFonts.nunito(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_playingAudioPath == path) {
      await _audioPlayer.stop();
      if (!mounted) return;
      setState(() => _playingAudioPath = null);
      return;
    }

    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(path));
    if (!mounted) return;
    setState(() => _playingAudioPath = path);
  }

  Future<void> _stopPlaybackForPath(String? path) async {
    if (path == null || _playingAudioPath != path) return;
    await _audioPlayer.stop();
    if (!mounted) return;
    setState(() => _playingAudioPath = null);
  }

  void _showAddNoteModal() {
    final ctrl = TextEditingController();
    const maxChars = 200;
    const maxVoiceNoteDuration = Duration(minutes: 2);
    String inputMode = 'text';
    XFile? pickedPhoto;
    bool isRecording = false;
    String? recordedAudioPath;
    bool noteSaved = false;
    Timer? autoStopTimer;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
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
                'Add Note',
                style: GoogleFonts.nunito(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: const Color.fromARGB(255, 0, 0, 0),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Notes are saved permanently. You can edit or remove them later.',
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  color: const Color.fromARGB(255, 3, 3, 3),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _modeButton(
                      icon: Icons.edit_outlined,
                      label: 'Text',
                      selected: inputMode == 'text',
                      onTap: () async {
                        autoStopTimer?.cancel();
                        if (isRecording) {
                          final path = await _stopVoiceRecording();
                          await _deleteAudioFile(path ?? recordedAudioPath);
                        }
                        await _stopPlaybackForPath(recordedAudioPath);
                        await _deleteAudioFile(recordedAudioPath);
                        if (!mounted || !ctx.mounted) return;
                        setModal(() {
                          inputMode = 'text';
                          isRecording = false;
                          recordedAudioPath = null;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _modeButton(
                      icon: Icons.mic_none_rounded,
                      label: 'Voice',
                      selected: inputMode == 'voice',
                      onTap: () => setModal(() => inputMode = 'voice'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _modeButton(
                      icon: Icons.photo_camera_back_outlined,
                      label: 'Photo',
                      selected: inputMode == 'photo',
                      onTap: () async {
                        autoStopTimer?.cancel();
                        if (isRecording) {
                          final path = await _stopVoiceRecording();
                          await _deleteAudioFile(path ?? recordedAudioPath);
                        }
                        await _stopPlaybackForPath(recordedAudioPath);
                        await _deleteAudioFile(recordedAudioPath);
                        if (!mounted || !ctx.mounted) return;
                        setModal(() {
                          inputMode = 'photo';
                          isRecording = false;
                          recordedAudioPath = null;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (inputMode == 'text') ...[
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _borderColor),
                  ),
                  child: TextField(
                    controller: ctrl,
                    maxLength: maxChars,
                    maxLines: 5,
                    inputFormatters: [
                      TextInputFormatter.withFunction((oldValue, newValue) {
                        final text = newValue.text;
                        if (text.isEmpty) return newValue;
                        final firstChar = text[0].toUpperCase();
                        final updatedText = '$firstChar${text.substring(1)}';
                        if (updatedText == text) return newValue;
                        return TextEditingValue(
                          text: updatedText,
                          selection: newValue.selection,
                          composing: newValue.composing,
                        );
                      }),
                    ],
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      color: Colors.black,
                    ),
                    onChanged: (_) => setModal(() {}),
                    decoration: InputDecoration(
                      hintText: 'What would you like to note?',
                      hintStyle: GoogleFonts.nunito(
                        fontSize: 18,
                        color: const Color.fromARGB(255, 0, 0, 0),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(16),
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    '${ctrl.text.length}/$maxChars',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      color: ctrl.text.length > 180
                          ? Colors.red.shade400
                          : _mutedPurple,
                    ),
                  ),
                ),
              ],
              if (inputMode == 'voice') ...[
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
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isRecording
                              ? Colors.red.withOpacity(0.14)
                              : _purple.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          isRecording
                              ? Icons.stop_rounded
                              : Icons.mic_none_rounded,
                          color: isRecording ? Colors.red.shade600 : _purple,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isRecording
                            ? 'Recording in progress'
                            : recordedAudioPath != null
                            ? 'Voice note ready to save'
                            : 'Record a voice note',
                        style: GoogleFonts.nunito(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: const Color.fromARGB(255, 0, 0, 0),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        isRecording
                            ? 'Tap stop when you are done. Maximum 2 minutes.'
                            : recordedAudioPath != null
                            ? 'You can save it now or record again.'
                            : 'Tap start to record with the microphone.',
                        style: GoogleFonts.nunito(
                          fontSize: 15,
                          color: const Color.fromARGB(255, 31, 31, 31),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isRecording
                                ? Colors.red.shade600
                                : _purple,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: () async {
                            if (isRecording) {
                              autoStopTimer?.cancel();
                              final path = await _stopVoiceRecording();
                              if (!mounted || !ctx.mounted) return;
                              setModal(() {
                                isRecording = false;
                                recordedAudioPath = path ?? recordedAudioPath;
                              });
                              return;
                            }

                            if (recordedAudioPath != null) {
                              await _deleteAudioFile(recordedAudioPath);
                            }
                            final path = await _startVoiceRecording();
                            if (path == null) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Microphone permission is required to record.',
                                    style: GoogleFonts.nunito(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  backgroundColor: Colors.red.shade700,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              return;
                            }
                            autoStopTimer?.cancel();
                            autoStopTimer = Timer(
                              maxVoiceNoteDuration,
                              () async {
                                if (!await _audioRecorder.isRecording()) return;
                                final path = await _stopVoiceRecording();
                                if (!mounted || !ctx.mounted) return;
                                setModal(() {
                                  isRecording = false;
                                  recordedAudioPath = path ?? recordedAudioPath;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Voice notes are limited to 2 minutes.',
                                      style: GoogleFonts.nunito(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              },
                            );
                            setModal(() {
                              isRecording = true;
                              recordedAudioPath = path;
                            });
                          },
                          icon: Icon(
                            isRecording
                                ? Icons.stop_circle_outlined
                                : Icons.fiber_manual_record_rounded,
                          ),
                          label: Text(
                            isRecording ? 'Stop Recording' : 'Start Recording',
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      if (recordedAudioPath != null && !isRecording) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await _toggleAudioPlayback(recordedAudioPath!);
                            if (!mounted || !ctx.mounted) return;
                            setModal(() {});
                          },
                          icon: Icon(
                            _playingAudioPath == recordedAudioPath
                                ? Icons.stop_rounded
                                : Icons.play_arrow_rounded,
                            color: _deepPurple,
                          ),
                          label: Text(
                            _playingAudioPath == recordedAudioPath
                                ? 'Stop Playback'
                                : 'Play Recording',
                            style: GoogleFonts.nunito(
                              color: const Color.fromARGB(255, 0, 0, 0),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _borderColor),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              if (inputMode == 'photo') ...[
                if (pickedPhoto != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      File(pickedPhoto!.path),
                      height: 190,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  )
                else
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
                          'Attach a photo note',
                          style: GoogleFonts.nunito(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: const Color.fromARGB(255, 0, 0, 0),
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
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          final file = await _picker.pickImage(
                            source: ImageSource.camera,
                            imageQuality: 85,
                          );
                          if (file != null) {
                            setModal(() => pickedPhoto = file);
                          }
                        },
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
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          final file = await _picker.pickImage(
                            source: ImageSource.gallery,
                            imageQuality: 85,
                          );
                          if (file != null) {
                            setModal(() => pickedPhoto = file);
                          }
                        },
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
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6B5B8E),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(32),
                    ),
                  ),
                  onPressed:
                      (inputMode == 'text' && ctrl.text.trim().isEmpty) ||
                          (inputMode == 'photo' && pickedPhoto == null) ||
                          (inputMode == 'voice' &&
                              (isRecording || recordedAudioPath == null))
                      ? null
                      : () async {
                          final member = SessionManager().currentMember;
                          final teamId = SessionManager().currentCareTeam?.id;
                          if (teamId == null) return;
                          final note = Observation(
                            id: _uuid.v4(),
                            careTeamId: teamId,
                            content: inputMode == 'voice'
                                ? recordedAudioPath
                                : inputMode == 'photo'
                                ? pickedPhoto!.path
                                : ctrl.text.trim(),
                            category: inputMode == 'voice'
                                ? 'voice'
                                : inputMode == 'photo'
                                ? 'photo'
                                : 'note',
                            createdAt: DateTime.now(),
                            createdByMemberId: member?.id,
                            createdByMemberName: member?.name,
                          );
                          await _service.addObservation(note);
                          noteSaved = true;
                          if (!mounted) return;
                          _safePopTopRoute();
                          _loadNotes();
                        },
                  child: Text(
                    'Save Note',
                    style: GoogleFonts.nunito(
                      fontSize: 18,
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
    ).whenComplete(() async {
      autoStopTimer?.cancel();
      if (await _audioRecorder.isRecording()) {
        final path = await _stopVoiceRecording();
        await _deleteAudioFile(path ?? recordedAudioPath);
      } else if (!noteSaved) {
        await _deleteAudioFile(recordedAudioPath);
      }
    });
  }

  Map<String, List<Observation>> _groupNotes() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));
    final monthAgo = today.subtract(const Duration(days: 30));

    final groups = <String, List<Observation>>{
      'Today': [],
      'Yesterday': [],
      'This Week': [],
      'This Month': [],
      'Older': [],
    };

    for (final note in _notes) {
      final d = note.createdAt ?? DateTime(2000);
      final noteDay = DateTime(d.year, d.month, d.day);
      if (noteDay == today) {
        groups['Today']!.add(note);
      } else if (noteDay == yesterday) {
        groups['Yesterday']!.add(note);
      } else if (d.isAfter(weekAgo)) {
        groups['This Week']!.add(note);
      } else if (d.isAfter(monthAgo)) {
        groups['This Month']!.add(note);
      } else {
        groups['Older']!.add(note);
      }
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groupNotes();

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
                            'Quick Notes',
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
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: _purple),
                      )
                    : _notes.isEmpty
                    ? _emptyState()
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                        children: [
                          for (final group in groups.entries)
                            if (group.value.isNotEmpty) ...[
                              _groupHeader(group.key),
                              ...group.value.map((n) => _noteCard(n)),
                              const SizedBox(height: 8),
                            ],
                        ],
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
          onTap: _showAddNoteModal,
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

  Widget _groupHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        label,
        style: GoogleFonts.nunito(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: const Color.fromARGB(255, 254, 254, 254),
        ),
      ),
    );
  }

  Widget _noteCard(Observation note) {
    final voicePath = note.content ?? '';
    final isPlaying = voicePath.isNotEmpty && _playingAudioPath == voicePath;

    return ObservationCard(
      note: note,
      isPlaying: isPlaying,
      onToggleAudio: note.category == 'voice' && voicePath.isNotEmpty
          ? () => _toggleAudioPlayback(voicePath)
          : null,
      onHistory: () => context.push('/quick-notes-history'),
      onEdit: () => _showEditNoteModal(note),
      onDelete: () => _confirmDeleteNote(note),
    );
  }

  Widget _modeButton({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? _purple : Colors.white.withOpacity(0.8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? _purple : _borderColor),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: selected ? Colors.white : _deepPurple),
            const SizedBox(height: 6),
            Text(
              label,
              style: GoogleFonts.nunito(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white : _deepPurple,
              ),
            ),
          ],
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
              Icons.description_outlined,
              size: 32,
              color: _purple,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No notes yet',
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
              fontSize: 18,
              color: const Color.fromARGB(255, 5, 5, 5).withOpacity(0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class ObservationCard extends StatefulWidget {
  final Observation note;
  final bool isPlaying;
  final VoidCallback? onToggleAudio;
  final VoidCallback onHistory;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const ObservationCard({
    super.key,
    required this.note,
    required this.isPlaying,
    this.onToggleAudio,
    required this.onHistory,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<ObservationCard> createState() => _ObservationCardState();
}

class _ObservationCardState extends State<ObservationCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final time = note.createdAt != null
        ? DateFormat('h:mm MMM d').format(note.createdAt!)
        : '';
    final isPhotoNote = note.category == 'photo';
    final isVoiceNote = note.category == 'voice';
    final voicePath = note.content ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: _expanded
            ? [
                BoxShadow(
                  color: _purple.withOpacity(0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isPhotoNote || isVoiceNote) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _purple.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isPhotoNote ? 'Photo' : 'Voice',
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _purple,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                note.createdByMemberName ?? 'Unknown',
                style: GoogleFonts.nunito(
                  fontSize: 15,
                  color: Colors.black,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              const SizedBox(width: 8),
              const Icon(Icons.lock_outline, size: 10, color: _lightPurple),
              const SizedBox(width: 3),
              Text(
                time,
                style: GoogleFonts.nunito(fontSize: 16, color: Colors.black),
              ),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 28,
                    color: _mutedPurple.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isPhotoNote && (note.content ?? '').isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.file(
                File(note.content!),
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 120,
                  width: double.infinity,
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: Text(
                    'Photo unavailable',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _mutedPurple,
                    ),
                  ),
                ),
              ),
            ),
          ] else if (isVoiceNote && voicePath.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _purple.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _borderColor),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _purple.withOpacity(0.14),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      onPressed: widget.onToggleAudio,
                      icon: Icon(
                        widget.isPlaying
                            ? Icons.stop_rounded
                            : Icons.play_arrow_rounded,
                        color: _purple,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Voice note',
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _deepPurple,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.isPlaying
                              ? 'Playing...'
                              : 'Tap to play recording',
                          style: GoogleFonts.nunito(
                            fontSize: 14,
                            color: _mutedPurple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Text(
              note.content ?? '',
              style: GoogleFonts.nunito(
                fontSize: 17,
                color: Colors.black,
                height: 1.5,
              ),
            ),

          if (_expanded) ...[
            const SizedBox(height: 14),
            const Divider(color: _borderColor),
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
                    onPressed: widget.onHistory,
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
              ],
            ),
          ],
        ],
      ),
    );
  }
}
