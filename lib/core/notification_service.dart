import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

class AppNotification {
  AppNotification({
    required this.id,
    required this.userProfileId,
    this.channel,
    this.eventType,
    this.title,
    this.body,
    this.status,
    this.sentAt,
    this.readAt,
    this.data,
    this.createdAt,
  });

  final String id;
  final String userProfileId;
  final String? channel;
  final String? eventType;
  final String? title;
  final String? body;
  final String? status;
  final DateTime? sentAt;
  final DateTime? readAt;
  final Map<String, dynamic>? data;
  final DateTime? createdAt;

  bool get isRead => readAt != null;

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  factory AppNotification.fromRow(Map<String, dynamic> row) {
    final mapped = Map<String, dynamic>.from(row);
    final dataRaw = mapped['data'];
    Map<String, dynamic>? data;
    if (dataRaw is Map<String, dynamic>) {
      data = dataRaw;
    } else if (dataRaw is Map) {
      data = Map<String, dynamic>.from(dataRaw);
    }

    return AppNotification(
      id: (mapped['notification_id'] ?? '').toString(),
      userProfileId: (mapped['user_profile_id'] ?? '').toString(),
      channel: mapped['channel']?.toString(),
      eventType: mapped['event_type']?.toString(),
      title: mapped['title']?.toString(),
      body: mapped['body']?.toString(),
      status: mapped['status']?.toString(),
      sentAt: _parseDate(mapped['sent_at']),
      readAt: _parseDate(mapped['read_at']),
      data: data,
      createdAt: _parseDate(mapped['created_at']),
    );
  }
}

class NotificationService {
  NotificationService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  bool _isPrimaryCaregiverRole(String? roleName) {
    final role = (roleName ?? '').trim().toLowerCase();
    if (role.isEmpty) return false;
    return role == 'p1' || role.contains('primary');
  }

  bool _isMedicationOrSymptomEvent(String eventType) {
    final t = eventType.trim().toLowerCase();
    if (t.isEmpty) return false;
    return t == 'dose_logged' ||
        t == 'medication_logged' ||
        t == 'medication_log' ||
        t == 'symptom_logged' ||
        t == 'symptom_log' ||
        t.contains('dose') ||
        t.contains('symptom');
  }

  bool _isMemberJoinEvent(String eventType) {
    final t = eventType.trim().toLowerCase();
    if (t.isEmpty) return false;
    return t == 'member_joined' ||
        t == 'care_team_member_joined' ||
        t.contains('member') && t.contains('join');
  }

  String? _extractRoleName(Map<String, dynamic> memberRow) {
    final embedded = memberRow['role_list'];
    if (embedded is Map) {
      return embedded['name']?.toString();
    }
    return null;
  }

  bool _isPrimaryMember(Map<String, dynamic> memberRow) {
    return memberRow['is_primary'] == true;
  }

  bool _isClinicalRole(String? roleName) {
    final role = (roleName ?? '').trim().toLowerCase();
    if (role.isEmpty) return false;
    return role == 'p5' ||
        role.contains('medical') ||
        role.contains('nurse') ||
        role.contains('clinical');
  }

  bool _isFamilyRole(String? roleName) {
    final role = (roleName ?? '').trim().toLowerCase();
    if (role.isEmpty) return true;
    return role == 'p1' ||
        role == 'p2' ||
        role.contains('family') ||
        role.contains('caregiver');
  }

