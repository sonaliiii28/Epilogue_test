import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../core/session_manager.dart';
import 'premium_bottom_nav.dart';

// Colors
const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _mutedPurple = Color(0xFF6C648B);
const _lightPurple = Color(0xFFB0A8C8);
const _borderColor = Color(0xFFD4CDDF);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

//  Demo moment model
class _DemoMoment {
  final String id;
  final String content;
  final String authorName;
  final DateTime createdAt;
  final String? photoPath;
  final String? audioPath;

  const _DemoMoment({
    required this.id,
    required this.content,
    required this.authorName,
    required this.createdAt,
    this.photoPath,
    this.audioPath,
  });
}

class MomentsScreen extends StatefulWidget {
  const MomentsScreen({super.key});

  @override
  State<MomentsScreen> createState() => _MomentsScreenState();
}

class _MomentsScreenState extends State<MomentsScreen> {
  final _uuid = const Uuid();
  final _picker = ImagePicker();
  final _audioRecorder = AudioRecorder();

  List<_DemoMoment> _moments = [];
  bool _isLoading = false;

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
  }

  @override
  void dispose() {
    _audioRecorder.dispose();
    super.dispose();
  }

  // Check if current user is family (not medical staff)
  bool get _isFamilyMember {
    final role = SessionManager().currentMember?.role?.toLowerCase() ?? '';
    return ![
      'nurse',
      'doctor',
      'physician',
      'rn',
      'lpn',
      'lvn',
      'medical',
      'hospice nurse',
      'np',
    ].any((r) => role.contains(r));
  }

  Future<String?> _startVoiceRecording() async {
    if (!await _audioRecorder.hasPermission()) return null;
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/moment_voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
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

  void _showAddMomentSheet() {
    if (!_isFamilyMember) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Only family members can add Moments.',
            style: GoogleFonts.nunito(fontSize: 15),
          ),
          backgroundColor: _deepPurple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );
      return;
    }

    final contentCtrl = TextEditingController();
    XFile? pickedPhoto;
    bool isRecording = false;
    String? recordedAudioPath;
    bool momentSaved = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => WillPopScope(
          onWillPop: () async {
            if (await _audioRecorder.isRecording()) {
              final path = await _stopVoiceRecording();
              await _deleteAudioFile(path);
            }
            await _deleteAudioFile(recordedAudioPath);
            return true;
          },
          child: Container(
            height: MediaQuery.of(ctx).size.height * 0.88,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFEDE8F5), Color(0xFFDAD4E6)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _borderColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add a Moment',
                        style: GoogleFonts.nunito(
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                          color: _deepPurple,
                        ),
                      ),
                      Text(
                        'Capture something worth keeping.',
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          color: const Color.fromARGB(255, 0, 0, 0),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

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
                        //  Media picker
                        Text(
                          'Add a photo or voice (optional)',
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _mutedPurple,
                          ),
                        ),
                        const SizedBox(height: 10),

                        if (pickedPhoto != null) ...[
                          Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.file(
                                  File(pickedPhoto!.path),
                                  height: 200,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: () => setModal(() {
                                    pickedPhoto = null;
                                  }),
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: const BoxDecoration(
                                      color: Colors.black54,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],

                        if (isRecording || recordedAudioPath != null) ...[
                          Stack(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: _borderColor),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isRecording
                                          ? Icons.mic_rounded
                                          : Icons.mic_none_rounded,
                                      color: _purple,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        isRecording
                                            ? 'Recording voice...'
                                            : 'Voice note attached',
                                        style: GoogleFonts.nunito(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: _deepPurple,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Positioned(
                                top: 8,
                                right: 8,
                                child: GestureDetector(
                                  onTap: isRecording
                                      ? null
                                      : () async {
                                          final toDelete = recordedAudioPath;
                                          setModal(
                                            () => recordedAudioPath = null,
                                          );
                                          await _deleteAudioFile(toDelete);
                                        },
                                  child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color:
                                          (isRecording
                                                  ? Colors.black26
                                                  : Colors.black54)
                                              .withOpacity(1),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                        ],

                        Row(
                          children: [
                            // Camera
                            Expanded(
                              child: _mediaButton(
                                icon: Icons.camera_alt_outlined,
                                label: 'Take Photo',
                                onTap: () async {
                                  final file = await _picker.pickImage(
                                    source: ImageSource.camera,
                                    imageQuality: 85,
                                  );
                                  if (file != null) {
                                    setModal(() {
                                      pickedPhoto = file;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Gallery
                            Expanded(
                              child: _mediaButton(
                                icon: Icons.photo_library_outlined,
                                label: 'Choose Photo',
                                onTap: () async {
                                  final file = await _picker.pickImage(
                                    source: ImageSource.gallery,
                                    imageQuality: 85,
                                  );
                                  if (file != null) {
                                    setModal(() {
                                      pickedPhoto = file;
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Voice
                            Expanded(
                              child: _mediaButton(
                                icon: isRecording
                                    ? Icons.stop_circle_outlined
                                    : Icons.mic_none_rounded,
                                label: isRecording ? 'Stop' : 'Voice',
                                onTap: () async {
                                  if (isRecording) {
                                    final path = await _stopVoiceRecording();
                                    if (!mounted || !ctx.mounted) return;
                                    setModal(() {
                                      isRecording = false;
                                      recordedAudioPath = path;
                                    });
                                    return;
                                  }

                                  final path = await _startVoiceRecording();
                                  if (path == null) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Microphone permission is required to record voice.',
                                          style: GoogleFonts.nunito(
                                            fontSize: 15,
                                          ),
                                        ),
                                        backgroundColor: _deepPurple,
                                        behavior: SnackBarBehavior.floating,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  if (!mounted || !ctx.mounted) return;
                                  setModal(() {
                                    isRecording = true;
                                    recordedAudioPath = null;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // ‚¬ Text content
                        Text(
                          'Write something (optional)',
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _mutedPurple,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'A memory, a message, a prayer whatever feels right.',
                          style: GoogleFonts.nunito(
                            fontSize: 15,
                            color: _lightPurple,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _borderColor),
                          ),
                          child: TextField(
                            controller: contentCtrl,
                            maxLines: 6,
                            style: GoogleFonts.nunito(
                              fontSize: 16,
                              color: _deepPurple,
                              height: 1.6,
                            ),
                            decoration: InputDecoration(
                              hintText: 'In their own words, or yours...',
                              hintStyle: GoogleFonts.nunito(
                                fontSize: 16,
                                color: const Color(0xFFB8B0CC),
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),

                        const SizedBox(height: 28),

                        // Ã¢â€â‚¬Ã¢â€â‚¬ Save button Ã¢â€â‚¬Ã¢â€â‚¬
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
                            onPressed:
                                (isRecording ||
                                    (contentCtrl.text.trim().isEmpty &&
                                        pickedPhoto == null &&
                                        recordedAudioPath == null))
                                ? null
                                : () {
                                    final member =
                                        SessionManager().currentMember;
                                    setState(() {
                                      _moments.insert(
                                        0,
                                        _DemoMoment(
                                          id: _uuid.v4(),
                                          content: contentCtrl.text.trim(),
                                          authorName: member?.name ?? 'You',
                                          createdAt: DateTime.now(),
                                          photoPath: pickedPhoto?.path,
                                          audioPath: recordedAudioPath,
                                        ),
                                      );
                                    });
                                    momentSaved = true;
                                    _safePopTopRoute();
                                  },
                            child: Text(
                              'Save Moment',
                              style: GoogleFonts.nunito(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
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
      ),
    ).whenComplete(() async {
      if (momentSaved) return;
      if (await _audioRecorder.isRecording()) {
        final path = await _stopVoiceRecording();
        await _deleteAudioFile(path);
      }
      await _deleteAudioFile(recordedAudioPath);
    });
  }

  Widget _mediaButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor),
        ),
        child: Column(
          children: [
            Icon(icon, size: 22, color: _purple),
            const SizedBox(height: 5),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 15,
                color: _mutedPurple,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final moments = _moments;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              //  Header
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
                            'Moments',
                            style: GoogleFonts.nunito(
                              fontSize: 28,
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
                    GestureDetector(
                      onTap: () => context.push('/moments-history'),
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
                          Icons.history,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              //  Moments feed
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(color: _purple),
                      )
                    : moments.isEmpty
                    ? _emptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                        itemCount: moments.length,
                        itemBuilder: (_, i) {
                          final moment = moments[i];
                          return _momentCard(moment);
                        },
                      ),
              ),

              // Ã¢â€â‚¬Ã¢â€â‚¬ Bottom Nav Ã¢â€â‚¬Ã¢â€â‚¬
              const PremiumBottomNav(currentIndex: 0),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),

      // Ã¢â€â‚¬Ã¢â€â‚¬ FAB Ã¢â€â‚¬Ã¢â€â‚¬
      floatingActionButton: _isFamilyMember
          ? Padding(
              padding: const EdgeInsets.only(bottom: 80),
              child: GestureDetector(
                onTap: _showAddMomentSheet,
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
            )
          : null,
    );
  }

  //  Moment card
  Widget _momentCard(_DemoMoment moment) {
    final timeStr = _formatTime(moment.createdAt);
    final initials = moment.authorName
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0] : '')
        .take(2)
        .join()
        .toUpperCase();

    final displayContent = moment.content.isNotEmpty
        ? moment.content
        : (moment.audioPath != null ? 'Voice note' : '');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: _purple.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (moment.photoPath != null)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
              child: Image.file(
                File(moment.photoPath!),
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (displayContent.isNotEmpty) ...[
                  Text(
                    displayContent,
                    style: GoogleFonts.nunito(
                      fontSize: 18,
                      color: const Color.fromARGB(255, 0, 0, 0),
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color.fromARGB(
                          255,
                          0,
                          0,
                          0,
                        ).withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: GoogleFonts.nunito(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: const Color.fromARGB(255, 0, 0, 0),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        moment.authorName,
                        style: GoogleFonts.nunito(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: const Color.fromARGB(255, 0, 0, 0),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      timeStr,
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _mutedPurple,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return DateFormat('MMM d').format(dt);
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFE1DCEA),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(
              child: Icon(Icons.auto_awesome, size: 36, color: _purple),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'No moments added yet',
            style: GoogleFonts.nunito(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: const Color.fromARGB(255, 0, 0, 0),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap "+" to get started',
            textAlign: TextAlign.center,
            style: GoogleFonts.nunito(
              fontSize: 18,
              color: const Color.fromARGB(255, 0, 0, 0),
            ),
          ),
        ],
      ),
    );
  }
}
