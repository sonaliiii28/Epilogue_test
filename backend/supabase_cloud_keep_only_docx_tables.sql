-- Supabase Cloud SQL Editor script
-- Purpose: Keep ONLY the DOCX tables in the `public` schema and drop all other
--          user-defined tables/views/materialized views/foreign tables/sequences.
--
-- WARNING: DESTRUCTIVE. This will delete data in non-whitelisted tables.
-- Safe to re-run.
--
-- Whitelist (kept):
--   user_profile, role_list, hospice_agency_list, care_space, patient_diagnosis,
--   care_team_member, invite_code, medication_list, symptom_list,
--   skin_wound_list, skin_treatment_list, medication, medication_log,
--   symptom_log, skin_wound_log, nurse_visit, care_plan, quick_notes,
--   moment, notification, message, entitlement

set local lock_timeout = '10s';
set local statement_timeout = '10min';

DO $$
DECLARE
  keep_tables text[] := ARRAY[
    'user_profile',
    'role_list',
    'hospice_agency_list',
    'care_space',
    'patient_diagnosis',
    'care_team_member',
    'invite_code',
    'medication_list',
    'symptom_list',
    'skin_wound_list',
    'skin_treatment_list',
    'medication',
    'medication_log',
    'symptom_log',
    'skin_wound_log',
    'nurse_visit',
    'care_plan',
    'quick_notes',
    'moment',
    'notification',
    'message',
    'entitlement'
  ];

  obj record;
  drop_stmt text;
  is_extension_owned boolean;
  is_owned_by_kept_table boolean;
BEGIN
  -- Drop everything in `public` that is not in the whitelist.
  -- We intentionally skip extension-owned objects (e.g. PostGIS tables/views)
  -- to avoid breaking extensions.

  FOR obj IN (
    SELECT c.oid, c.relname, c.relkind
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      AND c.relkind IN (
        'r', -- table
        'p', -- partitioned table
        'v', -- view
        'm', -- materialized view
        'f', -- foreign table
        'S'  -- sequence
      )
      AND c.relname <> ALL(keep_tables)
  ) LOOP
    SELECT EXISTS (
      SELECT 1
      FROM pg_depend d
      WHERE d.objid = obj.oid
        AND d.deptype = 'e' -- extension-owned dependency
    ) INTO is_extension_owned;

    IF is_extension_owned THEN
      CONTINUE;
    END IF;

    -- Don’t drop sequences owned by columns of kept tables.
    IF obj.relkind = 'S' THEN
      SELECT EXISTS (
        SELECT 1
        FROM pg_depend d
        JOIN pg_class t ON t.oid = d.refobjid
        JOIN pg_namespace tn ON tn.oid = t.relnamespace
        WHERE d.objid = obj.oid
          AND d.deptype = 'a' -- owned by (auto)
          AND tn.nspname = 'public'
          AND t.relname = ANY(keep_tables)
      ) INTO is_owned_by_kept_table;

      IF is_owned_by_kept_table THEN
        CONTINUE;
      END IF;
    END IF;

    drop_stmt := CASE obj.relkind
      WHEN 'v' THEN format('DROP VIEW IF EXISTS public.%I CASCADE', obj.relname)
      WHEN 'm' THEN format('DROP MATERIALIZED VIEW IF EXISTS public.%I CASCADE', obj.relname)
      WHEN 'f' THEN format('DROP FOREIGN TABLE IF EXISTS public.%I CASCADE', obj.relname)
      WHEN 'S' THEN format('DROP SEQUENCE IF EXISTS public.%I CASCADE', obj.relname)
      ELSE format('DROP TABLE IF EXISTS public.%I CASCADE', obj.relname)
    END;

    RAISE NOTICE '%', drop_stmt;
    EXECUTE drop_stmt;
  END LOOP;
END $$;
