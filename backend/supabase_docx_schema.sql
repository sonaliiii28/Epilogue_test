-- DOCX source-of-truth schema (extracted from Untitled document (1).docx)
--
-- This script is designed to be pasted into Supabase SQL editor.
-- It is idempotent (safe to re-run) and focuses on creating the tables/columns
-- from the document.

-- Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Helpers
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

-- Preflight: if a previous run created partial tables with old column names,
-- rename them to the DOCX names so policies/foreign keys don't fail.
DO $$
BEGIN
  -- user_profile: common legacy column name is "id".
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'user_profile'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'user_profile' AND lower(column_name) = 'user_profile_id'
    ) AND EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'user_profile' AND column_name = 'id'
    ) THEN
      EXECUTE 'ALTER TABLE public.user_profile RENAME COLUMN id TO user_profile_id';
    END IF;

    -- If still not in DOCX shape, drop so it can be recreated cleanly.
    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'user_profile' AND lower(column_name) = 'user_profile_id'
    ) THEN
      EXECUTE 'DROP TABLE public.user_profile CASCADE';
    END IF;
  END IF;

  -- care_team_member: common legacy column names are "user_id" and "care_team_id".
  IF EXISTS (
    SELECT 1
    FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'care_team_member'
  ) THEN
    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'care_team_member' AND lower(column_name) = 'user_profile_id'
    ) AND EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'care_team_member' AND column_name = 'user_id'
    ) THEN
      EXECUTE 'ALTER TABLE public.care_team_member RENAME COLUMN user_id TO user_profile_id';
    END IF;

    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'care_team_member' AND lower(column_name) = 'care_space_id'
    ) AND EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'care_team_member' AND column_name = 'care_team_id'
    ) THEN
      EXECUTE 'ALTER TABLE public.care_team_member RENAME COLUMN care_team_id TO care_space_id';
    END IF;

    -- If still not in DOCX shape, drop so it can be recreated cleanly.
    IF NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'care_team_member' AND lower(column_name) = 'user_profile_id'
    ) OR NOT EXISTS (
      SELECT 1
      FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = 'care_team_member' AND lower(column_name) = 'care_space_id'
    ) THEN
      EXECUTE 'DROP TABLE public.care_team_member CASCADE';
    END IF;
  END IF;
END $$;

-- 1) user_profile
CREATE TABLE IF NOT EXISTS public.user_profile (
  user_profile_id uuid PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  full_name text NOT NULL,
  preferred_name text,
  phone text,
  profile_pic text,
  preferred_language text,
  timezone text,
  account_type text,
  is_active boolean DEFAULT true,
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_user_profile_set_updated_at ON public.user_profile;
CREATE TRIGGER trg_user_profile_set_updated_at
BEFORE UPDATE ON public.user_profile
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.user_profile ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_profile_select_own" ON public.user_profile;
CREATE POLICY "user_profile_select_own"
ON public.user_profile
FOR SELECT
TO authenticated
USING (auth.uid() = user_profile_id);

DROP POLICY IF EXISTS "user_profile_insert_own" ON public.user_profile;
CREATE POLICY "user_profile_insert_own"
ON public.user_profile
FOR INSERT
TO authenticated
WITH CHECK (auth.uid() = user_profile_id);

DROP POLICY IF EXISTS "user_profile_update_own" ON public.user_profile;
CREATE POLICY "user_profile_update_own"
ON public.user_profile
FOR UPDATE
TO authenticated
USING (auth.uid() = user_profile_id)
WITH CHECK (auth.uid() = user_profile_id);

-- 2) role_list
CREATE TABLE IF NOT EXISTS public.role_list (
  role_list_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE
);

