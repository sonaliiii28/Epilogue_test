-- Supabase (Postgres) schema for Epilogue
-- Run this in your Supabase SQL editor or psql to create required tables.

-- Care teams
CREATE TABLE IF NOT EXISTS care_teams (
  id uuid PRIMARY KEY,
  patient_first_name text,
  primary_caregiver_name text,
  primary_caregiver_email text,
  hospice_org_id text,
  hospice_name text,
  patient_address text,
  nurse_line_number text,
  join_code text,
  created_at timestamptz DEFAULT now()
);

-- Backfill-friendly upgrades (safe to run on existing DBs)
ALTER TABLE care_teams ADD COLUMN IF NOT EXISTS primary_caregiver_name text;
ALTER TABLE care_teams ADD COLUMN IF NOT EXISTS primary_caregiver_email text;
ALTER TABLE care_teams ADD COLUMN IF NOT EXISTS hospice_name text;
ALTER TABLE care_teams ADD COLUMN IF NOT EXISTS patient_address text;
ALTER TABLE care_teams ADD COLUMN IF NOT EXISTS join_code text;

-- Members
CREATE TABLE IF NOT EXISTS members (
  id uuid PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  name text NOT NULL,
  email text NOT NULL,
  role text,
  is_admin boolean DEFAULT false,
  magic_link_token text,
  access_pin text,
  joined_at timestamptz DEFAULT now(),
  last_active timestamptz
);
CREATE INDEX IF NOT EXISTS members_care_team_idx ON members(care_team_id);

-- Invites
-- Used by CareTeamScreen to generate time-limited invite codes.
CREATE TABLE IF NOT EXISTS invites (
  id bigserial PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  invite_code text NOT NULL,
  email text,
  role text,
  created_by uuid,
  expires_at timestamptz,
  created_at timestamptz DEFAULT now()
);

-- Backfill-friendly upgrades (safe to run on existing DBs)
ALTER TABLE invites ADD COLUMN IF NOT EXISTS care_team_id uuid;
ALTER TABLE invites ADD COLUMN IF NOT EXISTS invite_code text;
ALTER TABLE invites ADD COLUMN IF NOT EXISTS email text;
ALTER TABLE invites ADD COLUMN IF NOT EXISTS role text;
ALTER TABLE invites ADD COLUMN IF NOT EXISTS created_by uuid;
ALTER TABLE invites ADD COLUMN IF NOT EXISTS expires_at timestamptz;
ALTER TABLE invites ADD COLUMN IF NOT EXISTS created_at timestamptz;

CREATE INDEX IF NOT EXISTS invites_care_team_idx ON invites(care_team_id);
CREATE INDEX IF NOT EXISTS invites_email_idx ON invites(email);
CREATE INDEX IF NOT EXISTS invites_role_idx ON invites(role);
CREATE INDEX IF NOT EXISTS invites_created_at_idx ON invites(created_at);
CREATE UNIQUE INDEX IF NOT EXISTS invites_invite_code_unique ON invites(invite_code);

-- Auto-generate an invite code when a care team is created.
-- This keeps CareTeamScreen's invite code visible without requiring a manual "Add Member" action.
CREATE OR REPLACE FUNCTION generate_invite_code(len int DEFAULT 8)
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  chars text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  result text := '';
  i int;
BEGIN
  IF len IS NULL OR len < 4 THEN
    len := 8;
  END IF;

  FOR i IN 1..len LOOP
    result := result || substr(chars, 1 + floor(random() * length(chars))::int, 1);
  END LOOP;
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION create_invite_for_new_care_team()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  code text;
  attempts int := 0;
BEGIN
  -- Best-effort uniqueness in case of collision.
  LOOP
    attempts := attempts + 1;
    code := generate_invite_code(8);
    BEGIN
      INSERT INTO invites (care_team_id, invite_code, expires_at)
      VALUES (NEW.id, code, now() + interval '5 days');
      EXIT;
    EXCEPTION WHEN unique_violation THEN
      IF attempts >= 10 THEN
        RAISE;
      END IF;
    END;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_create_invite_for_new_care_team ON care_teams;
CREATE TRIGGER trg_create_invite_for_new_care_team
AFTER INSERT ON care_teams
FOR EACH ROW
EXECUTE FUNCTION create_invite_for_new_care_team();

-- One-time backfill (safe to re-run): create invites for existing care teams
-- that do not currently have an active (non-expired) invite.
INSERT INTO invites (care_team_id, invite_code, expires_at)
SELECT
  ct.id,
  generate_invite_code(8) AS invite_code,
  now() + interval '5 days' AS expires_at
