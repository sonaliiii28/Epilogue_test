-- Backward-compatibility views (old table names -> new tables)
--
-- IMPORTANT:
-- - Does NOT delete data.
-- - If an old TABLE exists with the same name, it is renamed to `__legacy`.
-- - Then a VIEW with the old name is created pointing at the new table.
--
-- Run AFTER applying the new schema.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION public._compat_rename_table_to_legacy(old_name text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  kind char;
  legacy_name text;
BEGIN
  SELECT c.relkind
    INTO kind
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = old_name;

  -- Nothing to do if object doesn't exist.
  IF kind IS NULL THEN
    RETURN;
  END IF;

  -- If it's already a view, keep it.
  IF kind = 'v' THEN
    RETURN;
  END IF;

  -- Only rename real tables.
  IF kind <> 'r' THEN
    RETURN;
  END IF;

  legacy_name := old_name || '__legacy';

  IF to_regclass('public.' || legacy_name) IS NOT NULL THEN
    RAISE EXCEPTION 'Cannot rename public.% because public.% already exists. Rename manually.', old_name, legacy_name;
  END IF;

  EXECUTE format('ALTER TABLE public.%I RENAME TO %I', old_name, legacy_name);
END;
$$;

CREATE OR REPLACE FUNCTION public._compat_create_simple_view(view_name text, target_table text)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  -- Ensure any old table is preserved.
  PERFORM public._compat_rename_table_to_legacy(view_name);

  -- Create/replace the view.
  EXECUTE format('CREATE OR REPLACE VIEW public.%I AS SELECT * FROM public.%I', view_name, target_table);

  -- PostgREST requires privileges on the view itself.
  EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', view_name);
  EXECUTE format('GRANT SELECT ON public.%I TO anon', view_name);
END;
$$;

-- ----------------------------------------
-- EXACT views requested
-- ----------------------------------------

SELECT public._compat_create_simple_view('care_teams', 'care_space');
SELECT public._compat_create_simple_view('members', 'care_team_member');
SELECT public._compat_create_simple_view('profile', 'user_profile');
SELECT public._compat_create_simple_view('dose_logs', 'medication_log');
SELECT public._compat_create_simple_view('symptom_events', 'symptom_log');
SELECT public._compat_create_simple_view('skin_wound_events', 'skin_wound_log');
SELECT public._compat_create_simple_view('moments', 'moment');
SELECT public._compat_create_simple_view('observations', 'quick_notes');

-- Also needed by the app's current codebase (old -> new mapping list)
SELECT public._compat_create_simple_view('medications', 'medication');
SELECT public._compat_create_simple_view('care_plans', 'care_plan');