-- 3) hospice_agency_list
CREATE TABLE IF NOT EXISTS public.hospice_agency_list (
  agency_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  medicare_id text UNIQUE,
  npi text UNIQUE,
  phone text,
  fax text,
  address_line1 text,
  city text,
  state char(2),
  zip text,
  zip_code text,
  country char(2) DEFAULT 'US',
  county text,
  website_url text,
  hope_compliance_enabled boolean DEFAULT false,
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE IF EXISTS public.hospice_agency_list
  ADD COLUMN IF NOT EXISTS county text;

DROP TRIGGER IF EXISTS trg_hospice_agency_list_set_updated_at ON public.hospice_agency_list;
CREATE TRIGGER trg_hospice_agency_list_set_updated_at
BEFORE UPDATE ON public.hospice_agency_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.hospice_agency_list ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS hospice_agency_list_select_public ON public.hospice_agency_list;
CREATE POLICY hospice_agency_list_select_public
ON public.hospice_agency_list
FOR SELECT
TO anon, authenticated
USING (deleted_at IS NULL);

GRANT SELECT ON TABLE public.hospice_agency_list TO anon, authenticated;

-- 3b) homecare_provider_list
CREATE TABLE IF NOT EXISTS public.homecare_provider_list (
  homecare_provider_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  phone text,
  city text,
  state char(2),
  zip_code text,
  county text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_homecare_provider_list_set_updated_at ON public.homecare_provider_list;
CREATE TRIGGER trg_homecare_provider_list_set_updated_at
BEFORE UPDATE ON public.homecare_provider_list
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.homecare_provider_list ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS homecare_provider_list_select_public ON public.homecare_provider_list;
CREATE POLICY homecare_provider_list_select_public
ON public.homecare_provider_list
FOR SELECT
TO anon, authenticated
USING (true);

GRANT SELECT ON TABLE public.homecare_provider_list TO anon, authenticated;

-- 4) care_space
CREATE TABLE IF NOT EXISTS public.care_space (
  care_space_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agency_id uuid REFERENCES public.hospice_agency_list (agency_id),
  homecare_provider_id uuid REFERENCES public.homecare_provider_list (homecare_provider_id),
  full_name text NOT NULL,
  date_of_birth date,
  sex text,
  preferred_language text,
  status text DEFAULT 'active',
  enrollment_date date,
  discharge_date date,
  care_setting text,
  address_line1 text,
  emergency_contact_name text,
  emergency_contact_phone text,
  dnr_on_file boolean,
  advance_directive_on_file boolean,
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_care_space_set_updated_at ON public.care_space;
CREATE TRIGGER trg_care_space_set_updated_at
BEFORE UPDATE ON public.care_space
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.care_space ENABLE ROW LEVEL SECURITY;

-- 5) patient_diagnosis
CREATE TABLE IF NOT EXISTS public.patient_diagnosis (
  patient_diagnosis_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_space_id uuid NOT NULL REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,
  icd10_code text,
  description text,
  is_primary boolean,
  onset_date date,
  noted_by_id uuid REFERENCES public.user_profile (user_profile_id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_patient_diagnosis_set_updated_at ON public.patient_diagnosis;
CREATE TRIGGER trg_patient_diagnosis_set_updated_at
BEFORE UPDATE ON public.patient_diagnosis
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 6) care_team_member
CREATE TABLE IF NOT EXISTS public.care_team_member (
  care_team_member_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_space_id uuid NOT NULL REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,
  user_profile_id uuid NOT NULL REFERENCES public.user_profile (user_profile_id) ON DELETE CASCADE,
  role_list_id uuid REFERENCES public.role_list (role_list_id),
  is_primary boolean DEFAULT false,
  is_active boolean DEFAULT true,
  added_by uuid REFERENCES public.user_profile (user_profile_id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT care_team_member_unique UNIQUE (care_space_id, user_profile_id)
);

DROP TRIGGER IF EXISTS trg_care_team_member_set_updated_at ON public.care_team_member;
CREATE TRIGGER trg_care_team_member_set_updated_at
BEFORE UPDATE ON public.care_team_member
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.care_team_member ENABLE ROW LEVEL SECURITY;

-- Avoid recursive RLS: membership check via SECURITY DEFINER function.
-- This lets members see other members in the same care space without
-- referencing `care_team_member` from inside a `care_team_member` policy.
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

-- Members can select rows for care spaces they are in.
DROP POLICY IF EXISTS "care_team_member_select_for_members" ON public.care_team_member;
CREATE POLICY "care_team_member_select_for_members"
ON public.care_team_member
FOR SELECT
TO authenticated
USING (
  public.is_active_member_of_care_space(care_space_id)
);

-- Users can insert their own membership row (typically done when accepting an invite).
DROP POLICY IF EXISTS "care_team_member_insert_self" ON public.care_team_member;
CREATE POLICY "care_team_member_insert_self"
ON public.care_team_member
FOR INSERT
TO authenticated
WITH CHECK (user_profile_id = auth.uid());

-- Users can update their own membership row.
DROP POLICY IF EXISTS "care_team_member_update_self" ON public.care_team_member;
CREATE POLICY "care_team_member_update_self"
ON public.care_team_member
FOR UPDATE
TO authenticated
USING (user_profile_id = auth.uid())
WITH CHECK (user_profile_id = auth.uid());

-- Allow members to view care spaces they belong to.
DROP POLICY IF EXISTS "care_space_select_for_members" ON public.care_space;
CREATE POLICY "care_space_select_for_members"
ON public.care_space
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.care_team_member m
    WHERE m.care_space_id = care_space.care_space_id
      AND m.user_profile_id = auth.uid()
      AND m.is_active = true
  )
);

