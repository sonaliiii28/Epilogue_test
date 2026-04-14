-- Supabase (Postgres) schema for Epilogue
-- Run this in your Supabase SQL editor or psql to create required tables.

-- Care teams
CREATE TABLE IF NOT EXISTS care_teams (
  id uuid PRIMARY KEY,
  patient_first_name text,
  hospice_org_id text,
  nurse_line_number text,
  created_at timestamptz DEFAULT now()
);

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
