-- Patch: RLS policies needed for Flutter app flows (DOCX schema)
--
-- Run this in Supabase Dashboard → SQL Editor.
-- Safe to re-run.

-- care_team_member: fix recursive SELECT policy (42P17 infinite recursion)
ALTER TABLE IF EXISTS public.care_team_member ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.is_active_member_of_care_space(_care_space_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.care_team_member m
    WHERE m.care_space_id = _care_space_id
      AND m.user_profile_id = auth.uid()
      AND m.is_active = true
  );
$$;

REVOKE ALL ON FUNCTION public.is_active_member_of_care_space(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_active_member_of_care_space(uuid) TO authenticated;

DROP POLICY IF EXISTS "care_team_member_select_for_members" ON public.care_team_member;
CREATE POLICY "care_team_member_select_for_members"
ON public.care_team_member
FOR SELECT
TO authenticated
USING (public.is_active_member_of_care_space(care_space_id));

-- Allow users to create/update their own membership row.
DROP POLICY IF EXISTS "care_team_member_insert_self" ON public.care_team_member;
CREATE POLICY "care_team_member_insert_self"
ON public.care_team_member
FOR INSERT
TO authenticated
WITH CHECK (user_profile_id = auth.uid());

DROP POLICY IF EXISTS "care_team_member_update_self" ON public.care_team_member;
CREATE POLICY "care_team_member_update_self"
ON public.care_team_member
FOR UPDATE
TO authenticated
USING (user_profile_id = auth.uid())
WITH CHECK (user_profile_id = auth.uid());

-- care_space: allow authenticated inserts + member updates
ALTER TABLE IF EXISTS public.care_space ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "care_space_insert_authenticated" ON public.care_space;
CREATE POLICY "care_space_insert_authenticated"
ON public.care_space
FOR INSERT
TO authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "care_space_update_for_members" ON public.care_space;
CREATE POLICY "care_space_update_for_members"
ON public.care_space
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.care_team_member m
    WHERE m.care_space_id = care_space.care_space_id
      AND m.user_profile_id = auth.uid()
      AND m.is_active = true
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.care_team_member m
    WHERE m.care_space_id = care_space.care_space_id
      AND m.user_profile_id = auth.uid()
      AND m.is_active = true
  )
);

-- invite_code: members can create/update; invited users can read/update their invite by email
ALTER TABLE IF EXISTS public.invite_code ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "invite_code_select_for_members_or_invited" ON public.invite_code;
CREATE POLICY "invite_code_select_for_members_or_invited"
ON public.invite_code
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.care_team_member me
    WHERE me.care_space_id = invite_code.care_space_id
      AND me.user_profile_id = auth.uid()
      AND me.is_active = true
  )
  OR lower(invite_email) = lower((auth.jwt() ->> 'email')::text)
  OR invite_email = 'public'
);

DROP POLICY IF EXISTS "invite_code_insert_for_members" ON public.invite_code;
CREATE POLICY "invite_code_insert_for_members"
ON public.invite_code
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.care_team_member me
    WHERE me.care_space_id = invite_code.care_space_id
      AND me.user_profile_id = auth.uid()
      AND me.is_active = true
  )
);

DROP POLICY IF EXISTS "invite_code_update_for_members" ON public.invite_code;
CREATE POLICY "invite_code_update_for_members"
ON public.invite_code
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.care_team_member me
    WHERE me.care_space_id = invite_code.care_space_id
      AND me.user_profile_id = auth.uid()
      AND me.is_active = true
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.care_team_member me
    WHERE me.care_space_id = invite_code.care_space_id
      AND me.user_profile_id = auth.uid()
      AND me.is_active = true
  )
);

DROP POLICY IF EXISTS "invite_code_update_for_invited_email" ON public.invite_code;
CREATE POLICY "invite_code_update_for_invited_email"
ON public.invite_code
FOR UPDATE
TO authenticated
USING (
  lower(invite_email) = lower((auth.jwt() ->> 'email')::text)
)
WITH CHECK (
  lower(invite_email) = lower((auth.jwt() ->> 'email')::text)
);

-- Public invite: allow an authenticated user to accept it once.
DROP POLICY IF EXISTS "invite_code_update_for_public" ON public.invite_code;
CREATE POLICY "invite_code_update_for_public"
ON public.invite_code
FOR UPDATE
TO authenticated
USING (
  invite_email = 'public'
  AND accepted_at IS NULL
)
WITH CHECK (
  invite_email = 'public'
  AND user_profile_id = auth.uid()
  AND accepted_at IS NOT NULL
);

-- hospice_agency_list: should be readable during signup (anon)
ALTER TABLE IF EXISTS public.hospice_agency_list ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "hospice_agency_list_select_public" ON public.hospice_agency_list;
CREATE POLICY "hospice_agency_list_select_public"
ON public.hospice_agency_list
FOR SELECT
TO anon, authenticated
USING (deleted_at IS NULL);

GRANT SELECT ON TABLE public.hospice_agency_list TO anon, authenticated;

-- medication_list: lookup should be readable in the app
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON TABLE public.medication_list TO anon, authenticated;

-- PostgREST schema cache refresh (optional)
NOTIFY pgrst, 'reload schema';
