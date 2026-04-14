import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models.dart';
import 'dart:convert';
import 'dart:math';
import 'package:uuid/uuid.dart';
import 'package:flutter/foundation.dart';

import 'notification_service.dart';

class CareTeamMembership {
  final Member member;
  final CareTeam careTeam;

  CareTeamMembership({required this.member, required this.careTeam});
}

class SupabaseService {
  static final SupabaseClient _client = Supabase.instance.client;

  final NotificationService _notifications = NotificationService();

  static bool? _docxSchemaCache;
  static bool? _docxCalendarSchemaCache;

  SupabaseClient get client => _client;

  Future<bool> isDocxSchema() => _isDocxSchema();
  Future<bool> isDocxCalendarSchema() => _isDocxCalendarSchema();

  bool _roleCanBePrimaryCaregiver(String? role) {
    final normalized = (role ?? '').trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return normalized == 'family' ||
        normalized == 'caregiver' ||
        normalized == 'primary_caregiver' ||
        normalized == 'primary caregiver';
  }

  Future<bool?> _getMyPrimaryFlag({
    required String careSpaceId,
    required String uid,
  }) async {
    try {
      final row = await _client
          .from('care_team_member')
          .select('is_primary')
          .eq('care_space_id', careSpaceId)
          .eq('user_profile_id', uid)
          .limit(1)
          .maybeSingle();
      if (row == null) return null;
      return row['is_primary'] == true;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _tryClaimPrimaryCaregiver({
    required String careSpaceId,
    required String uid,
    required bool canBePrimary,
  }) async {
    if (!canBePrimary) return false;

    try {
      final existing = await _client
          .from('care_team_member')
          .select('user_profile_id')
          .eq('care_space_id', careSpaceId)
          .eq('is_primary', true)
          .eq('is_active', true)
          .limit(1)
          .maybeSingle();

      final existingUid = (existing?['user_profile_id'] ?? '')
          .toString()
          .trim();
      final canClaim = existingUid.isEmpty || existingUid == uid;
      if (!canClaim) return false;

      await _client
          .from('care_team_member')
          .update({'is_primary': true})
          .eq('care_space_id', careSpaceId)
          .eq('user_profile_id', uid);
      return true;
    } catch (e) {
      debugPrint('Primary caregiver claim failed: $e');
      return false;
    }
  }

  bool _isRelationMissing(Object error) {
    if (error is PostgrestException) {
      final code = (error.code ?? '').toUpperCase();
      if (code == '42P01') return true; // undefined_table
      final msg = error.message.toLowerCase();
      if (msg.contains('does not exist') && msg.contains('relation'))
        return true;
    }

    final msg = error.toString().toLowerCase();
    return msg.contains('does not exist') && msg.contains('relation');
  }

  bool _isMissingColumn(Object error) {
    if (error is! PostgrestException) return false;
    return (error.code ?? '').toUpperCase() == 'PGRST204';
  }

  Future<bool> _isDocxSchema() async {
    final cached = _docxSchemaCache;
    if (cached != null) return cached;

    try {
      await _client.from('care_space').select('care_space_id').limit(1);
      _docxSchemaCache = true;
    } catch (e) {
      if (_isRelationMissing(e)) {
        _docxSchemaCache = false;
      } else {
        rethrow;
      }
    }

    return _docxSchemaCache ?? false;
  }

  Future<bool> _isDocxCalendarSchema() async {
    final cached = _docxCalendarSchemaCache;
    if (cached != null) return cached;

    try {
      await _client.from('calendar_events').select('scheduled_at').limit(1);
      _docxCalendarSchemaCache = true;
    } catch (e) {
      if (_isRelationMissing(e) || _isMissingColumn(e)) {
        _docxCalendarSchemaCache = false;
      } else {
        rethrow;
      }
    }

    return _docxCalendarSchemaCache ?? false;
  }

  Map<String, dynamic>? _tryParseJsonObject(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    return null;
  }

  List<String>? _jsonTextArray(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString()).toList();
    }
    return null;
  }

  EventType _eventTypeFromString(String raw) {
    final trimmed = raw.trim();
    for (final value in EventType.values) {
      if (value.name == trimmed) return value;
    }
    return EventType.symptom;
  }

  Future<void> ensureSignedInWithEmailPassword({
    required String email,
    required String password,
  }) async {
    final trimmedEmail = email.trim();
    final trimmedPassword = password.trim();
    if (trimmedEmail.isEmpty || trimmedPassword.isEmpty) {
      throw Exception('Email and password are required');
    }

    if (_client.auth.currentUser != null) return;

    try {
      final res = await _client.auth.signUp(
        email: trimmedEmail,
        password: trimmedPassword,
      );
      // Some Supabase setups require email confirmation and will return a user
      // without an active session. Only return early if we are actually signed in.
      if (res.session != null || _client.auth.currentUser != null) return;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      final code = (e.code ?? '').toLowerCase();
      final alreadyExists =
          code.contains('user_already_exists') ||
          msg.contains('already registered') ||
          msg.contains('already exists');
      if (!alreadyExists) {
        rethrow;
      }
    }

    await _client.auth.signInWithPassword(
      email: trimmedEmail,
      password: trimmedPassword,
    );
  }