FROM care_teams ct
WHERE NOT EXISTS (
  SELECT 1
  FROM invites i
  WHERE i.care_team_id = ct.id
    AND (i.expires_at IS NULL OR i.expires_at > now())
);

-- Care plans
CREATE TABLE IF NOT EXISTS care_plans (
  care_team_id uuid PRIMARY KEY REFERENCES care_teams(id) ON DELETE CASCADE,
  medications_summary text,
  positioning_turning text,
  transfers text,
  mobility text,
  personal_care text,
  other_instructions text,
  hospice_instructions text,
  updated_at timestamptz DEFAULT now(),
  updated_by_member_id uuid
);

-- Medications
CREATE TABLE IF NOT EXISTS medications (
  id uuid PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  name text,
  strength text,
  typical_dose text,
  route text,
  pattern text,
  schedule_details text,
  prn_reason_tags jsonb,
  notes text,
  deprescribed_at timestamptz,
  created_at timestamptz DEFAULT now(),
  created_by_member_id uuid
);

-- Dose logs
CREATE TABLE IF NOT EXISTS dose_logs (
  id uuid PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  medication_id uuid,
  medication_name text,
  dose_time timestamptz DEFAULT now(),
  amount_given text,
  who_gave text,
  note text,
  logged_by_member_id uuid,
  logged_by_member_name text,
  editable_until timestamptz,
  event_id uuid
);

-- Symptom events
CREATE TABLE IF NOT EXISTS symptom_events (
  id uuid PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  symptoms jsonb,
  severity text,
  what_happened text,
  event_time timestamptz DEFAULT now(),
  created_by_member_id uuid,
  created_by_member_name text,
  editable_until timestamptz
);

-- Skin & wound events
CREATE TABLE IF NOT EXISTS skin_wound_events (
  id uuid PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  has_skin_condition boolean DEFAULT false,
  skin_condition text,
  treatments jsonb DEFAULT '[]'::jsonb,
  image_urls jsonb DEFAULT '[]'::jsonb,
  notes text,
  event_time timestamptz DEFAULT now(),
  deleted_at timestamptz,
  created_by_member_id uuid,
  created_by_member_name text,
  editable_until timestamptz
);

-- Nurse contacts
CREATE TABLE IF NOT EXISTS nurse_contacts (
  id uuid PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  symptom_event_id uuid,
  contact_method text,
  status text,
  message_body text,
  attempted_at timestamptz DEFAULT now(),
  attempted_by_member_id uuid
);

-- Observations
CREATE TABLE IF NOT EXISTS observations (
  id uuid PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  content text,
  category text,
  created_at timestamptz DEFAULT now(),
  created_by_member_id uuid,
  created_by_member_name text
);

-- Moments
CREATE TABLE IF NOT EXISTS moments (
  id uuid PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  category text,
  content text,
  visibility text,
  photo_url text,
  created_at timestamptz DEFAULT now(),
  created_by_member_id uuid,
  created_by_member_name text
);

-- Calendar events
CREATE TABLE IF NOT EXISTS calendar_events (
  id uuid PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  event_type text,
  title text,
  date date,
  time_window_start time,
  time_window_end time,
  visitor_role text,
  notes text,
  created_at timestamptz DEFAULT now(),
  created_by_member_id uuid
);

-- Check-ins
CREATE TABLE IF NOT EXISTS check_ins (
  id uuid PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  member_id uuid,
  question_text text,
  response text,
  created_at timestamptz DEFAULT now()
);

-- Shift notes
CREATE TABLE IF NOT EXISTS shift_notes (
  id uuid PRIMARY KEY,
  care_team_id uuid REFERENCES care_teams(id) ON DELETE CASCADE,
  member_id uuid,
  member_name text,
  shift_date date,
  arrived_at timestamptz,
  left_at timestamptz,
  tasks_completed jsonb,
  what_i_noticed text,
  flag_for_primary_only boolean DEFAULT false,
  created_at timestamptz DEFAULT now()
);

-- Analytics events
CREATE TABLE IF NOT EXISTS analytics_events (
  id bigserial PRIMARY KEY,
  event_type text,
  care_team_id uuid,
  member_role text,
  properties jsonb,
  timestamp timestamptz DEFAULT now()
);

-- Helpful indices
CREATE INDEX IF NOT EXISTS idx_analytics_care_team ON analytics_events(care_team_id);
CREATE INDEX IF NOT EXISTS idx_medications_care_team ON medications(care_team_id);
CREATE INDEX IF NOT EXISTS idx_symptom_events_care_team ON symptom_events(care_team_id);
CREATE INDEX IF NOT EXISTS idx_skin_wound_events_care_team ON skin_wound_events(care_team_id);