-- Allow any authenticated user to create a care space (used by onboarding).
DROP POLICY IF EXISTS "care_space_insert_authenticated" ON public.care_space;
CREATE POLICY "care_space_insert_authenticated"
ON public.care_space
FOR INSERT
TO authenticated
WITH CHECK (true);

-- Allow members of a care space to update it.
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

-- 7) invite_code
CREATE TABLE IF NOT EXISTS public.invite_code (
  invite_code_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_space_id uuid NOT NULL REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,
  user_profile_id uuid REFERENCES public.user_profile (user_profile_id),
  role_list_id uuid REFERENCES public.role_list (role_list_id),
  invite_token text NOT NULL UNIQUE,
  invite_email text NOT NULL,
  invited_at timestamptz DEFAULT now(),
  accepted_at timestamptz,
  expires_at timestamptz,
  CONSTRAINT invite_code_unique UNIQUE (care_space_id, invite_email)
);

ALTER TABLE public.invite_code ENABLE ROW LEVEL SECURITY;

-- Members can view invites for their care spaces.
-- Invited users can also view their own invite by email (required to accept invites).
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

-- Members can create invites for care spaces they belong to (used by CareTeamScreen).
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

-- Members can update invites for their care spaces (e.g. refresh token/expiry).
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

-- Invited users can mark their invite accepted.
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

-- 17) medication_list (lookup)
CREATE TABLE IF NOT EXISTS public.medication_list (
  medication_list_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text,
  brand_name text,
  available_strengths text,
  form text,
  route text,
  dose_unit text,
  is_active boolean DEFAULT true
);

-- Allow lookup reads from clients (RLS disabled).
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON TABLE public.medication_list TO anon, authenticated;

-- 18) symptom_list (lookup)
CREATE TABLE IF NOT EXISTS public.symptom_list (
  symptom_list_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text UNIQUE,
  is_hope boolean DEFAULT false
);

-- 19) skin_wound_list (lookup)
CREATE TABLE IF NOT EXISTS public.skin_wound_list (
  skin_wound_list_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text
);

-- 20) skin_treatment_list (lookup)
CREATE TABLE IF NOT EXISTS public.skin_treatment_list (
  skin_treatment_list_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE
);

-- 8) medication
CREATE TABLE IF NOT EXISTS public.medication (
  medication_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_space_id uuid REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,
  medication_list_id uuid REFERENCES public.medication_list (medication_list_id),
  name text,
  frequency text,
  notes text,
  prn_indication text,
  ordered_by_name text,
  ordered_date date,
  is_active boolean DEFAULT true,
  created_by uuid REFERENCES public.user_profile (user_profile_id),
  deleted_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_medication_set_updated_at ON public.medication;
CREATE TRIGGER trg_medication_set_updated_at
BEFORE UPDATE ON public.medication
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 9) medication_log
CREATE TABLE IF NOT EXISTS public.medication_log (
  medication_log_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  medication_id uuid REFERENCES public.medication (medication_id) ON DELETE CASCADE,
  care_space_id uuid REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,
  administered_by_id uuid REFERENCES public.user_profile (user_profile_id),
  administered_at timestamptz,
  notes text,
  created_at timestamptz DEFAULT now()
);

-- 10) symptom_log
CREATE TABLE IF NOT EXISTS public.symptom_log (
  symptom_log_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_space_id uuid REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,
  symptom_list_id uuid REFERENCES public.symptom_list (symptom_list_id),
  custom_name text,
  severity smallint,
  observed_at timestamptz,
  notes text,
  voice_note_url text,
  created_by uuid REFERENCES public.user_profile (user_profile_id),
  created_at timestamptz DEFAULT now()
);

