class NoteVoicePayload {
  final String text;
  final String? audioPath;

  const NoteVoicePayload({required this.text, this.audioPath});
}

/// Lightweight encoding to store an optional voice-note file path inside an
/// existing `notes` text column without changing the database schema.
///
/// Format:
/// - Plain text when no voice note.
/// - When voice note exists: `<text>\n[[VOICE_NOTE]]:<path>`
class NoteVoiceCodec {
  static const String _marker = '[[VOICE_NOTE]]:';
  static const String _photoMarker = '[[PHOTO]]:';

  static NoteVoicePayload decode(String? raw) {
    final value = (raw ?? '').toString();
    if (value.isEmpty) return const NoteVoicePayload(text: '', audioPath: null);

    final voiceIdx = value.indexOf(_marker);
    final photoIdx = value.indexOf(_photoMarker);
    final indices = <int>[voiceIdx, photoIdx].where((i) => i >= 0).toList();
    if (indices.isEmpty) {
      return NoteVoicePayload(text: value.trim(), audioPath: null);
    }

    final firstIdx = indices.reduce((a, b) => a < b ? a : b);
    final before = value.substring(0, firstIdx).trimRight();
    String? audioPath;
    if (voiceIdx >= 0) {
      final after = value.substring(voiceIdx + _marker.length).trim();
      if (after.isNotEmpty) {
        final newline = after.indexOf('\n');
        final candidate = (newline >= 0 ? after.substring(0, newline) : after)
            .trim();
        audioPath = candidate.isEmpty ? null : candidate;
      }
    }

    return NoteVoicePayload(text: before.trim(), audioPath: audioPath);
  }

  static String? encode({required String text, required String? audioPath}) {
    final cleanedText = text.trim();
    final cleanedPath = audioPath?.trim();

    if (cleanedPath == null || cleanedPath.isEmpty) {
      return cleanedText.isEmpty ? null : cleanedText;
    }

    if (cleanedText.isEmpty) {
      return '$_marker$cleanedPath';
    }

    return '$cleanedText\n$_marker$cleanedPath';
  }

  static String? encodeWithPhoto({
    required String text,
    required String? audioPath,
    required String? photoPath,
  }) {
    final cleanedText = text.trim();
    final cleanedAudio = audioPath?.trim();
    final cleanedPhoto = photoPath?.trim();

    final hasAudio = cleanedAudio != null && cleanedAudio.isNotEmpty;
    final hasPhoto = cleanedPhoto != null && cleanedPhoto.isNotEmpty;

    if (!hasAudio && !hasPhoto) {
      return cleanedText.isEmpty ? null : cleanedText;
    }

    final parts = <String>[];
    if (cleanedText.isNotEmpty) parts.add(cleanedText);
    if (hasAudio) parts.add('$_marker$cleanedAudio');
    if (hasPhoto) parts.add('$_photoMarker$cleanedPhoto');
    return parts.join('\n');
  }

  static String stripFromText(String? raw) => decode(raw).text;

  static String? extractAudioPath(String? raw) => decode(raw).audioPath;

  static String? extractPhotoPath(String? raw) {
    final value = (raw ?? '').toString();
    if (value.isEmpty) return null;

    final idx = value.indexOf(_photoMarker);
    if (idx < 0) return null;
    final after = value.substring(idx + _photoMarker.length).trim();
    if (after.isEmpty) return null;
    final newline = after.indexOf('\n');
    if (newline >= 0) return after.substring(0, newline).trim();
    return after;
  }
}
