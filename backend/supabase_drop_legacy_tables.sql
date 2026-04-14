-- DANGER: Drop legacy (pre-DOCX) tables and compatibility views
--
-- Run this ONLY if you are sure you want to permanently remove the old schema.
-- Recommended order in Supabase SQL Editor:
--   1) Run this script (drops legacy objects)
--   2) Run backend/supabase_docx_schema.sql (creates DOCX schema)
--
-- This script is idempotent.

-- 0) Drop compatibility views first (they can block table drops)
DO $$
DECLARE
	obj_name text;
	obj_kind "char";
BEGIN
	FOREACH obj_name IN ARRAY ARRAY[
		'care_teams',
		'members',
		'profile',
		'invites',
		'care_plans',
		'medications',
		'dose_logs',
		'symptom_events',
		'skin_wound_events',
		'observations',
		'moments',
		'calendar_events',
		'nurse_contacts',
		'check_ins',
		'shift_notes',
		'analytics_events'
	]
	LOOP
		SELECT c.relkind
		INTO obj_kind
		FROM pg_class c
		JOIN pg_namespace n ON n.oid = c.relnamespace
		WHERE n.nspname = 'public'
			AND c.relname = obj_name;

		IF obj_kind IS NULL THEN
			CONTINUE;
		ELSIF obj_kind = 'v' THEN
			EXECUTE format('DROP VIEW IF EXISTS public.%I CASCADE', obj_name);
		ELSIF obj_kind = 'm' THEN
			EXECUTE format('DROP MATERIALIZED VIEW IF EXISTS public.%I CASCADE', obj_name);
		ELSIF obj_kind = 'f' THEN
			EXECUTE format('DROP FOREIGN TABLE IF EXISTS public.%I CASCADE', obj_name);
		ELSIF obj_kind = 'S' THEN
			EXECUTE format('DROP SEQUENCE IF EXISTS public.%I CASCADE', obj_name);
		ELSE
			-- Tables ('r', 'p') and anything else we treat as a table-like object.
			EXECUTE format('DROP TABLE IF EXISTS public.%I CASCADE', obj_name);
		END IF;
	END LOOP;
END $$;

-- 1) Drop legacy tables (and any renamed __legacy backups)
DROP TABLE IF EXISTS public.care_teams__legacy CASCADE;
DROP TABLE IF EXISTS public.members__legacy CASCADE;
DROP TABLE IF EXISTS public.profile__legacy CASCADE;
DROP TABLE IF EXISTS public.invites__legacy CASCADE;
DROP TABLE IF EXISTS public.care_plans__legacy CASCADE;
DROP TABLE IF EXISTS public.medications__legacy CASCADE;
DROP TABLE IF EXISTS public.dose_logs__legacy CASCADE;
DROP TABLE IF EXISTS public.symptom_events__legacy CASCADE;
DROP TABLE IF EXISTS public.skin_wound_events__legacy CASCADE;
DROP TABLE IF EXISTS public.observations__legacy CASCADE;
DROP TABLE IF EXISTS public.moments__legacy CASCADE;
DROP TABLE IF EXISTS public.calendar_events__legacy CASCADE;
DROP TABLE IF EXISTS public.nurse_contacts__legacy CASCADE;
DROP TABLE IF EXISTS public.check_ins__legacy CASCADE;
DROP TABLE IF EXISTS public.shift_notes__legacy CASCADE;
DROP TABLE IF EXISTS public.analytics_events__legacy CASCADE;

DROP TABLE IF EXISTS public.calendar_events CASCADE;
DROP TABLE IF EXISTS public.nurse_contacts CASCADE;
DROP TABLE IF EXISTS public.check_ins CASCADE;
DROP TABLE IF EXISTS public.shift_notes CASCADE;
DROP TABLE IF EXISTS public.analytics_events CASCADE;
DROP TABLE IF EXISTS public.moments CASCADE;
DROP TABLE IF EXISTS public.observations CASCADE;
DROP TABLE IF EXISTS public.skin_wound_events CASCADE;
DROP TABLE IF EXISTS public.symptom_events CASCADE;
DROP TABLE IF EXISTS public.dose_logs CASCADE;
DROP TABLE IF EXISTS public.medications CASCADE;
DROP TABLE IF EXISTS public.care_plans CASCADE;
DROP TABLE IF EXISTS public.invites CASCADE;
DROP TABLE IF EXISTS public.members CASCADE;
DROP TABLE IF EXISTS public.profile CASCADE;
DROP TABLE IF EXISTS public.care_teams CASCADE;

-- 2) Drop legacy helper functions/triggers if present
DROP FUNCTION IF EXISTS public.generate_invite_code(int) CASCADE;
DROP FUNCTION IF EXISTS public.create_invite_for_new_care_team() CASCADE;

-- Note: Do NOT drop DOCX tables here (user_profile, care_space, etc).
-- After running this script, run backend/supabase_docx_schema.sql to create the new schema.
