import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/models.dart';
import 'supabase_service.dart';

class SessionManager {
  static final SessionManager _instance = SessionManager._internal();
  factory SessionManager() => _instance;
  SessionManager._internal();

  CareTeam? _currentCareTeam;
  Member? _currentMember;

  CareTeam? get currentCareTeam => _currentCareTeam;
  Member? get currentMember => _currentMember;

  Future<void> setSession(CareTeam team, Member member) async {
    _currentCareTeam = team;
    _currentMember = member;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('care_team_id', team.id);
    await prefs.setString('member_id', member.id);
  }

  Future<void> clearSession() async {
    _currentCareTeam = null;
    _currentMember = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('care_team_id');
    await prefs.remove('member_id');
  }

  Future<bool> loadSession() async {
    final prefs = await SharedPreferences.getInstance();
    final teamId = prefs.getString('care_team_id');
    final memberId = prefs.getString('member_id');

    if (teamId != null && memberId != null) {
      try {
        final service = SupabaseService();

        // Restore team using schema-aware adapter.
        final team = await service.getCareTeam(teamId);
        if (team == null) {
          await clearSession();
          return false;
        }

        // Restore member.
        Member? member;
        if (await service.isDocxSchema()) {
          final user = service.client.auth.currentUser;
          final uid = user?.id;
          if (uid != null) {
            final membership = await service.client
                .from('care_team_member')
                .select('is_primary, is_active')
                .eq('care_space_id', team.id)
                .eq('user_profile_id', uid)
                .eq('is_active', true)
                .maybeSingle();
            if (membership != null) {
              final profile = await service.client
                  .from('user_profile')
                  .select('full_name')
                  .eq('user_profile_id', uid)
                  .maybeSingle();
              final profileMap = (profile as Map?)?.cast<String, dynamic>();
              final fullName = (profileMap?['full_name'] ?? '')
                  .toString()
                  .trim();
              member = Member(
                id: uid,
                careTeamId: team.id,
                name: fullName.isEmpty ? 'Member' : fullName,
                email: (user?.email ?? '').trim().isEmpty
                    ? 'unknown@example.com'
                    : user!.email!.trim(),
                role: 'family',
                isAdmin: membership['is_primary'] == true,
              );
            }
          }
        } else {
          final memberResp = await Supabase.instance.client
              .from('members')
              .select()
              .eq('id', memberId)
              .maybeSingle();
          if (memberResp != null) {
            member = Member.fromJson(memberResp);
          }
        }

        if (member != null) {
          _currentCareTeam = team;
          _currentMember = member;
          return true;
        }
      } catch (_) {
        // If fetch fails, clear stale session
      }
      await clearSession();
      return false;
    }
    return false;
  }
}
