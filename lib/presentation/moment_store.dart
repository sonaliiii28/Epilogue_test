import 'package:flutter/foundation.dart';

class MomentEntry {
  final String id;
  final String content;
  final String authorName;
  final DateTime createdAt;
  final String? photoPath;
  final String? audioPath;
  final DateTime? deletedAt;

  const MomentEntry({
    required this.id,
    required this.content,
    required this.authorName,
    required this.createdAt,
    this.photoPath,
    this.audioPath,
    this.deletedAt,
  });

  MomentEntry copyWith({
    String? id,
    String? content,
    String? authorName,
    DateTime? createdAt,
    String? photoPath,
    String? audioPath,
    DateTime? deletedAt,
    bool clearPhotoPath = false,
    bool clearAudioPath = false,
  }) {
    return MomentEntry(
      id: id ?? this.id,
      content: content ?? this.content,
      authorName: authorName ?? this.authorName,
      createdAt: createdAt ?? this.createdAt,
      photoPath: clearPhotoPath ? null : (photoPath ?? this.photoPath),
      audioPath: clearAudioPath ? null : (audioPath ?? this.audioPath),
      deletedAt: deletedAt ?? this.deletedAt,
    );
  }
}

final ValueNotifier<List<MomentEntry>> momentEntriesNotifier =
    ValueNotifier<List<MomentEntry>>(<MomentEntry>[]);