-- 11) skin_wound_log
CREATE TABLE IF NOT EXISTS public.skin_wound_log (
  skin_wound_log_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_space_id uuid REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,
  skin_wound_list_id uuid REFERENCES public.skin_wound_list (skin_wound_list_id),
  skin_treatment_list_id uuid REFERENCES public.skin_treatment_list (skin_treatment_list_id),
  content_image_url text,
  observed_at timestamptz,
  notes text,
  voice_note_url text,
  created_by uuid REFERENCES public.user_profile (user_profile_id),
  created_at timestamptz DEFAULT now()
);

-- 12) nurse_visit
CREATE TABLE IF NOT EXISTS public.nurse_visit (
  nurse_visit_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_space_id uuid REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,
  nurse_id uuid REFERENCES public.user_profile (user_profile_id),
  scheduled_at timestamptz,
  arrived_at timestamptz,
  departed_at timestamptz,
  visit_type text,
  notes text,
  voice_note_url text,
  created_by uuid REFERENCES public.user_profile (user_profile_id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_nurse_visit_set_updated_at ON public.nurse_visit;
CREATE TRIGGER trg_nurse_visit_set_updated_at
BEFORE UPDATE ON public.nurse_visit
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 13) care_plan
CREATE TABLE IF NOT EXISTS public.care_plan (
  care_plan_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_space_id uuid REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,
  version smallint,
  is_current boolean DEFAULT true,
  effective_date date,
  goals text,
  special_instructions text,
  created_by uuid REFERENCES public.user_profile (user_profile_id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_care_plan_set_updated_at ON public.care_plan;
CREATE TRIGGER trg_care_plan_set_updated_at
BEFORE UPDATE ON public.care_plan
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 14) quick_notes
CREATE TABLE IF NOT EXISTS public.quick_notes (
  quick_notes_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_space_id uuid REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,
  user_profile_id uuid REFERENCES public.user_profile (user_profile_id),
  content_text text NOT NULL,
  content_image_url text,
  voice_note_url text,
  visibility text,
  is_pinned boolean DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  deleted_at timestamptz
);

DROP TRIGGER IF EXISTS trg_quick_notes_set_updated_at ON public.quick_notes;
CREATE TRIGGER trg_quick_notes_set_updated_at
BEFORE UPDATE ON public.quick_notes
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 15) moment
CREATE TABLE IF NOT EXISTS public.moment (
  moment_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_space_id uuid REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,
  content_text text NOT NULL,
  content_image_url text,
  voice_note_url text,
  moment_date date,
  created_by uuid REFERENCES public.user_profile (user_profile_id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_moment_set_updated_at ON public.moment;
CREATE TRIGGER trg_moment_set_updated_at
BEFORE UPDATE ON public.moment
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- 16) notification
CREATE TABLE IF NOT EXISTS public.notification (
  notification_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_profile_id uuid REFERENCES public.user_profile (user_profile_id),
  channel text,
  event_type text,
  title text,
  body text,
  status text,
  sent_at timestamptz,
  read_at timestamptz,
  data jsonb,
  created_at timestamptz DEFAULT now()
);

-- 21) message
CREATE TABLE IF NOT EXISTS public.message (
  message_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id uuid,
  sender_id uuid REFERENCES public.user_profile (user_profile_id),
  text_message text,
  message_type text,
  is_system_message boolean DEFAULT false,
  attachment_storage_path text,
  created_at timestamptz DEFAULT now()
);

-- 22) entitlement
CREATE TABLE IF NOT EXISTS public.entitlement (
  entitlement_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  role_list_id uuid REFERENCES public.role_list (role_list_id),
  can_view_care_space boolean,
  can_edit_care_space boolean,
  can_log_medication boolean,
  can_edit_medication boolean,
  can_view_medication boolean,
  can_log_symptom boolean,
  can_edit_symptom boolean,
  can_log_skin_wound boolean,
  can_view_skin_wound boolean,
  can_edit_skin_wound boolean,
  can_view_moment boolean,
  can_post_moment boolean,
  can_write_notes boolean,
  can_view_notes boolean,
  can_message boolean,
  created_at timestamptz,
  updated_at timestamptz
);
