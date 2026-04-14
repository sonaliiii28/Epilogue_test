import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../core/session_manager.dart';
import '../core/supabase_service.dart';

const _deepPurple = Color(0xFF2E2540);
const _purple = Color(0xFF7A64A4);
const _borderColor = Color(0xFFD4CDDF);
const _cardBg = Color(0xFFF0EDF6);
const _bg1 = Color(0xFF74659A);
const _bg2 = Color(0xFFDFDBE5);

String generateInviteCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final rand = Random.secure();
  return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
}

class CareTeamScreen extends StatefulWidget {
  const CareTeamScreen({super.key});

  @override
  State<CareTeamScreen> createState() => _CareTeamScreenState();
}

class _CareTeamScreenState extends State<CareTeamScreen> {
  final _service = SupabaseService();
  final _session = SessionManager();

  List<Map<String, dynamic>> _members = [];
  String? _inviteCode;
  bool _loading = true;
  String? _removingMemberId;

  List<Map<String, dynamic>> get _activeMembers {
    return _members.where((member) {
      final joinedAt = member['joined_at'];
      return joinedAt != null;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  DateTime? _parseExpiry(dynamic rawExpiry) {
    if (rawExpiry is DateTime) return rawExpiry;
    if (rawExpiry is String) return DateTime.tryParse(rawExpiry);
    return null;
  }

  Future<String?> _loadActiveInviteCodeFromInviteCodeTable(
    String teamId,
  ) async {
    // Prefer the unified `invite_code` table when present.
    // Supports both DOCX (care_space_id/invite_token) and legacy (care_team_id/invite_code) shapes.
    try {
      final invite = await _service.client
          .from('invite_code')
          .select('invite_token, expires_at, invited_at')
          .eq('care_space_id', teamId)
          .eq('invite_email', 'public')
          .order('invited_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (invite == null) return null;
      final expiry = _parseExpiry(invite['expires_at']);
      final isExpired = expiry != null && DateTime.now().isAfter(expiry);
      if (isExpired) return null;

      final code = (invite['invite_token'] ?? '').toString().trim();
      return code.isEmpty ? null : code;
    } catch (e) {
      debugPrint('CareTeamScreen: invite_code (docx-shape) fetch failed: $e');
    }

    try {
      final invite = await _service.client
          .from('invite_code')
          .select('invite_code, expires_at, created_at')
          .eq('care_team_id', teamId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (invite == null) return null;
      final expiry = _parseExpiry(invite['expires_at']);
      final isExpired = expiry != null && DateTime.now().isAfter(expiry);
      if (isExpired) return null;

      final code = (invite['invite_code'] ?? '').toString().trim();
      return code.isEmpty ? null : code;
    } catch (e) {
      debugPrint('CareTeamScreen: invite_code (legacy-shape) fetch failed: $e');
      return null;
    }
  }

  Future<void> _ensureActiveLegacyInviteCodeExists(String teamId) async {
    try {
      final existing = await _service.client
          .from('invite_code')
          .select('invite_code, expires_at, created_at')
          .eq('care_team_id', teamId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        final expiry = _parseExpiry(existing['expires_at']);
        final isExpired = expiry != null && DateTime.now().isAfter(expiry);
        final code = (existing['invite_code'] ?? '').toString().trim();
        if (!isExpired && code.isNotEmpty) return;
      }

      final userId = _service.client.auth.currentUser?.id;
      final code = generateInviteCode();
      await _service.client.from('invite_code').insert({
        'care_team_id': teamId,
        'invite_code': code,
        'created_by': userId,
        'expires_at': DateTime.now()
            .add(const Duration(days: 5))
            .toIso8601String(),
      });
      debugPrint('CareTeamScreen: created invite_code row invite_code=$code');
    } catch (e) {
      debugPrint(
        'CareTeamScreen: _ensureActiveLegacyInviteCodeExists failed: $e',
      );
    }
  }

  Future<void> _loadMembers() async {
    final teamId = _session.currentCareTeam?.id;
    if (teamId == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    try {
      debugPrint('CareTeamScreen: loading members + invite for teamId=$teamId');

      final isDocx = await _service.isDocxSchema();
      if (isDocx) {
        await _ensureActiveDocxInviteExists(teamId);
        final inviteCode = await _loadActiveDocxInviteCode(teamId);
        final members = await _service.getMembers(teamId);
        if (!mounted) return;
        setState(() {
          _members = members
              .map(
                (m) => <String, dynamic>{
                  'id': m.id,
                  'care_team_id': m.careTeamId,
                  'name': m.name,
                  'email': m.email,
                  'role': m.role,
                  'is_admin': m.isAdmin == true,
                  'joined_at': DateTime.now().toUtc().toIso8601String(),
                },
              )
              .toList();
          _inviteCode = inviteCode;
          _loading = false;
          _removingMemberId = null;
        });
        return;
      }

      final membersResp = await _service.client
          .from('members')
          .select()
          .eq('care_team_id', teamId)
          .order('joined_at', ascending: true);

      // Prefer reading the "public" invite code from the `invite_code` table.
      // If it's missing, try to create a legacy invite_code row, then read again.
      String? code = await _loadActiveInviteCodeFromInviteCodeTable(teamId);
      if ((code ?? '').trim().isEmpty) {
        await _ensureActiveLegacyInviteCodeExists(teamId);
        code = await _loadActiveInviteCodeFromInviteCodeTable(teamId);
      }

      // Back-compat fallback: older deployments still store invite codes in `invites`.
      if ((code ?? '').trim().isEmpty) {
        await _ensureActiveInviteExists(teamId);
        final inviteResp = await _service.client
            .from('invites')
            .select()
            .eq('care_team_id', teamId)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        debugPrint('CareTeamScreen: inviteResp=$inviteResp');

        if (inviteResp != null) {
          final expiry = _parseExpiry(inviteResp['expires_at']);
          final isExpired = expiry != null && DateTime.now().isAfter(expiry);
          if (!isExpired) {
            code = (inviteResp['invite_code'] ?? '').toString().trim();
          }
        }
      }

      final fallbackJoinCode = (_session.currentCareTeam?.joinCode ?? '')
          .toString()
          .trim();
      final resolvedCode = (code ?? '').trim().isNotEmpty
          ? code
          : (fallbackJoinCode.isNotEmpty ? fallbackJoinCode : null);

      debugPrint('CareTeamScreen: resolved invite code=$resolvedCode');

      if (!mounted) return;
      setState(() {
        _members = (membersResp as List)
            .cast<Map<dynamic, dynamic>>()
            .map(
              (row) => row.map((key, value) => MapEntry(key.toString(), value)),
            )
            .toList();
        _inviteCode = resolvedCode;
        _loading = false;
        _removingMemberId = null;
      });
    } catch (e) {
      debugPrint('CareTeamScreen _loadMembers error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _removingMemberId = null;
      });
    }
  }

  Future<void> _removeMember(Map<String, dynamic> member) async {
    final memberId = member['id']?.toString();
    if (memberId == null || memberId.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Remove Member',
          style: GoogleFonts.nunito(
            fontWeight: FontWeight.w800,
            color: _deepPurple,
          ),
        ),
        content: Text(
          'Remove ${_displayName(member)} from this care team?',
          style: GoogleFonts.nunito(fontSize: 15),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: GoogleFonts.nunito(color: Colors.grey[700]),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade500,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Remove',
              style: GoogleFonts.nunito(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _removingMemberId = memberId);

    try {
      final isDocx = await _service.isDocxSchema();
      if (isDocx) {
        final teamId = _session.currentCareTeam?.id;
        if (teamId == null) return;
        await _service.client
            .from('care_team_member')
            .delete()
            .eq('care_space_id', teamId)
            .eq('user_profile_id', memberId);
      } else {
        await _service.client.from('members').delete().eq('id', memberId);
      }
      await _loadMembers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_displayName(member)} removed',
            style: GoogleFonts.nunito(),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not remove member right now.',
            style: GoogleFonts.nunito(),
          ),
        ),
      );
      setState(() => _removingMemberId = null);
    }
  }

  Future<void> _ensureActiveInviteExists(String teamId) async {
    try {
      final existing = await _service.client
          .from('invites')
          .select('id, invite_code, expires_at, created_at')
          .eq('care_team_id', teamId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (existing != null) {
        DateTime? expiry;
        final rawExpiry = existing['expires_at'];
        if (rawExpiry is DateTime) {
          expiry = rawExpiry;
        } else if (rawExpiry is String) {
          expiry = DateTime.tryParse(rawExpiry);
        }
        final isExpired = expiry != null && DateTime.now().isAfter(expiry);
        final code = (existing['invite_code'] ?? '').toString().trim();
        if (!isExpired && code.isNotEmpty) {
          return;
        }
      }

      final userId = _service.client.auth.currentUser?.id;
      final code = generateInviteCode();
      await _service.client.from('invites').insert({
        'care_team_id': teamId,
        'invite_code': code,
        'created_by': userId,
        'expires_at': DateTime.now()
            .add(const Duration(days: 5))
            .toIso8601String(),
      });
      debugPrint('CareTeamScreen: created fallback invite code=$code');
    } catch (e) {
      debugPrint('CareTeamScreen: _ensureActiveInviteExists failed: $e');
    }
  }

  Future<String?> _loadActiveDocxInviteCode(String teamId) async {
    final invite = await _service.client
        .from('invite_code')
        .select('invite_token, expires_at, invited_at')
        .eq('care_space_id', teamId)
        .eq('invite_email', 'public')
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

    final code = (invite['invite_token'] ?? '').toString().trim();
    return code.isEmpty ? null : code;
  }

  Future<void> _ensureActiveDocxInviteExists(String teamId) async {
    try {
      final existingCode = await _loadActiveDocxInviteCode(teamId);
      if ((existingCode ?? '').trim().isNotEmpty) return;

      final userId = _service.client.auth.currentUser?.id;
      final code = generateInviteCode();
      await _service.client.from('invite_code').upsert({
        'care_space_id': teamId,
        'user_profile_id': userId,
        'invite_token': code,
        'invite_email': 'public',
        'expires_at': DateTime.now()
            .add(const Duration(days: 5))
            .toIso8601String(),
      }, onConflict: 'care_space_id,invite_email');
      debugPrint('CareTeamScreen: created DOCX invite code=$code');
    } catch (e) {
      debugPrint('CareTeamScreen: _ensureActiveDocxInviteExists failed: $e');
    }
  }

  void _openAddMemberModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMemberModal(onSuccess: _loadMembers),
    );
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    context.go('/dashboard');
  }

  String _displayName(Map<String, dynamic> member) {
    final name = (member['name'] ?? '').toString().trim();
    if (name.isNotEmpty && name.toLowerCase() != 'member') {
      return name;
    }
    final email = (member['email'] ?? '').toString().trim();
    return email.isEmpty ? 'Member' : email;
  }

  String _roleLabel(Map<String, dynamic> member) {
    if (member['is_admin'] == true) return 'Primary caregiver';

    final role = member['role']?.toString();
    switch ((role ?? '').trim()) {
      case 'family':
        return 'Family';
      case 'caregiver':
        return 'Caregiver';
      case 'medical_team':
      case 'nurse':
        return 'Medical Team';
      default:
        final raw = (role ?? '').trim();
        return raw.isEmpty ? 'Member' : raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientName = _session.currentCareTeam?.patientFirstName ?? 'Care';

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
                      onTap: _goBack,
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
                            'Care Team',
                            style: GoogleFonts.nunito(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "$patientName's Care Space",
                            style: GoogleFonts.nunito(
                              fontSize: 16,
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
              const SizedBox(height: 14),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                        children: [
                          _buildInviteCodeCard(),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Active Members',
                                  style: GoogleFonts.nunito(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: _openAddMemberModal,
                                style: TextButton.styleFrom(
                                  backgroundColor: _purple,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(Icons.add, size: 18),
                                label: Text(
                                  'Add Member',
                                  style: GoogleFonts.nunito(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_activeMembers.isEmpty) _emptyState(),
                          ..._activeMembers.map(_memberCard),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInviteCodeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Invite Code',
            style: GoogleFonts.nunito(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: _deepPurple,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _inviteCode ?? '----',
            style: GoogleFonts.nunito(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: _purple,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor),
      ),
      child: Text(
        'Joined members will appear here after they accept the invite.',
        style: GoogleFonts.nunito(
          fontSize: 15,
          color: Colors.grey[700],
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _memberCard(Map<String, dynamic> member) {
    final memberId = member['id']?.toString();
    final isRemoving = _removingMemberId == memberId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _purple.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.person_rounded, color: _purple, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName(member),
                  style: GoogleFonts.nunito(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _deepPurple,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (member['email'] ?? '').toString(),
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _roleLabel(member),
                  style: GoogleFonts.nunito(
                    fontSize: 14,
                    color: _purple,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          isRemoving
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              : IconButton(
                  onPressed: () => _removeMember(member),
                  icon: const Icon(
                    Icons.remove_circle_outline_rounded,
                    color: Colors.redAccent,
                  ),
                  tooltip: 'Remove member',
                ),
        ],
      ),
    );
  }
}

class _AddMemberModal extends StatefulWidget {
  final Future<void> Function() onSuccess;

  const _AddMemberModal({required this.onSuccess});

  @override
  State<_AddMemberModal> createState() => _AddMemberModalState();
}

class _AddMemberModalState extends State<_AddMemberModal> {
  final _emailCtrl = TextEditingController();
  String? _role;
  bool _saving = false;

  final roles = const {
    'family': 'Family',
    'caregiver': 'Caregiver',
    'medical_team': 'Medical Team',
  };

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickRole() async {
    FocusScope.of(context).unfocus();

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _borderColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Select role',
                  style: GoogleFonts.nunito(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _deepPurple,
                  ),
                ),
                const SizedBox(height: 10),
                ...roles.entries.map(
                  (entry) => Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _borderColor),
                    ),
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 2,
                      ),
                      title: Text(
                        entry.value,
                        style: GoogleFonts.nunito(
                          fontWeight: FontWeight.w800,
                          color: _deepPurple,
                        ),
                      ),
                      trailing: _role == entry.key
                          ? const Icon(Icons.check, color: _purple)
                          : null,
                      onTap: () => Navigator.of(ctx).pop(entry.key),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (selected == null) return;
    setState(() => _role = selected);
  }

  Future<void> _sendInvite() async {
    final teamId = SessionManager().currentCareTeam?.id;
    final user = SupabaseService().client.auth.currentUser;

    final email = _emailCtrl.text.trim();
    final role = (_role ?? '').trim();

    if (teamId == null) return;
    if (email.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email is required')));
      return;
    }
    if (role.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a role')));
      return;
    }

    setState(() => _saving = true);

    try {
      final code = generateInviteCode();
      final service = SupabaseService();
      final isDocx = await service.isDocxSchema();

      if (isDocx) {
        await service.client.from('invite_code').upsert({
          'care_space_id': teamId,
          'user_profile_id': user?.id,
          'invite_token': code,
          'invite_email': email,
          'expires_at': DateTime.now()
              .add(const Duration(days: 5))
              .toIso8601String(),
        }, onConflict: 'care_space_id,invite_email');
      } else {
        await service.client.from('invites').insert({
          'care_team_id': teamId,
          'invite_code': code,
          'email': email,
          'role': role,
          'created_by': user?.id,
          'expires_at': DateTime.now()
              .add(const Duration(days: 5))
              .toIso8601String(),
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Invite Code: $code')));

      await widget.onSuccess();
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error sending invite: $e')));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: _borderColor,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Add Member',
              style: GoogleFonts.nunito(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _deepPurple,
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: 'Email',
                labelStyle: GoogleFonts.nunito(),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _borderColor),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _saving ? null : _pickRole,
              child: AbsorbPointer(
                child: TextField(
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Role',
                    labelStyle: GoogleFonts.nunito(),
                    hintText: 'Select role',
                    hintStyle: GoogleFonts.nunito(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    suffixIcon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: _deepPurple,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(color: _borderColor),
                    ),
                  ),
                  controller: TextEditingController(
                    text: _role == null ? '' : (roles[_role] ?? ''),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _sendInvite,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Send Invite',
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
  }
}