  Future<void> _ensureUserProfile({required String fullName}) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) {
      throw Exception('Not signed in');
    }

    final payload = <String, dynamic>{
      'user_profile_id': uid,
      'full_name': fullName.trim().isEmpty ? 'User' : fullName.trim(),
    };

    await _client
        .from('user_profile')
        .upsert(payload, onConflict: 'user_profile_id');
  }

  String? _missingColumnFromSchemaCacheError(Object error) {
    if (error is! PostgrestException) return null;
    if ((error.code ?? '').toUpperCase() != 'PGRST204') return null;

    final match = RegExp(
      r"Could not find the '([^']+)' column",
    ).firstMatch(error.message);
    return match?.group(1);
  }

  Future<T> _retryWithoutUnknownColumns<T>(
    Future<T> Function() request,
    Map<String, dynamic> payload, {
    int maxStrips = 25,
  }) async {
    var remainingStrips = maxStrips;
    while (true) {
      try {
        return await request();
      } catch (e) {
        final missing = _missingColumnFromSchemaCacheError(e);
        if (missing == null || remainingStrips <= 0) {
          rethrow;
        }

        if (!payload.containsKey(missing)) {
          rethrow;
        }

        payload.remove(missing);
        remainingStrips--;
        debugPrint(
          "Supabase schema mismatch: removed '$missing' from payload and retrying.",
        );
      }
    }
  }

  void _removeNullValues(Map<String, dynamic> payload) {
    payload.removeWhere((_, value) => value == null);
  }

  String get passwordResetRedirectTo {
    if (kIsWeb) {
      return Uri.base.resolve('/reset-password').toString();
    }
    return 'com.example.epilouge://login-callback/reset-password';
  }

  Future<bool> isRegisteredEmail(String email) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) return false;

    if (await _isDocxSchema()) return true;

    try {
      final response = await _client
          .from('members')
          .select('id')
          .eq('email', trimmedEmail)
          .limit(1);
      return (response as List).isNotEmpty;
    } catch (e) {
      // DOCX schema doesn't expose auth.users emails; let auth handle existence.
      if (_isRelationMissing(e)) return true;
      rethrow;
    }
  }

  // Care Teams
  Future<CareTeam?> getCareTeam(String id) async {
    if (await _isDocxSchema()) {
      final response = await _client
          .from('care_space')
          .select(
            'care_space_id, full_name, agency_id, address_line1, created_at, homecare_provider_id',
          )
          .eq('care_space_id', id)
          .maybeSingle();
      if (response == null) return null;

      final raw = (response as Map).cast<String, dynamic>();
      final hospiceId = (raw['agency_id'] ?? '').toString().trim();
      String? hospiceName;
      if (hospiceId.isNotEmpty) {
        try {
          final hospice = await _client
              .from('hospice_agency_list')
              .select('name, city, state')
              .eq('agency_id', hospiceId)
              .maybeSingle();
          if (hospice != null) {
            final h = (hospice as Map).cast<String, dynamic>();
            final n = (h['name'] ?? '').toString().trim();
            final c = (h['city'] ?? '').toString().trim();
            final s = (h['state'] ?? '').toString().trim();
            hospiceName = [n, c, s].where((p) => p.isNotEmpty).join(' ');
            if (hospiceName.trim().isEmpty) hospiceName = null;
          }
        } catch (_) {
          // Best-effort only.
        }
      }

      final address = <String>[];
      for (final key in ['address_line1']) {
        final value = (raw[key] ?? '').toString().trim();
        if (value.isNotEmpty) address.add(value);
      }
      final patientAddress = address.join(', ').trim();

      return CareTeam(
        id: (raw['care_space_id'] ?? id).toString(),
        patientFirstName: (raw['full_name'] ?? '').toString().trim().isEmpty
            ? null
            : (raw['full_name'] ?? '').toString().trim(),
        hospiceOrgId: hospiceId.isEmpty ? null : hospiceId,
        hospiceName: hospiceName,
        patientAddress: patientAddress.isEmpty ? null : patientAddress,
        createdAt: raw['created_at'] is String
            ? DateTime.tryParse(raw['created_at'] as String)
            : raw['created_at'] as DateTime?,
      );
    }

    final response = await _client
        .from('care_teams')
        .select()
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return CareTeam.fromJson(response);
  }

  Future<CareTeam> updateCareTeamPatientDetails({
    required String careTeamId,
    String? patientName,
    String? primaryCaregiverName,
    String? primaryCaregiverEmail,
    String? hospiceName,
    String? patientAddress,
  }) async {
    final payload = <String, dynamic>{
      'patient_first_name': (patientName ?? '').trim().isEmpty
          ? null
          : patientName!.trim(),
      'primary_caregiver_name': (primaryCaregiverName ?? '').trim().isEmpty
          ? null
          : primaryCaregiverName!.trim(),
      'primary_caregiver_email': (primaryCaregiverEmail ?? '').trim().isEmpty
          ? null
          : primaryCaregiverEmail!.trim(),
      'hospice_name': (hospiceName ?? '').trim().isEmpty
          ? null
          : hospiceName!.trim(),
      'patient_address': (patientAddress ?? '').trim().isEmpty
          ? null
          : patientAddress!.trim(),
    };

    _removeNullValues(payload);

    final response = await _retryWithoutUnknownColumns(
      () => _client
          .from('care_teams')
          .update(payload)
          .eq('id', careTeamId)
          .select()
          .single(),
      payload,
    );

    return CareTeam.fromJson(response);
  }

  Future<void> createCareTeam(
    CareTeam team, {
    String? homeCareProviderId,
  }) async {
    if (await _isDocxSchema()) {
      final fullName = (team.patientFirstName ?? '').trim().isEmpty
          ? 'Patient'
          : team.patientFirstName!.trim();
      final payload = <String, dynamic>{
        'care_space_id': team.id,
        'full_name': fullName,
        'agency_id': (team.hospiceOrgId ?? '').trim().isEmpty
            ? null
            : team.hospiceOrgId,
        'homecare_provider_id': (homeCareProviderId ?? '').trim().isEmpty
            ? null
            : homeCareProviderId,
        'address_line1': (team.patientAddress ?? '').trim().isEmpty
            ? null
            : team.patientAddress,
      };
      _removeNullValues(payload);

      await _client.from('care_space').insert(payload);
      return;
    }

    final joinCode = (100000 + Random().nextInt(900000)).toString();

    final data = team.toJson();
    data['join_code'] = joinCode;
    _removeNullValues(data);

    bool isTransientNetworkError(Object error) {
      final msg = error.toString().toLowerCase();
      return msg.contains('failed host lookup') ||
          msg.contains('socketexception') ||
          msg.contains('network is unreachable') ||
          msg.contains('connection timed out') ||
          msg.contains('timed out');
    }

    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final response = await _retryWithoutUnknownColumns(
          () => _client.from('care_teams').insert(data).select(),
          data,
        );
        debugPrint('CARE TEAM INSERT SUCCESS: $response');
        return;
      } catch (e) {
        debugPrint('CARE TEAM INSERT ERROR (attempt ${attempt + 1}/3): $e');
        final isLastAttempt = attempt == 2;
        if (!isTransientNetworkError(e) || isLastAttempt) {
          rethrow;
        }
        await Future.delayed(Duration(milliseconds: 600 * (attempt + 1)));
      }
    }
  }

  // Members
  Future<List<Member>> getMembers(String careTeamId) async {
    if (await _isDocxSchema()) {
      final response = await _client
          .from('care_team_member')
          .select(
            'care_space_id, user_profile_id, is_primary, is_active, user_profile!care_team_member_user_profile_id_fkey(full_name)',
          )
          .eq('care_space_id', careTeamId);

      final rows = (response as List).cast<Map<String, dynamic>>();
      final currentUid = _client.auth.currentUser?.id;
      final currentEmail = _client.auth.currentUser?.email?.trim();
      return rows.map((row) {
        final profile = row['user_profile'];
        final fullName = profile is Map
            ? (profile['full_name'] ?? '').toString().trim()
            : '';
        final uid = (row['user_profile_id'] ?? '').toString();
        final email = uid == currentUid && (currentEmail ?? '').isNotEmpty
            ? currentEmail!
            : 'unknown@example.com';

        return Member(
          id: uid,
          careTeamId: (row['care_space_id'] ?? '').toString(),
          name: fullName.isEmpty ? 'Member' : fullName,
          email: email,
          role: 'family',
          isAdmin: row['is_primary'] == true,
        );
      }).toList();
    }

    final response = await _client
        .from('members')
        .select()
        .eq('care_team_id', careTeamId);
    return (response as List).map((m) => Member.fromJson(m)).toList();
  }

  Future<void> addMember(Member member) async {
    if (await _isDocxSchema()) {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        throw Exception('Not signed in');
      }

      final careSpaceId = (member.careTeamId ?? '').trim();
      if (careSpaceId.isEmpty) {
        throw Exception('careTeamId is required');
      }
      if (member.id != uid) {
        throw Exception(
          'Adding other members requires an invite flow; only self-membership is supported here.',
        );
      }

      await _ensureUserProfile(fullName: member.name);

      final canBePrimary = _roleCanBePrimaryCaregiver(member.role);
      final existingSelfPrimary = await _getMyPrimaryFlag(
        careSpaceId: careSpaceId,
        uid: uid,
      );

      final payload = <String, dynamic>{
        'care_space_id': careSpaceId,
        'user_profile_id': uid,
        // Never allow clients to arbitrarily set primary caregiver.
        // If the user is already primary, preserve it; otherwise default false.
        'is_primary': existingSelfPrimary == true,
        'is_active': true,
      };

      await _client
          .from('care_team_member')
          .upsert(payload, onConflict: 'care_space_id,user_profile_id');

      // Best-effort: if there is no primary caregiver yet, let the first
      // family/caregiver member claim it (P1 should be this account).
      await _tryClaimPrimaryCaregiver(
        careSpaceId: careSpaceId,
        uid: uid,
        canBePrimary: canBePrimary,
      );

      await _notifications.notifyCareSpaceMembers(
        careSpaceId: careSpaceId,
        eventType: 'member_joined',
        title: 'New member joined',
        body: 'A new member joined the care team.',
        data: {'joined_user_profile_id': uid},
      );
      return;
    }

    final data = member.toJson();
    _removeNullValues(data);
    try {
      await _client.from('members').insert(data);
    } on PostgrestException catch (e) {
      final code = (e.code ?? '').toUpperCase();
      final msg = e.message.toLowerCase();
      if (code == '42P17' && msg.contains('infinite recursion')) {
        throw Exception(
          'Supabase RLS policy recursion on table "members". '
          'Fix this in Supabase SQL Editor using backend/supabase_cloud_members_rls_fix.sql. '
          'Original error: ${e.message}',
        );
      }
      rethrow;
    }
  }

  Future<Member> ensureMemberForTeam({
    required CareTeam careTeam,
    required String email,
    required String role,
  }) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      throw Exception('Email is required');
    }

    if (await _isDocxSchema()) {
      final uid = _client.auth.currentUser?.id;
      if (uid == null) {
        throw Exception('Please sign in to join this care space');
      }

      final now = DateTime.now();
      final derivedName = trimmedEmail.contains('@')
          ? trimmedEmail.split('@').first
          : trimmedEmail;
      final memberName = derivedName.isEmpty ? 'Member' : derivedName;

      await _ensureUserProfile(fullName: memberName);

      final canBePrimary = _roleCanBePrimaryCaregiver(role);
      final existingSelfPrimary = await _getMyPrimaryFlag(
        careSpaceId: careTeam.id,
        uid: uid,
      );

      await _client.from('care_team_member').upsert({
        'care_space_id': careTeam.id,
        'user_profile_id': uid,
        'is_primary': existingSelfPrimary == true,
        'is_active': true,
      }, onConflict: 'care_space_id,user_profile_id');

      final isPrimary = await _tryClaimPrimaryCaregiver(
        careSpaceId: careTeam.id,
        uid: uid,
        canBePrimary: canBePrimary,
      );

      await _notifications.notifyCareSpaceMembers(
        careSpaceId: careTeam.id,
        eventType: 'member_joined',
        title: 'New member joined',
        body: 'A new member joined the care team.',
        data: {'joined_user_profile_id': uid},
      );

      return Member(
        id: uid,
        careTeamId: careTeam.id,
        name: memberName,
        email: trimmedEmail,
        role: role,
        isAdmin: isPrimary || existingSelfPrimary == true,
        joinedAt: now,
        lastActive: now,
      );
    }

    final existing = await getMemberByEmailAndCareTeam(
      trimmedEmail,
      careTeam.id,
    );
    if (existing != null) {
      final now = DateTime.now();
      final joinedMember =
          existing.joinedAt == null || existing.lastActive == null
          ? await markMemberJoined(existing.id)
          : existing;

      if ((joinedMember.role ?? '').trim() != role) {
        await updateMemberRole(joinedMember.id, role);
        return Member(
          id: joinedMember.id,
          careTeamId: joinedMember.careTeamId,
          name: joinedMember.name,
          email: joinedMember.email,
          role: role,
          isAdmin: joinedMember.isAdmin,
          magicLinkToken: joinedMember.magicLinkToken,
          accessPin: joinedMember.accessPin,
          joinedAt: joinedMember.joinedAt ?? now,
          lastActive: joinedMember.lastActive ?? now,
        );
      }
      return joinedMember;
    }

    const uuid = Uuid();
    final now = DateTime.now();
    final derivedName = trimmedEmail.contains('@')
        ? trimmedEmail.split('@').first
        : trimmedEmail;

    final newMember = Member(
      id: uuid.v4(),
      careTeamId: careTeam.id,
      name: derivedName.isEmpty ? 'Member' : derivedName,
      email: trimmedEmail,
      role: role,
      isAdmin: false,
      joinedAt: now,
      lastActive: now,
    );

    try {
      await addMember(newMember);
      return newMember;
    } catch (_) {
      // If insert fails (duplicate / RLS), try to reuse the record.
      final after = await getMemberByEmailAndCareTeam(
        trimmedEmail,
        careTeam.id,
      );
      if (after == null) {
        rethrow;
      }
      if ((after.role ?? '').trim() != role) {
        await updateMemberRole(after.id, role);
        return Member(
          id: after.id,
          careTeamId: after.careTeamId,
          name: after.name,
          email: after.email,
          role: role,
          isAdmin: after.isAdmin,
          magicLinkToken: after.magicLinkToken,
          accessPin: after.accessPin,
          joinedAt: after.joinedAt,
          lastActive: after.lastActive,
        );
      }
      return after;
    }
  }

  Future<List<CareTeamMembership>> getCareTeamsForMedicalMember(
    String email,
  ) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) return [];

    final response = await _client
        .from('members')
        .select(
          'id, care_team_id, name, email, role, is_admin, magic_link_token, access_pin, joined_at, last_active, care_teams(id, patient_first_name, nurse_line_number, created_at)',
        )
        .eq('email', trimmedEmail)
        .inFilter('role', ['medical_team', 'nurse']);

    final rows = (response as List).cast<Map<String, dynamic>>();
    final memberships = <CareTeamMembership>[];
    for (final row in rows) {
      final teamJson = row['care_teams'];
      if (teamJson is! Map<String, dynamic>) continue;
      final member = Member.fromJson(row);
      final team = CareTeam.fromJson(teamJson);
      memberships.add(CareTeamMembership(member: member, careTeam: team));
    }

    memberships.sort((a, b) {
      final an = (a.careTeam.patientFirstName ?? '').toLowerCase();
      final bn = (b.careTeam.patientFirstName ?? '').toLowerCase();
      return an.compareTo(bn);
    });

    return memberships;
  }

  Future<Member?> getMemberByEmailAndCareTeam(
    String email,
    String careTeamId,
  ) async {
    final response = await _client
        .from('members')
        .select()
        .eq('email', email)
        .eq('care_team_id', careTeamId)
        .maybeSingle();
    if (response == null) return null;
    return Member.fromJson(response);
  }

  Future<void> updateMemberRole(String memberId, String role) async {
    await _client.from('members').update({'role': role}).eq('id', memberId);
  }

  Future<Member> markMemberJoined(String memberId) async {
    final now = DateTime.now().toIso8601String();
    final response = await _client
        .from('members')
        .update({'joined_at': now, 'last_active': now})
        .eq('id', memberId)
        .select()
        .single();
    return Member.fromJson(response);
  }

  Future<CareTeam?> getCareTeamByJoinCode(String code) async {
    final trimmed = code.trim().toUpperCase();
    if (trimmed.isEmpty) return null;

    if (await _isDocxSchema()) {
      final invite = await _client
          .from('invite_code')
          .select('care_space_id, invite_token, invite_email, expires_at')
          .eq('invite_token', trimmed)
          .order('invited_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (invite == null) return null;

      DateTime? expiry;
      final rawExpiry = invite['expires_at'];
      if (rawExpiry is DateTime) {
        expiry = rawExpiry;
      } else if (rawExpiry is String) {
        expiry = DateTime.tryParse(rawExpiry);
      }
      final isExpired = expiry != null && DateTime.now().isAfter(expiry);
      if (isExpired) return null;

      final teamId = (invite['care_space_id'] ?? '').toString().trim();
      if (teamId.isEmpty) return null;
      try {
        return await getCareTeam(teamId) ?? CareTeam(id: teamId);
      } catch (_) {
        return CareTeam(id: teamId);
      }
    }

    // Some Supabase environments may not have `care_teams.join_code` yet.
    // Try join_code first, then fall back to invites.invite_code.
    try {
      final response = await _client
          .from('care_teams')
          .select()
          .eq('join_code', trimmed)
          .maybeSingle();
      if (response != null) {
        return CareTeam.fromJson(response);
      }
    } catch (e) {
      final msg = e.toString().toLowerCase();
      final joinCodeMissing =
          msg.contains('join_code') &&
          (msg.contains('does not exist') || msg.contains('could not find'));
      if (!joinCodeMissing) {
        rethrow;
      }
    }

    final invite = await _client
        .from('invites')
        .select('care_team_id, expires_at')
        .eq('invite_code', trimmed)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (invite == null) return null;

    DateTime? expiry;
    final rawExpiry = invite['expires_at'];
    if (rawExpiry is DateTime) {
      expiry = rawExpiry;
    } else if (rawExpiry is String) {
      expiry = DateTime.tryParse(rawExpiry);
    }
    final isExpired = expiry != null && DateTime.now().isAfter(expiry);
    if (isExpired) return null;

    final teamId = (invite['care_team_id'] ?? '').toString().trim();
    if (teamId.isEmpty) return null;
    return getCareTeam(teamId);
  }

  Future<Map<String, dynamic>?> getActiveInviteByCodeAndEmail({
    required String inviteCode,
    required String email,
  }) async {
    final trimmedCode = inviteCode.trim().toUpperCase();
    final trimmedEmail = email.trim();
    if (trimmedCode.isEmpty || trimmedEmail.isEmpty) return null;

    if (await _isDocxSchema()) {
      final inviteRows = await _client
          .from('invite_code')
          .select(
            'invite_code_id, care_space_id, invite_token, invite_email, expires_at, invited_at',
          )
          .eq('invite_token', trimmedCode)
          .order('invited_at', ascending: false)
          .limit(10);

      final invites = (inviteRows as List).cast<Map<String, dynamic>>();
      Map<String, dynamic>? invite;
      for (final row in invites) {
        final inviteEmail = (row['invite_email'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (inviteEmail == 'public' ||
            inviteEmail == trimmedEmail.toLowerCase()) {
          invite = row;
          break;
        }
      }
      if (invite == null) return null;

      DateTime? expiry;
      final rawExpiry = invite['expires_at'];
      if (rawExpiry is DateTime) {
        expiry = rawExpiry;
      } else if (rawExpiry is String) {
        expiry = DateTime.tryParse(rawExpiry);
      }
      final isExpired = expiry != null && DateTime.now().isAfter(expiry);
      if (isExpired) return null;

      return {
        'id': invite['invite_code_id'],
        'care_team_id': invite['care_space_id'],
        'invite_code': invite['invite_token'],
        'email': invite['invite_email'],
        'role': 'family',
        'expires_at': invite['expires_at'],
        'created_at': invite['invited_at'],
      };
    }

    final invite = await _client
        .from('invites')
        .select(
          'id, care_team_id, invite_code, email, role, expires_at, created_at',
        )
        .eq('invite_code', trimmedCode)
        .eq('email', trimmedEmail)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();

    if (invite == null) return null;

    DateTime? expiry;
    final rawExpiry = invite['expires_at'];
    if (rawExpiry is DateTime) {
      expiry = rawExpiry;
    } else if (rawExpiry is String) {
      expiry = DateTime.tryParse(rawExpiry);
    }
    final isExpired = expiry != null && DateTime.now().isAfter(expiry);
    if (isExpired) return null;

    return (invite as Map).cast<String, dynamic>();
  }

  // Medications
  Future<List<Medication>> getMedications(String careTeamId) async {
    if (await _isDocxSchema()) {
      final response = await _client
          .from('medication')
          .select(
            'medication_id, care_space_id, name, frequency, notes, created_at, created_by, deleted_at',
          )
          .eq('care_space_id', careTeamId)
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);

      final rows = (response as List).cast<Map<String, dynamic>>();
      return rows.map((row) {
        final rawNotes = (row['notes'] ?? '').toString();
        final legacy = _tryParseJsonObject(rawNotes);

        final legacyStrength = legacy?['strength']?.toString();
        final legacyTypicalDose = legacy?['typical_dose']?.toString();
        final legacyRoute = legacy?['route']?.toString();
        final legacyPattern = legacy?['pattern']?.toString();
        final legacyScheduleDetails = legacy?['schedule_details']?.toString();
        final legacyNotes = legacy?['notes']?.toString();
        final legacyPrnReasonTags = _jsonTextArray(legacy?['prn_reason_tags']);

        final rowFrequency = (row['frequency'] ?? '').toString();
        return Medication(
          id: (row['medication_id'] ?? '').toString(),
          careTeamId: (row['care_space_id'] ?? '').toString(),
          name: (row['name'] ?? '').toString().trim().isEmpty
              ? null
              : (row['name'] ?? '').toString(),
          strength: legacyStrength,
          typicalDose: legacyTypicalDose,
          route: legacyRoute,
          pattern: rowFrequency.trim().isEmpty ? legacyPattern : rowFrequency,
          scheduleDetails: legacyScheduleDetails,
          notes: legacyNotes ?? (rawNotes.trim().isEmpty ? null : rawNotes),
          prnReasonTags: legacyPrnReasonTags,
          createdAt: row['created_at'] is String
              ? DateTime.tryParse(row['created_at'] as String)
              : row['created_at'] as DateTime?,
          createdByMemberId: (row['created_by'] ?? '').toString().trim().isEmpty
              ? null
              : (row['created_by'] ?? '').toString(),
          deprescribedAt: row['deleted_at'] is String
              ? DateTime.tryParse(row['deleted_at'] as String)
              : row['deleted_at'] as DateTime?,
        );
      }).toList();
    }

    final response = await _client
        .from('medications')
        .select()
        .eq('care_team_id', careTeamId);
    return (response as List).map((m) => Medication.fromJson(m)).toList();
  }

  Future<void> addMedication(Medication medication) async {
    if (await _isDocxSchema()) {
      final legacy = <String, dynamic>{
        'notes': medication.notes,
        'strength': medication.strength,
        'typical_dose': medication.typicalDose,
        'route': medication.route,
        'pattern': medication.pattern,
        'schedule_details': medication.scheduleDetails,
        'prn_reason_tags': medication.prnReasonTags ?? <String>[],
      };
      legacy.removeWhere((_, v) => v == null);

      final payload = <String, dynamic>{
        'medication_id': medication.id,
        'care_space_id': medication.careTeamId,
        'name': medication.name,
        'frequency': medication.pattern,
        'notes': jsonEncode(legacy),
        'is_active': medication.deprescribedAt == null,
        'deleted_at': medication.deprescribedAt?.toUtc().toIso8601String(),
        'created_by': _client.auth.currentUser?.id,
      };
      _removeNullValues(payload);

      await _client
          .from('medication')
          .upsert(payload, onConflict: 'medication_id');
      return;
    }

    await _client.from('medications').upsert(medication.toJson());
  }

  Future<void> updateMedication(Medication medication) async {
    if (await _isDocxSchema()) {
      final legacy = <String, dynamic>{
        'notes': medication.notes,
        'strength': medication.strength,
        'typical_dose': medication.typicalDose,
        'route': medication.route,
        'pattern': medication.pattern,
        'schedule_details': medication.scheduleDetails,
        'prn_reason_tags': medication.prnReasonTags ?? <String>[],
      };
      legacy.removeWhere((_, v) => v == null);

      final payload = <String, dynamic>{
        'name': medication.name,
        'frequency': medication.pattern,
        'notes': jsonEncode(legacy),
        'is_active': medication.deprescribedAt == null,
        'deleted_at': medication.deprescribedAt?.toUtc().toIso8601String(),
      };
      _removeNullValues(payload);

      await _client
          .from('medication')
          .update(payload)
          .eq('medication_id', medication.id);
      return;
    }

    await _client
        .from('medications')
        .update(medication.toJson())
        .eq('id', medication.id);
  }

  Future<void> deleteMedication(String medicationId) async {
    if (await _isDocxSchema()) {
      await _client
          .from('medication')
          .update({
            'deleted_at': DateTime.now().toUtc().toIso8601String(),
            'is_active': false,
          })
          .eq('medication_id', medicationId);
      return;
    }

    await _client.from('medications').delete().eq('id', medicationId);
  }

  // Dose Logs
  Future<List<DoseLog>> getDoseLogs(String careTeamId) async {
    if (await _isDocxSchema()) {
      final response = await _client
          .from('medication_log')
          .select(
            'medication_log_id, care_space_id, medication_id, administered_at, notes, created_at',
          )
          .eq('care_space_id', careTeamId)
          .order('administered_at', ascending: false);

      final rows = (response as List).cast<Map<String, dynamic>>();
      return rows.map((row) {
        final legacy = _tryParseJsonObject((row['notes'] ?? '').toString());
        return DoseLog(
          id: (row['medication_log_id'] ?? '').toString(),
          careTeamId: (row['care_space_id'] ?? '').toString(),
          medicationId: (row['medication_id'] ?? '').toString().trim().isEmpty
              ? null
              : (row['medication_id'] ?? '').toString(),
          medicationName: legacy?['medication_name']?.toString(),
          doseTime: row['administered_at'] is String
              ? DateTime.tryParse(row['administered_at'] as String)
              : row['administered_at'] as DateTime?,
          amountGiven: legacy?['amount_given']?.toString(),
          whoGave: legacy?['who_gave']?.toString(),
          note: legacy?['note']?.toString(),
          loggedByMemberId: legacy?['logged_by_member_id']?.toString(),
          loggedByMemberName: legacy?['logged_by_member_name']?.toString(),
          editableUntil: null,
          eventId: null,
        );
      }).toList();
    }

    final response = await _client
        .from('dose_logs')
        .select()
        .eq('care_team_id', careTeamId)
        .order('dose_time', ascending: false);
    return (response as List).map((d) => DoseLog.fromJson(d)).toList();
  }

  Future<void> logDose(DoseLog log) async {
    if (await _isDocxSchema()) {
      final careSpaceId = (log.careTeamId ?? '').trim();
      if (careSpaceId.isEmpty) {
        throw Exception('careTeamId is required');
      }

      final administeredAt = (log.doseTime ?? DateTime.now()).toUtc();
      final legacy = <String, dynamic>{
        'amount_given': log.amountGiven,
        'who_gave': log.whoGave,
        'note': log.note,
        'logged_by_member_id': log.loggedByMemberId,
        'logged_by_member_name': log.loggedByMemberName,
        'medication_name': log.medicationName,
      };
      legacy.removeWhere((_, v) => v == null);

      final payload = <String, dynamic>{
        'medication_log_id': log.id,
        'care_space_id': careSpaceId,
        'medication_id': log.medicationId,
        'administered_at': administeredAt.toIso8601String(),
        'notes': jsonEncode(legacy),
        'administered_by_id': _client.auth.currentUser?.id,
      };
      _removeNullValues(payload);
      await _client.from('medication_log').insert(payload);

      await _notifications.notifyCareSpaceMembers(
        careSpaceId: careSpaceId,
        eventType: 'dose_logged',
        title: 'Medication dose logged',
        body: (log.medicationName ?? '').trim().isEmpty
            ? 'A medication dose was logged.'
            : 'Dose logged for ${log.medicationName}.',
        data: {
          'medication_id': log.medicationId,
          'medication_name': log.medicationName,
          'administered_at': administeredAt.toIso8601String(),
        },
      );
      return;
    }

    await _client.from('dose_logs').insert(log.toJson());
  }

  // Symptom Events
  Future<List<SymptomEvent>> getSymptomEvents(
    String careTeamId, {
    bool includeDeleted = false,
  }) async {
    if (await _isDocxSchema()) {
      final response = await _client
          .from('symptom_log')
          .select(
            'symptom_log_id, care_space_id, observed_at, notes, created_by, created_at',
          )
          .eq('care_space_id', careTeamId)
          .order('observed_at', ascending: false);

      final rows = (response as List).cast<Map<String, dynamic>>();
      final events = rows.map((row) {
        final legacy = _tryParseJsonObject((row['notes'] ?? '').toString());
        return SymptomEvent(
          id: (row['symptom_log_id'] ?? '').toString(),
          careTeamId: (row['care_space_id'] ?? '').toString(),
          symptoms: _jsonTextArray(legacy?['symptoms']) ?? <String>[],
          severity: legacy?['severity']?.toString(),
          whatHappened:
              legacy?['what_happened']?.toString() ??
              legacy?['notes']?.toString(),
          eventTime: row['observed_at'] is String
              ? DateTime.tryParse(row['observed_at'] as String)
              : row['observed_at'] as DateTime?,
          deletedAt: null,
          createdByMemberId: (row['created_by'] ?? '').toString().trim().isEmpty
              ? null
              : (row['created_by'] ?? '').toString(),
          createdByMemberName: null,
          editableUntil: null,
        );
      }).toList();

      return events;
    }

    final response = await _client
        .from('symptom_events')
        .select()
        .eq('care_team_id', careTeamId)
        .order('event_time', ascending: false);
    final events = (response as List)
        .map((s) => SymptomEvent.fromJson(s))
        .toList();
    if (includeDeleted) return events;
    return events.where((e) => e.deletedAt == null).toList();
  }

  Future<void> logSymptomEvent(SymptomEvent event) async {
    if (await _isDocxSchema()) {
      final careSpaceId = (event.careTeamId ?? '').trim();
      if (careSpaceId.isEmpty) {
        throw Exception('careTeamId is required');
      }

      final observedAt = (event.eventTime ?? DateTime.now()).toUtc();
      final legacy = <String, dynamic>{
        'symptoms': event.symptoms ?? <String>[],
        'severity': event.severity,
        'what_happened': event.whatHappened,
        'notes': event.whatHappened,
      };
      legacy.removeWhere((_, v) => v == null);

      final payload = <String, dynamic>{
        'symptom_log_id': event.id,
        'care_space_id': careSpaceId,
        'observed_at': observedAt.toIso8601String(),
        'notes': jsonEncode(legacy),
        'created_by': _client.auth.currentUser?.id,
        'voice_note_url': null,
      };
      _removeNullValues(payload);
      await _client.from('symptom_log').insert(payload);

      final symptoms = (event.symptoms ?? const <String>[])
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      await _notifications.notifyCareSpaceMembers(
        careSpaceId: careSpaceId,
        eventType: 'symptom_logged',
        title: 'Symptom logged',
        body: symptoms.isEmpty
            ? 'A symptom was logged.'
            : 'Logged: ${symptoms.take(3).join(', ')}',
        data: {
          'symptom_log_id': event.id,
          'observed_at': observedAt.toIso8601String(),
          'symptoms': symptoms,
          'severity': event.severity,
        },
      );
      return;
    }

    try {
      final response = await _client
          .from('symptom_events')
          .insert(event.toJson())
          .select();

      // ignore: avoid_print
      print("SYMPTOM INSERT SUCCESS:");
      // ignore: avoid_print
      print(response);
    } catch (e) {
      // ignore: avoid_print
      print("SYMPTOM INSERT ERROR:");
      // ignore: avoid_print
      print(e);
    }
  }

  Future<void> updateSymptomEvent(SymptomEvent event) async {
    if (await _isDocxSchema()) {
      // DOCX symptom_log doesn't support editing fields beyond notes/time in this adapter.
      final legacy = <String, dynamic>{
        'symptoms': event.symptoms ?? <String>[],
        'severity': event.severity,
        'what_happened': event.whatHappened,
        'notes': event.whatHappened,
      };
      legacy.removeWhere((_, v) => v == null);
      final payload = <String, dynamic>{
        'observed_at': event.eventTime?.toUtc().toIso8601String(),
        'notes': jsonEncode(legacy),
      };
      _removeNullValues(payload);
      await _client
          .from('symptom_log')
          .update(payload)
          .eq('symptom_log_id', event.id);
      return;
    }

    await _client
        .from('symptom_events')
        .update(event.toJson())
        .eq('id', event.id);
  }

  /// Soft-delete a symptom event by setting `deleted_at`.
  ///
  /// If the backend schema does not include a `deleted_at` column, Supabase will
  /// throw and the caller can fall back to local hiding.
  Future<void> archiveSymptomEvent(String eventId) async {
    await _client
        .from('symptom_events')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', eventId);
  }

  Future<void> deleteSymptomEvent(String eventId) async {
    if (await _isDocxSchema()) {
      await _client.from('symptom_log').delete().eq('symptom_log_id', eventId);
      return;
    }
    await _client.from('symptom_events').delete().eq('id', eventId);
  }

  Future<Map<String, dynamic>?> getMedicationScheduleDetails(
    String medicationId,
  ) async {
    if (await _isDocxSchema()) {
      final response = await _client
          .from('medication')
          .select('name, frequency, notes')
          .eq('medication_id', medicationId)
          .maybeSingle();
      if (response == null) return null;
      final row = (response as Map).cast<String, dynamic>();
      final legacy = _tryParseJsonObject((row['notes'] ?? '').toString());
      final legacyPattern = legacy?['pattern'];
      return {
        'name': row['name'],
        'pattern': (row['frequency'] ?? '').toString().trim().isEmpty
            ? legacyPattern
            : row['frequency'],
      };
    }

    return await _client
        .from('medications')
        .select('name, pattern')
        .eq('id', medicationId)
        .maybeSingle();
  }

  Future<Map<String, dynamic>?> getMedicationDetails(
    String medicationId,
  ) async {
    if (await _isDocxSchema()) {
      final response = await _client
          .from('medication')
          .select('name, frequency, notes')
          .eq('medication_id', medicationId)
          .maybeSingle();
      if (response == null) return null;
      final row = (response as Map).cast<String, dynamic>();
      final legacy = _tryParseJsonObject((row['notes'] ?? '').toString());
      final legacyPattern = legacy?['pattern'];
      return {
        'name': row['name'],
        'strength': legacy?['strength'],
        'pattern': (row['frequency'] ?? '').toString().trim().isEmpty
            ? legacyPattern
            : row['frequency'],
        'schedule_details': legacy?['schedule_details'],
        'notes': legacy?['notes'] ?? row['notes'],
      };
    }

    return await _client
        .from('medications')
        .select('name, strength, pattern, schedule_details, notes')
        .eq('id', medicationId)
        .maybeSingle();
  }

  Future<Map<String, dynamic>?> getSymptomDetails(String symptomEventId) async {
    if (await _isDocxSchema()) {
      final response = await _client
          .from('symptom_log')
          .select('notes')
          .eq('symptom_log_id', symptomEventId)
          .maybeSingle();
      if (response == null) return null;
      final row = (response as Map).cast<String, dynamic>();
      final legacy = _tryParseJsonObject((row['notes'] ?? '').toString());
      return {
        'what_happened': legacy?['what_happened'] ?? legacy?['notes'],
        'severity': legacy?['severity'],
      };
    }

    return await _client
        .from('symptom_events')
        .select('what_happened, severity')
        .eq('id', symptomEventId)
        .maybeSingle();
  }

  // Skin & Wound Events
  Future<void> logSkinWoundEvent(SkinWoundEvent event) async {
    try {
      final response = await _client
          .from('skin_wound_events')
          .insert(event.toJson())
          .select();
      // ignore: avoid_print
      print('SKIN/WOUND INSERT SUCCESS:');
      // ignore: avoid_print
      print(response);
    } catch (e) {
      // ignore: avoid_print
      print('SKIN/WOUND INSERT ERROR:');
      // ignore: avoid_print
      print(e);
      rethrow;
    }
  }

  Future<List<SkinWoundEvent>> getSkinWoundEvents(String careTeamId) async {
    final response = await _client
        .from('skin_wound_events')
        .select()
        .eq('care_team_id', careTeamId)
        .order('event_time', ascending: false);
    final events = (response as List)
        .map((e) => SkinWoundEvent.fromJson(e))
        .toList();
    return events.where((e) => e.deletedAt == null).toList();
  }

  Future<List<SkinWoundEvent>> getSkinWoundEventsIncludingDeleted(
    String careTeamId,
  ) async {
    final response = await _client
        .from('skin_wound_events')
        .select()
        .eq('care_team_id', careTeamId)
        .order('event_time', ascending: false);
    return (response as List).map((e) => SkinWoundEvent.fromJson(e)).toList();
  }

  Future<void> updateSkinWoundEvent(SkinWoundEvent event) async {
    await _client
        .from('skin_wound_events')
        .update(event.toJson())
        .eq('id', event.id);
  }

  Future<void> archiveSkinWoundEvent(String id) async {
    await _client
        .from('skin_wound_events')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', id);
  }

  // Care Plans
  Future<CarePlan?> getCarePlan(String careTeamId) async {
    final response = await _client
        .from('care_plans')
        .select()
        .eq('care_team_id', careTeamId)
        .maybeSingle();
    if (response == null) return null;
    return CarePlan.fromJson(response);
  }

  Future<void> updateCarePlan(CarePlan plan) async {
    await _client.from('care_plans').upsert(plan.toJson());
  }

  // Observations
  Future<List<Observation>> getObservations(
    String careTeamId, {
    bool includeDeleted = false,
  }) async {
    if (await _isDocxSchema()) {
      final response = await _client
          .from('quick_notes')
          .select(
            'quick_notes_id, care_space_id, content_text, visibility, created_at, deleted_at, user_profile_id',
          )
          .eq('care_space_id', careTeamId)
          .order('created_at', ascending: false);

      final rows = (response as List).cast<Map<String, dynamic>>();
      final mapped = rows.map((row) {
        return Observation(
          id: (row['quick_notes_id'] ?? '').toString(),
          careTeamId: (row['care_space_id'] ?? '').toString(),
          content: (row['content_text'] ?? '').toString(),
          category: null,
          createdAt: row['created_at'] is String
              ? DateTime.tryParse(row['created_at'] as String)
              : row['created_at'] as DateTime?,
          deletedAt: row['deleted_at'] is String
              ? DateTime.tryParse(row['deleted_at'] as String)
              : row['deleted_at'] as DateTime?,
          createdByMemberId:
              (row['user_profile_id'] ?? '').toString().trim().isEmpty
              ? null
              : (row['user_profile_id'] ?? '').toString(),
          createdByMemberName: null,
        );
      }).toList();

      if (includeDeleted) return mapped;
      return mapped.where((o) => o.deletedAt == null).toList();
    }

    final response = await _client
        .from('observations')
        .select()
        .eq('care_team_id', careTeamId)
        .order('created_at', ascending: false);
    final observations = (response as List)
        .map((o) => Observation.fromJson(o))
        .toList();
    if (includeDeleted) return observations;
    return observations.where((o) => o.deletedAt == null).toList();
  }

  Future<void> addObservation(Observation observation) async {
    if (await _isDocxSchema()) {
      final careSpaceId = (observation.careTeamId ?? '').trim();
      if (careSpaceId.isEmpty) {
        throw Exception('careTeamId is required');
      }

      final payload = <String, dynamic>{
        'quick_notes_id': observation.id,
        'care_space_id': careSpaceId,
        'user_profile_id': _client.auth.currentUser?.id,
        'content_text': (observation.content ?? '').trim().isEmpty
            ? 'Note'
            : observation.content,
        'visibility': 'team',
      };
      _removeNullValues(payload);
      await _client.from('quick_notes').insert(payload);

      await _notifications.notifyCareSpaceMembers(
        careSpaceId: careSpaceId,
        eventType: 'note_added',
        title: 'Note added',
        body: ((observation.content ?? '').trim().isEmpty)
            ? 'A new note was added.'
            : (observation.content ?? '').trim(),
        data: {'quick_notes_id': observation.id},
      );
      return;
    }

    await _client.from('observations').insert(observation.toJson());
  }

  Future<void> updateObservation(Observation observation) async {
    if (await _isDocxSchema()) {
      final payload = <String, dynamic>{'content_text': observation.content};
      _removeNullValues(payload);
      await _client
          .from('quick_notes')
          .update(payload)
          .eq('quick_notes_id', observation.id);
      return;
    }

    await _client
        .from('observations')
        .update(observation.toJson())
        .eq('id', observation.id);
  }

  /// Soft-delete an observation by setting `deleted_at`.
  ///
  /// If the backend schema does not include a `deleted_at` column, Supabase will
  /// throw and the caller can fall back to local hiding.
  Future<void> archiveObservation(String observationId) async {
    if (await _isDocxSchema()) {
      await _client
          .from('quick_notes')
          .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
          .eq('quick_notes_id', observationId);
      return;
    }

    await _client
        .from('observations')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', observationId);
  }

  // Moments
  Future<List<Moment>> getMoments(String careTeamId) async {
    if (await _isDocxSchema()) {
      final response = await _client
          .from('moment')
          .select(
            'moment_id, care_space_id, content_text, content_image_url, voice_note_url, moment_date, created_by, created_at, updated_at',
          )
          .eq('care_space_id', careTeamId)
          .order('created_at', ascending: false);

      final rows = (response as List).cast<Map<String, dynamic>>();
      return rows.map((row) {
        return Moment(
          id: (row['moment_id'] ?? '').toString(),
          careTeamId: (row['care_space_id'] ?? '').toString(),
          category: null,
          content: (row['content_text'] ?? '').toString(),
          visibility: null,
          photoUrl: (row['content_image_url'] ?? '').toString().trim().isEmpty
              ? null
              : (row['content_image_url'] ?? '').toString(),
          createdAt: row['created_at'] is String
              ? DateTime.tryParse(row['created_at'] as String)
              : row['created_at'] as DateTime?,
          createdByMemberId: (row['created_by'] ?? '').toString().trim().isEmpty
              ? null
              : (row['created_by'] ?? '').toString(),
          createdByMemberName: null,
        );
      }).toList();
    }

    final response = await _client
        .from('moments')
        .select()
        .eq('care_team_id', careTeamId)
        .order('created_at', ascending: false);
    return (response as List).map((m) => Moment.fromJson(m)).toList();
  }

  Future<void> addMoment(Moment moment) async {
    if (await _isDocxSchema()) {
      final careSpaceId = (moment.careTeamId ?? '').trim();
      if (careSpaceId.isEmpty) {
        throw Exception('careTeamId is required');
      }

      final payload = <String, dynamic>{
        'moment_id': moment.id,
        'care_space_id': careSpaceId,
        'created_by': _client.auth.currentUser?.id,
        'content_text': (moment.content ?? '').trim().isEmpty
            ? 'Moment'
            : moment.content,
        'content_image_url': moment.photoUrl,
      };
      _removeNullValues(payload);
      await _client.from('moment').insert(payload);

      await _notifications.notifyCareSpaceMembers(
        careSpaceId: careSpaceId,
        eventType: 'moment_added',
        title: 'New moment',
        body: ((moment.content ?? '').trim().isEmpty)
            ? 'A new moment was posted.'
            : (moment.content ?? '').trim(),
        data: {'moment_id': moment.id},
      );
      return;
    }

    await _client.from('moments').insert(moment.toJson());
  }

  // Calendar Events
  Future<List<CalendarEvent>> getCalendarEvents(String careTeamId) async {
    if (await _isDocxCalendarSchema()) {
      final response = await _client
          .from('calendar_events')
          .select(
            'calendar_event_id, care_space_id, title, scheduled_at, event_type, source, created_by, notes, duration_minutes, detail, source_medication_id, deleted_at, created_at',
          )
          .eq('care_space_id', careTeamId)
          .isFilter('deleted_at', null)
          .order('scheduled_at', ascending: true);

      final rows = (response as List).cast<Map<String, dynamic>>();
      return rows
          .map((row) {
            final rawType = (row['event_type'] ?? '').toString();
            final mappedType = rawType == 'medication'
                ? 'medication'
                : rawType.endsWith('_visit')
                ? 'visit'
                : rawType == 'reminder'
                ? 'care'
                : 'care';

            final legacy = _tryParseJsonObject((row['notes'] ?? '').toString());
            final notesText =
                legacy?['notes']?.toString() ?? row['notes']?.toString();
            final isOverridden = legacy?['is_overridden'] == true;

            return CalendarEvent(
              id: (row['calendar_event_id'] ?? '').toString(),
              careTeamId: (row['care_space_id'] ?? '').toString(),
              title: (row['title'] ?? '').toString(),
              dateTime: row['scheduled_at'] is String
                  ? DateTime.parse(row['scheduled_at'] as String)
                  : (row['scheduled_at'] as DateTime),
              type: _eventTypeFromString(mappedType),
              source: (row['source'] ?? 'manual').toString(),
              createdBy: (row['created_by'] ?? '').toString().trim().isEmpty
                  ? null
                  : (row['created_by'] ?? '').toString(),
              notes: notesText?.trim().isEmpty ?? true ? null : notesText,
              duration: row['duration_minutes'] as int?,
              severity: legacy?['severity']?.toString(),
              relatedId:
                  (row['source_medication_id'] ?? '').toString().trim().isEmpty
                  ? null
                  : (row['source_medication_id'] ?? '').toString(),
              isAuto: (row['source'] ?? '').toString() != 'manual',
              isOverridden: isOverridden,
              createdAt: row['created_at'] is String
                  ? DateTime.tryParse(row['created_at'] as String)
                  : row['created_at'] as DateTime?,
            );
          })
          .where((event) => event.isOverridden != true)
          .toList();
    }

    final response = await _client
        .from('calendar_events')
        .select()
        .eq('care_team_id', careTeamId)
        .order('date', ascending: true);
    return (response as List).map((e) => CalendarEvent.fromJson(e)).toList();
  }

  Future<void> addCalendarEvent(CalendarEvent event) async {
    if (await _isDocxCalendarSchema()) {
      final rawNotes = <String, dynamic>{
        'notes': event.notes,
        'severity': event.severity,
        'is_overridden': event.isOverridden,
      };
      rawNotes.removeWhere((_, v) => v == null);

      final docxType = event.type == EventType.medication
          ? 'medication'
          : event.type == EventType.visit
          ? 'other_visit'
          : 'reminder';
      final category = event.type == EventType.medication
          ? 'medications'
          : event.type == EventType.visit
          ? 'visits'
          : 'other';

      final payload = <String, dynamic>{
        'calendar_event_id': event.id,
        'care_space_id': event.careTeamId,
        'event_type': docxType,
        'category': category,
        'scheduled_at': event.dateTime.toUtc().toIso8601String(),
        'duration_minutes': event.duration,
        'title': event.title,
        // Visitor name was repurposed into detail in the UI.
        'detail': null,
        'notes': jsonEncode(rawNotes),
        'source': event.source,
        'source_medication_id': event.relatedId,
        'created_by': _client.auth.currentUser?.id,
      };
      _removeNullValues(payload);

      await _client.from('calendar_events').insert(payload);
      return;
    }

    await _client.from('calendar_events').insert(event.toJson());
  }

  // Nurse Contacts
  Future<void> logNurseContact(NurseContact contact) async {
    await _client.from('nurse_contacts').insert(contact.toJson());
  }

  // Check-ins
  Future<void> addCheckIn(CheckIn checkIn) async {
    await _client.from('check_ins').insert(checkIn.toJson());
  }

  // Shift Notes
  Future<void> addShiftNote(ShiftNote note) async {
    await _client.from('shift_notes').insert(note.toJson());
  }

  // Auth (Simple PIN-based login for now as per schema)
  Future<Member?> loginWithPin(String email, String pin) async {
    final response = await _client
        .from('members')
        .select()
        .eq('email', email)
        .eq('access_pin', pin)
        .maybeSingle();
    if (response == null) return null;
    return Member.fromJson(response);
  }
}
