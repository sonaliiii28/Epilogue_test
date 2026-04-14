import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceNoteAttachment extends StatefulWidget {
  final String? initialPath;
  final ValueChanged<String?> onChanged;

  final Color primaryColor;
  final Color borderColor;
  final Color textColor;

  final Duration maxDuration;

  const VoiceNoteAttachment({
    super.key,
    required this.initialPath,
    required this.onChanged,
    required this.primaryColor,
    required this.borderColor,
    required this.textColor,
    this.maxDuration = const Duration(minutes: 2),
  });

  @override
  State<VoiceNoteAttachment> createState() => _VoiceNoteAttachmentState();

  static Future<void> deleteLocalFile(String? path) async {
    if (path == null || path.trim().isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}

class _VoiceNoteAttachmentState extends State<VoiceNoteAttachment> {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();

  String? _path;
  bool _isRecording = false;
  String? _playingPath;
  Timer? _autoStopTimer;

  @override
  void initState() {
    super.initState();
    _path = (widget.initialPath ?? '').trim().isEmpty
        ? null
        : widget.initialPath!.trim();

    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _playingPath = null);
    });
  }

  @override
  void dispose() {
    _autoStopTimer?.cancel();
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _showSnack(String message, {Color? backgroundColor}) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.nunito(fontSize: 15)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: backgroundColor,
      ),
    );
  }

  Future<String?> _startRecording() async {
    if (!await _recorder.hasPermission()) return null;

    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );

    return path;
  }

  Future<String?> _stopRecording() async {
    return _recorder.stop();
  }

  Future<void> _stopPlaybackForPath(String? path) async {
    if (path == null) return;
    if (_playingPath != path) return;

    await _player.stop();
    if (!mounted) return;
    setState(() => _playingPath = null);
  }

  Future<void> _togglePlayback(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      await _showSnack(
        'Voice note file is unavailable on this device.',
        backgroundColor: Colors.red.shade700,
      );
      return;
    }

    if (_playingPath == path) {
      await _player.stop();
      if (!mounted) return;
      setState(() => _playingPath = null);
      return;
    }

    await _player.stop();
    await _player.play(DeviceFileSource(path));
    if (!mounted) return;
    setState(() => _playingPath = path);
  }

  Future<void> _clearRecording() async {
    final toDelete = _path;
    await _stopPlaybackForPath(toDelete);
    await VoiceNoteAttachment.deleteLocalFile(toDelete);

    if (!mounted) return;
    setState(() => _path = null);
    widget.onChanged(null);
  }

  Future<void> _onRecordPressed() async {
    if (_isRecording) {
      _autoStopTimer?.cancel();
      final stoppedPath = await _stopRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _path = (stoppedPath ?? _path)?.trim().isEmpty == true
            ? null
            : (stoppedPath ?? _path)?.trim();
      });
      widget.onChanged(_path);
      return;
    }

    // Overwrite existing recording.
    if (_path != null) {
      await _clearRecording();
    }

    final startedPath = await _startRecording();
    if (startedPath == null) {
      await _showSnack(
        'Microphone permission is required to record.',
        backgroundColor: Colors.red.shade700,
      );
      return;
    }

    _autoStopTimer?.cancel();
    _autoStopTimer = Timer(widget.maxDuration, () async {
      if (!await _recorder.isRecording()) return;
      final stoppedPath = await _stopRecording();
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _path = (stoppedPath ?? _path)?.trim().isEmpty == true
            ? null
            : (stoppedPath ?? _path)?.trim();
      });
      widget.onChanged(_path);
      await _showSnack('Voice notes are limited to 2 minutes.');
    });

    if (!mounted) return;
    setState(() {
      _isRecording = true;
      _path = startedPath;
    });
    widget.onChanged(_path);
  }

  @override
  Widget build(BuildContext context) {
    final hasRecording = _path != null && _path!.trim().isNotEmpty;
    final isPlaying = hasRecording && _playingPath == _path;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _isRecording
                      ? Colors.red.withOpacity(0.14)
                      : widget.primaryColor.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _isRecording ? Icons.stop_rounded : Icons.mic_none_rounded,
                  color: _isRecording
                      ? Colors.red.shade600
                      : widget.primaryColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isRecording
                      ? 'Recording… (max 2 minutes)'
                      : hasRecording
                      ? 'Voice note attached'
                      : 'Add a voice note (optional)',
                  style: GoogleFonts.nunito(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: widget.textColor,
                  ),
                ),
              ),
              if (hasRecording && !_isRecording)
                IconButton(
                  onPressed: _clearRecording,
                  tooltip: 'Remove voice note',
                  icon: Icon(Icons.close_rounded, color: widget.textColor),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isRecording
                        ? Colors.red.shade600
                        : widget.primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _onRecordPressed,
                  icon: Icon(
                    _isRecording
                        ? Icons.stop_circle_outlined
                        : Icons.fiber_manual_record_rounded,
                  ),
                  label: Text(
                    _isRecording ? 'Stop Recording' : 'Start Recording',
                    style: GoogleFonts.nunito(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              if (hasRecording && !_isRecording) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: widget.borderColor),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => _togglePlayback(_path!),
                    icon: Icon(
                      isPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                      color: widget.textColor,
                    ),
                    label: Text(
                      isPlaying ? 'Stop' : 'Play',
                      style: GoogleFonts.nunito(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: widget.textColor,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class VoiceNotePlaybackButton extends StatefulWidget {
  final String path;
  final Color borderColor;
  final Color textColor;

  const VoiceNotePlaybackButton({
    super.key,
    required this.path,
    required this.borderColor,
    required this.textColor,
  });

  @override
  State<VoiceNotePlaybackButton> createState() =>
      _VoiceNotePlaybackButtonState();
}

class _VoiceNotePlaybackButtonState extends State<VoiceNotePlaybackButton> {
  final _player = AudioPlayer();
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final file = File(widget.path);
    if (!await file.exists()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Voice note file is unavailable on this device.',
            style: GoogleFonts.nunito(fontSize: 15),
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_playing) {
      await _player.stop();
      if (!mounted) return;
      setState(() => _playing = false);
      return;
    }

    await _player.stop();
    await _player.play(DeviceFileSource(widget.path));
    if (!mounted) return;
    setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: widget.borderColor),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      onPressed: _toggle,
      icon: Icon(
        _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
        color: widget.textColor,
      ),
      label: Text(
        _playing ? 'Stop voice note' : 'Play voice note',
        style: GoogleFonts.nunito(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: widget.textColor,
        ),
      ),
    );
  }
}