  Future<List<AppNotification>> getInbox({int limit = 50}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const <AppNotification>[];

    try {
      final rows = await _client
          .from('notification')
          .select(
            'notification_id, user_profile_id, channel, event_type, title, body, status, sent_at, read_at, data, created_at',
          )
          .eq('user_profile_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .cast<Map<String, dynamic>>()
          .map(AppNotification.fromRow)
          .toList();
    } catch (e) {
      debugPrint('[NotificationService][getInbox] $e');
      return const <AppNotification>[];
    }
  }

  Future<void> markRead(String notificationId) async {
    if (notificationId.trim().isEmpty) return;
    try {
      await _client
          .from('notification')
          .update({
            'read_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'read',
          })
          .eq('notification_id', notificationId);
    } catch (e) {
      debugPrint('[NotificationService][markRead] $e');
    }
  }

  Future<Map<String, int>> getUnreadCountsByEventType({
    List<String>? eventTypes,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const <String, int>{};

    try {
      var query = _client
          .from('notification')
          .select('event_type')
          .eq('user_profile_id', userId)
          .isFilter('read_at', null);

      final trimmedTypes = (eventTypes ?? const <String>[])
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (trimmedTypes.isNotEmpty) {
        query = query.inFilter('event_type', trimmedTypes);
      }

      final rows = await query;
      final counts = <String, int>{};
      for (final item in (rows as List)) {
        final row = Map<String, dynamic>.from(item as Map);
        final eventType = row['event_type']?.toString().trim();
        if (eventType == null || eventType.isEmpty) continue;
        counts[eventType] = (counts[eventType] ?? 0) + 1;
      }
      return counts;
    } catch (_) {
      // best-effort
      return const <String, int>{};
    }
  }

  Future<void> markAllReadForEventTypes(List<String> eventTypes) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    final trimmedTypes = eventTypes
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (trimmedTypes.isEmpty) return;

    try {
      await _client
          .from('notification')
          .update({
            'read_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'read',
          })
          .eq('user_profile_id', userId)
          .isFilter('read_at', null)
          .inFilter('event_type', trimmedTypes);
    } catch (_) {
      // best-effort
    }
  }

  Future<void> _insertNotifications(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return;
    // Best-effort insert; let upstream writes succeed even if notifications fail.
    try {
      // Insert in chunks to avoid payload limits.
      const chunkSize = 100;
      for (var i = 0; i < rows.length; i += chunkSize) {
        final chunk = rows.sublist(
          i,
          (i + chunkSize > rows.length) ? rows.length : i + chunkSize,
        );
        await _client.from('notification').insert(chunk);
      }
    } catch (e) {
      debugPrint('[NotificationService][_insertNotifications] $e');
    }
  }

  Future<void> notifyCareSpaceMembers({
    required String careSpaceId,
    required String eventType,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    final actorUserId = _client.auth.currentUser?.id;
    if (actorUserId == null) return;

    List<Map<String, dynamic>> members;
    try {
      // Fetch active members in the care space (DOCX schema).
      final resp = await _client
          .from('care_team_member')
          .select(
            'user_profile_id, is_primary, role_list:role_list_id(name), is_active',
          )
          .eq('care_space_id', careSpaceId)
          .eq('is_active', true);
      members = (resp as List)
          .cast<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
    } catch (e) {
      debugPrint('[NotificationService][notifyCareSpaceMembers][members] $e');
      return;
    }

    Map<String, dynamic>? actorRow;
    for (final m in members) {
      if ((m['user_profile_id']?.toString() ?? '') == actorUserId) {
        actorRow = m;
        break;
      }
    }

    final actorRoleName = actorRow == null ? null : _extractRoleName(actorRow);
    final actorIsClinical = _isClinicalRole(actorRoleName);
    final actorIsPrimary = actorRow == null
        ? _isPrimaryCaregiverRole(actorRoleName)
        : (_isPrimaryMember(actorRow) ||
              _isPrimaryCaregiverRole(actorRoleName));

    final primaryCaregiverIds = members
        .where((m) {
          final roleName = _extractRoleName(m);
          final isPrimary =
              _isPrimaryMember(m) || _isPrimaryCaregiverRole(roleName);
          if (!isPrimary) return false;
          // Primary should generally be a family/caregiver role.
          return _isFamilyRole(roleName) && !_isClinicalRole(roleName);
        })
        .map((m) => (m['user_profile_id'] ?? '').toString())
        .where((id) => id.trim().isNotEmpty)
        .toList();

    final isMedOrSymptom = _isMedicationOrSymptomEvent(eventType);
    final isMemberJoin = _isMemberJoinEvent(eventType);

    final recipients = <String>{};

    if (isMemberJoin) {
      // New member join -> notify primary caregiver(s).
      for (final id in primaryCaregiverIds) {
        if (id != actorUserId) recipients.add(id);
      }
    } else if (isMedOrSymptom) {
      if (actorIsClinical) {
        // Medical team logged med/symptom -> notify primary caregiver(s) only.
        for (final id in primaryCaregiverIds) {
          if (id != actorUserId) recipients.add(id);
        }
      } else {
        // Caregiver logged med/symptom -> notify medical team.
        for (final m in members) {
          final id = (m['user_profile_id'] ?? '').toString();
          if (id.trim().isEmpty || id == actorUserId) continue;
          final roleName = _extractRoleName(m);
          if (_isClinicalRole(roleName)) recipients.add(id);
        }

        // If this is NOT the primary caregiver, also notify primary caregiver(s).
        if (!actorIsPrimary) {
          for (final id in primaryCaregiverIds) {
            if (id != actorUserId) recipients.add(id);
          }
        }
      }
    } else {
      // All other events -> primary caregiver(s) should receive notifications
      // for others' actions, but not for their own.
      for (final id in primaryCaregiverIds) {
        if (id != actorUserId) recipients.add(id);
      }
    }

    // Fallbacks: keep it robust even if role/is_primary isn't set.
    if (recipients.isEmpty) {
      if (!actorIsClinical) {
        // Caregiver action: at least notify clinical team.
        for (final m in members) {
          final id = (m['user_profile_id'] ?? '').toString();
          if (id.trim().isEmpty || id == actorUserId) continue;
          final roleName = _extractRoleName(m);
          if (_isClinicalRole(roleName)) recipients.add(id);
        }
      }
    }

    if (recipients.isEmpty) {
      for (final m in members) {
        final id = (m['user_profile_id'] ?? '').toString();
        if (id.trim().isEmpty || id == actorUserId) continue;
        recipients.add(id);
      }
    }

    final nowUtc = DateTime.now().toUtc().toIso8601String();
    final baseData = <String, dynamic>{
      'care_space_id': careSpaceId,
      'actor_user_profile_id': actorUserId,
      'actor_role': actorRoleName,
      ...(data ?? const <String, dynamic>{}),
    };

    final rows = <Map<String, dynamic>>[];
    for (final recipientId in recipients) {
      rows.add(<String, dynamic>{
        'notification_id': const Uuid().v4(),
        'user_profile_id': recipientId,
        'channel': 'in_app',
        'event_type': eventType,
        'title': title,
        'body': body,
        'status': 'unread',
        'sent_at': nowUtc,
        'data': baseData,
      });
    }

    await _insertNotifications(rows);
  }
}
