-- Legacy compatibility views
--
-- Purpose:
--   Keep the Flutter app working with its existing (legacy) table names
--   while the real storage lives in the DOCX tables created by
--   backend/supabase_docx_schema.sql.
--
-- Usage (Supabase SQL editor):
--   1) Run backend/supabase_docx_schema.sql
--   2) Run this file
--
-- Notes:
--   - These objects are designed for PostgREST/Supabase usage.
--   - Many legacy models contain fields that do not exist in the DOCX schema.
--     For those, we persist a JSON payload inside the DOCX "notes" text fields
--     and project them back out through the views.
--   - If a legacy *table* already exists with the same name as a view below,
--     you must rename it (e.g., medications -> medications__legacy) before
--     creating the view.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------
-- Helpers
-- ------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.try_parse_jsonb(raw text)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF raw IS NULL OR btrim(raw) = '' THEN
    RETURN NULL;
  END IF;

  BEGIN
    RETURN raw::jsonb;
  EXCEPTION WHEN others THEN
    RETURN NULL;
  END;
END;
$$;

CREATE OR REPLACE FUNCTION public.jsonb_text_array(raw jsonb)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(array_agg(value), ARRAY[]::text[])
  FROM jsonb_array_elements_text(COALESCE(raw, '[]'::jsonb)) AS t(value);
$$;

CREATE OR REPLACE FUNCTION public.text_array_to_jsonb(arr text[])
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT COALESCE(to_jsonb(arr), '[]'::jsonb);
$$;

CREATE OR REPLACE FUNCTION public.assert_not_table(object_name text)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  kind char;
BEGIN
  SELECT c.relkind
    INTO kind
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND c.relname = object_name;

  IF kind = 'r' THEN
    RAISE EXCEPTION
      'public.% is a TABLE. Rename it (e.g., %__legacy) before creating the compatibility view.',
      object_name,
      object_name;
  END IF;
END;
$$;

-- ------------------------------------------------------------
-- medications  -> public.medication (+ medication_list)
-- ------------------------------------------------------------

SELECT public.assert_not_table('medications');

CREATE OR REPLACE VIEW public.medications AS
SELECT
  m.medication_id                         AS id,
  m.care_space_id                         AS care_team_id,
  COALESCE(m.name, ml.name)               AS name,
  COALESCE(
    ml.strength,
    (public.try_parse_jsonb(m.notes) ->> 'strength')
  )                                       AS strength,
  (public.try_parse_jsonb(m.notes) ->> 'typical_dose')        AS typical_dose,
  COALESCE(
    ml.route,
    (public.try_parse_jsonb(m.notes) ->> 'route')
  )                                       AS route,
  -- Legacy "pattern" is used by the app as the frequency/schedule choice.
  COALESCE(
    m.frequency,
    (public.try_parse_jsonb(m.notes) ->> 'pattern')
  )                                       AS pattern,
  (public.try_parse_jsonb(m.notes) ->> 'schedule_details')    AS schedule_details,
  COALESCE(
    (public.try_parse_jsonb(m.notes) ->> 'notes'),
    m.notes
  )                                       AS notes,
  public.jsonb_text_array(public.try_parse_jsonb(m.notes) -> 'prn_reason_tags') AS prn_reason_tags,
  m.created_at                            AS created_at,
  m.created_by                            AS created_by_member_id,
  m.deleted_at                            AS deprescribed_at
FROM public.medication m
LEFT JOIN public.medication_list ml
  ON ml.medication_list_id = m.medication_list_id;

CREATE OR REPLACE FUNCTION public.medications_view_write()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  med_id uuid;
  legacy jsonb;
  eff_care_team_id uuid;
  eff_name text;
  eff_pattern text;
  eff_notes text;
  eff_strength text;
  eff_typical_dose text;
  eff_route text;
  eff_schedule_details text;
  eff_prn_reason_tags text[];
  eff_created_by uuid;
  eff_created_at timestamptz;
  eff_deprescribed_at timestamptz;
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE public.medication
      SET deleted_at = COALESCE(deleted_at, now()),
          is_active = false,
          updated_at = now()
    WHERE medication_id = OLD.id::uuid;
    RETURN OLD;
  END IF;

  med_id := COALESCE(NULLIF(NEW.id::text, '')::uuid, gen_random_uuid());

  eff_care_team_id := COALESCE(
    NULLIF(NEW.care_team_id::text, '')::uuid,
    CASE WHEN TG_OP = 'UPDATE' THEN NULLIF(OLD.care_team_id::text, '')::uuid ELSE NULL END
  );
  eff_name := COALESCE(NEW.name, CASE WHEN TG_OP = 'UPDATE' THEN OLD.name ELSE NULL END);
  eff_pattern := COALESCE(NEW.pattern, CASE WHEN TG_OP = 'UPDATE' THEN OLD.pattern ELSE NULL END);
  eff_notes := COALESCE(NEW.notes, CASE WHEN TG_OP = 'UPDATE' THEN OLD.notes ELSE NULL END);
  eff_strength := COALESCE(NEW.strength, CASE WHEN TG_OP = 'UPDATE' THEN OLD.strength ELSE NULL END);
  eff_typical_dose := COALESCE(NEW.typical_dose, CASE WHEN TG_OP = 'UPDATE' THEN OLD.typical_dose ELSE NULL END);
  eff_route := COALESCE(NEW.route, CASE WHEN TG_OP = 'UPDATE' THEN OLD.route ELSE NULL END);
  eff_schedule_details := COALESCE(NEW.schedule_details, CASE WHEN TG_OP = 'UPDATE' THEN OLD.schedule_details ELSE NULL END);
  eff_prn_reason_tags := COALESCE(NEW.prn_reason_tags, CASE WHEN TG_OP = 'UPDATE' THEN OLD.prn_reason_tags ELSE NULL END);
  eff_created_by := COALESCE(
    NULLIF(NEW.created_by_member_id::text, '')::uuid,
    CASE WHEN TG_OP = 'UPDATE' THEN NULLIF(OLD.created_by_member_id::text, '')::uuid ELSE NULL END,
    auth.uid()
  );
  eff_created_at := COALESCE(NEW.created_at, CASE WHEN TG_OP = 'UPDATE' THEN OLD.created_at ELSE NULL END, now());
  eff_deprescribed_at := COALESCE(NEW.deprescribed_at, CASE WHEN TG_OP = 'UPDATE' THEN OLD.deprescribed_at ELSE NULL END);

  legacy := jsonb_build_object(
    'notes', eff_notes,
    'strength', eff_strength,
    'typical_dose', eff_typical_dose,
    'route', eff_route,
    'pattern', eff_pattern,
    'schedule_details', eff_schedule_details,
    'prn_reason_tags', public.text_array_to_jsonb(eff_prn_reason_tags)
  );

  -- Insert-or-update against DOCX medication table.
  INSERT INTO public.medication (
    medication_id,
    care_space_id,
    name,
    frequency,
    notes,
    is_active,
    created_by,
    created_at,
    updated_at,
    deleted_at
  ) VALUES (
    med_id,
    eff_care_team_id,
    eff_name,
    eff_pattern,
    legacy::text,
    CASE WHEN eff_pattern = 'inactive' THEN false ELSE true END,
    eff_created_by,
    eff_created_at,
    now(),
    eff_deprescribed_at
  )
  ON CONFLICT (medication_id)
  DO UPDATE SET
    care_space_id = EXCLUDED.care_space_id,
    name = EXCLUDED.name,
    frequency = EXCLUDED.frequency,
    notes = EXCLUDED.notes,
    is_active = EXCLUDED.is_active,
    created_by = COALESCE(public.medication.created_by, EXCLUDED.created_by),
    updated_at = now(),
    deleted_at = EXCLUDED.deleted_at;

  NEW.id := med_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_medications_view_write ON public.medications;
CREATE TRIGGER trg_medications_view_write
INSTEAD OF INSERT OR UPDATE OR DELETE ON public.medications
FOR EACH ROW
EXECUTE FUNCTION public.medications_view_write();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.medications TO authenticated;
GRANT SELECT ON public.medications TO anon;

-- ------------------------------------------------------------
-- dose_logs -> public.medication_log (+ medication)
-- ------------------------------------------------------------

SELECT public.assert_not_table('dose_logs');

CREATE OR REPLACE VIEW public.dose_logs AS
SELECT
  l.medication_log_id                                 AS id,
  l.care_space_id                                     AS care_team_id,
  l.medication_id                                     AS medication_id,
  COALESCE(m.name, ml.name)                           AS medication_name,
  l.administered_at                                   AS dose_time,
  (public.try_parse_jsonb(l.notes) ->> 'amount_given') AS amount_given,
  (public.try_parse_jsonb(l.notes) ->> 'who_gave')     AS who_gave,
  (public.try_parse_jsonb(l.notes) ->> 'note')         AS note,
  (public.try_parse_jsonb(l.notes) ->> 'logged_by_member_id')   AS logged_by_member_id,
  (public.try_parse_jsonb(l.notes) ->> 'logged_by_member_name') AS logged_by_member_name,
  NULL::timestamptz                                   AS editable_until,
  NULL::text                                          AS event_id,
  l.created_at                                        AS created_at
FROM public.medication_log l
LEFT JOIN public.medication m
  ON m.medication_id = l.medication_id
LEFT JOIN public.medication_list ml
  ON ml.medication_list_id = m.medication_list_id;

CREATE OR REPLACE FUNCTION public.dose_logs_view_write()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  log_id uuid;
  legacy jsonb;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.medication_log
    WHERE medication_log_id = OLD.id::uuid;
    RETURN OLD;
  END IF;

  log_id := COALESCE(NULLIF(NEW.id::text, '')::uuid, gen_random_uuid());

  legacy := jsonb_build_object(
    'amount_given', NEW.amount_given,
    'who_gave', NEW.who_gave,
    'note', NEW.note,
    'logged_by_member_id', NEW.logged_by_member_id,
    'logged_by_member_name', NEW.logged_by_member_name
  );

  INSERT INTO public.medication_log (
    medication_log_id,
    medication_id,
    care_space_id,
    administered_by_id,
    administered_at,
    notes,
    created_at
  ) VALUES (
    log_id,
    NULLIF(NEW.medication_id::text, '')::uuid,
    NULLIF(NEW.care_team_id::text, '')::uuid,
    auth.uid(),
    COALESCE(NEW.dose_time, now()),
    legacy::text,
    COALESCE(NEW.created_at, now())
  )
  ON CONFLICT (medication_log_id)
  DO UPDATE SET
    medication_id = EXCLUDED.medication_id,
    care_space_id = EXCLUDED.care_space_id,
    administered_at = EXCLUDED.administered_at,
    notes = EXCLUDED.notes;

  NEW.id := log_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_dose_logs_view_write ON public.dose_logs;
CREATE TRIGGER trg_dose_logs_view_write
INSTEAD OF INSERT OR UPDATE OR DELETE ON public.dose_logs
FOR EACH ROW
EXECUTE FUNCTION public.dose_logs_view_write();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.dose_logs TO authenticated;
GRANT SELECT ON public.dose_logs TO anon;

-- ------------------------------------------------------------
-- symptom_events -> public.symptom_log (+ symptom_list)
-- ------------------------------------------------------------

SELECT public.assert_not_table('symptom_events');

CREATE OR REPLACE VIEW public.symptom_events AS
SELECT
  s.symptom_log_id                         AS id,
  s.care_space_id                          AS care_team_id,
  ARRAY[
    COALESCE(NULLIF(btrim(s.custom_name), ''), sl.name, 'Symptom')
  ]                                        AS symptoms,
  COALESCE(
    (public.try_parse_jsonb(s.notes) ->> 'severity'),
    s.severity::text
  )                                        AS severity,
  COALESCE(
    (public.try_parse_jsonb(s.notes) ->> 'what_happened'),
    NULLIF(btrim(s.notes), '')
  )                                        AS what_happened,
  s.observed_at                            AS event_time,
  NULLIF((public.try_parse_jsonb(s.notes) ->> 'deleted_at'), '')::timestamptz AS deleted_at,
  (public.try_parse_jsonb(s.notes) ->> 'created_by_member_id')   AS created_by_member_id,
  (public.try_parse_jsonb(s.notes) ->> 'created_by_member_name') AS created_by_member_name,
  NULL::timestamptz                        AS editable_until,
  s.created_at                             AS created_at
FROM public.symptom_log s
LEFT JOIN public.symptom_list sl
  ON sl.symptom_list_id = s.symptom_list_id;

CREATE OR REPLACE FUNCTION public.symptom_events_view_write()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  ev_id uuid;
  symptom_name text;
  list_id uuid;
  existing_notes text;
  existing jsonb;
  legacy jsonb;
  eff_care_team_id uuid;
  eff_severity text;
  eff_what_happened text;
  eff_event_time timestamptz;
  eff_deleted_at timestamptz;
  eff_created_by_member_id text;
  eff_created_by_member_name text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.symptom_log
    WHERE symptom_log_id = OLD.id::uuid;
    RETURN OLD;
  END IF;

  ev_id := COALESCE(NULLIF(NEW.id::text, '')::uuid, gen_random_uuid());

  eff_care_team_id := COALESCE(
    NULLIF(NEW.care_team_id::text, '')::uuid,
    CASE WHEN TG_OP = 'UPDATE' THEN NULLIF(OLD.care_team_id::text, '')::uuid ELSE NULL END
  );
  eff_severity := COALESCE(NEW.severity, CASE WHEN TG_OP = 'UPDATE' THEN OLD.severity ELSE NULL END);
  eff_what_happened := COALESCE(NEW.what_happened, CASE WHEN TG_OP = 'UPDATE' THEN OLD.what_happened ELSE NULL END);
  eff_event_time := COALESCE(NEW.event_time, CASE WHEN TG_OP = 'UPDATE' THEN OLD.event_time ELSE NULL END, now());
  eff_deleted_at := COALESCE(NEW.deleted_at, CASE WHEN TG_OP = 'UPDATE' THEN OLD.deleted_at ELSE NULL END);
  eff_created_by_member_id := COALESCE(NEW.created_by_member_id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.created_by_member_id ELSE NULL END);
  eff_created_by_member_name := COALESCE(NEW.created_by_member_name, CASE WHEN TG_OP = 'UPDATE' THEN OLD.created_by_member_name ELSE NULL END);

  symptom_name := NULL;
  IF NEW.symptoms IS NOT NULL AND array_length(NEW.symptoms, 1) >= 1 THEN
    symptom_name := NULLIF(btrim(NEW.symptoms[1]), '');
  ELSIF TG_OP = 'UPDATE' AND OLD.symptoms IS NOT NULL AND array_length(OLD.symptoms, 1) >= 1 THEN
    symptom_name := NULLIF(btrim(OLD.symptoms[1]), '');
  END IF;

  list_id := NULL;
  IF symptom_name IS NOT NULL THEN
    SELECT symptom_list_id INTO list_id
    FROM public.symptom_list
    WHERE name = symptom_name
    LIMIT 1;
  END IF;

  SELECT notes INTO existing_notes
  FROM public.symptom_log
  WHERE symptom_log_id = ev_id;

  existing := COALESCE(public.try_parse_jsonb(existing_notes), '{}'::jsonb);

  legacy := existing || jsonb_strip_nulls(
    jsonb_build_object(
      'severity', eff_severity,
      'what_happened', eff_what_happened,
      'deleted_at', eff_deleted_at,
      'created_by_member_id', eff_created_by_member_id,
      'created_by_member_name', eff_created_by_member_name
    )
  );

  INSERT INTO public.symptom_log (
    symptom_log_id,
    care_space_id,
    symptom_list_id,
    custom_name,
    severity,
    observed_at,
    notes,
    voice_note_url,
    created_by,
    created_at
  ) VALUES (
    ev_id,
    eff_care_team_id,
    list_id,
    CASE WHEN list_id IS NULL THEN symptom_name ELSE NULL END,
    NULLIF(eff_severity::text, '')::smallint,
    eff_event_time,
    legacy::text,
    NULL,
    auth.uid(),
    COALESCE(NEW.created_at, CASE WHEN TG_OP = 'UPDATE' THEN OLD.created_at ELSE NULL END, now())
  )
  ON CONFLICT (symptom_log_id)
  DO UPDATE SET
    care_space_id = EXCLUDED.care_space_id,
    symptom_list_id = EXCLUDED.symptom_list_id,
    custom_name = EXCLUDED.custom_name,
    severity = EXCLUDED.severity,
    observed_at = EXCLUDED.observed_at,
    notes = EXCLUDED.notes;

  NEW.id := ev_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_symptom_events_view_write ON public.symptom_events;
CREATE TRIGGER trg_symptom_events_view_write
INSTEAD OF INSERT OR UPDATE OR DELETE ON public.symptom_events
FOR EACH ROW
EXECUTE FUNCTION public.symptom_events_view_write();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.symptom_events TO authenticated;
GRANT SELECT ON public.symptom_events TO anon;

-- ------------------------------------------------------------
-- skin_wound_events -> public.skin_wound_log (+ lookup lists)
-- ------------------------------------------------------------

SELECT public.assert_not_table('skin_wound_events');

CREATE OR REPLACE VIEW public.skin_wound_events AS
SELECT
  w.skin_wound_log_id                                 AS id,
  w.care_space_id                                     AS care_team_id,
  COALESCE(
    (public.try_parse_jsonb(w.notes) ->> 'has_skin_condition')::boolean,
    true
  )                                                   AS has_skin_condition,
  COALESCE(
    (public.try_parse_jsonb(w.notes) ->> 'skin_condition'),
    sw.name
  )                                                   AS skin_condition,
  COALESCE(
    public.jsonb_text_array(public.try_parse_jsonb(w.notes) -> 'treatments'),
    CASE WHEN st.name IS NULL THEN ARRAY[]::text[] ELSE ARRAY[st.name] END
  )                                                   AS treatments,
  COALESCE(
    public.jsonb_text_array(public.try_parse_jsonb(w.notes) -> 'image_urls'),
    CASE WHEN w.content_image_url IS NULL OR btrim(w.content_image_url) = ''
      THEN ARRAY[]::text[] ELSE ARRAY[w.content_image_url] END
  )                                                   AS image_urls,
  (public.try_parse_jsonb(w.notes) ->> 'notes')        AS notes,
  w.observed_at                                       AS event_time,
  NULLIF((public.try_parse_jsonb(w.notes) ->> 'deleted_at'), '')::timestamptz AS deleted_at,
  (public.try_parse_jsonb(w.notes) ->> 'created_by_member_id')   AS created_by_member_id,
  (public.try_parse_jsonb(w.notes) ->> 'created_by_member_name') AS created_by_member_name,
  NULL::timestamptz                                   AS editable_until,
  w.created_at                                        AS created_at
FROM public.skin_wound_log w
LEFT JOIN public.skin_wound_list sw
  ON sw.skin_wound_list_id = w.skin_wound_list_id
LEFT JOIN public.skin_treatment_list st
  ON st.skin_treatment_list_id = w.skin_treatment_list_id;

CREATE OR REPLACE FUNCTION public.skin_wound_events_view_write()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  ev_id uuid;
  wound_name text;
  treatment_name text;
  wound_id uuid;
  treatment_id uuid;
  first_image text;
  existing_notes text;
  existing jsonb;
  legacy jsonb;
  eff_care_team_id uuid;
  eff_has_skin_condition boolean;
  eff_skin_condition text;
  eff_treatments text[];
  eff_image_urls text[];
  eff_notes text;
  eff_event_time timestamptz;
  eff_deleted_at timestamptz;
  eff_created_by_member_id text;
  eff_created_by_member_name text;
BEGIN
  IF TG_OP = 'DELETE' THEN
    DELETE FROM public.skin_wound_log
    WHERE skin_wound_log_id = OLD.id::uuid;
    RETURN OLD;
  END IF;

  ev_id := COALESCE(NULLIF(NEW.id::text, '')::uuid, gen_random_uuid());

  eff_care_team_id := COALESCE(
    NULLIF(NEW.care_team_id::text, '')::uuid,
    CASE WHEN TG_OP = 'UPDATE' THEN NULLIF(OLD.care_team_id::text, '')::uuid ELSE NULL END
  );
  eff_has_skin_condition := COALESCE(NEW.has_skin_condition, CASE WHEN TG_OP = 'UPDATE' THEN OLD.has_skin_condition ELSE NULL END, true);
  eff_skin_condition := COALESCE(NEW.skin_condition, CASE WHEN TG_OP = 'UPDATE' THEN OLD.skin_condition ELSE NULL END);
  eff_treatments := COALESCE(NEW.treatments, CASE WHEN TG_OP = 'UPDATE' THEN OLD.treatments ELSE NULL END);
  eff_image_urls := COALESCE(NEW.image_urls, CASE WHEN TG_OP = 'UPDATE' THEN OLD.image_urls ELSE NULL END);
  eff_notes := COALESCE(NEW.notes, CASE WHEN TG_OP = 'UPDATE' THEN OLD.notes ELSE NULL END);
  eff_event_time := COALESCE(NEW.event_time, CASE WHEN TG_OP = 'UPDATE' THEN OLD.event_time ELSE NULL END, now());
  eff_deleted_at := COALESCE(NEW.deleted_at, CASE WHEN TG_OP = 'UPDATE' THEN OLD.deleted_at ELSE NULL END);
  eff_created_by_member_id := COALESCE(NEW.created_by_member_id, CASE WHEN TG_OP = 'UPDATE' THEN OLD.created_by_member_id ELSE NULL END);
  eff_created_by_member_name := COALESCE(NEW.created_by_member_name, CASE WHEN TG_OP = 'UPDATE' THEN OLD.created_by_member_name ELSE NULL END);

  wound_name := NULLIF(btrim(eff_skin_condition), '');
  treatment_name := NULL;
  IF eff_treatments IS NOT NULL AND array_length(eff_treatments, 1) >= 1 THEN
    treatment_name := NULLIF(btrim(eff_treatments[1]), '');
  END IF;

  wound_id := NULL;
  IF wound_name IS NOT NULL THEN
    SELECT skin_wound_list_id INTO wound_id
    FROM public.skin_wound_list
    WHERE name = wound_name
    LIMIT 1;
  END IF;

  treatment_id := NULL;
  IF treatment_name IS NOT NULL THEN
    SELECT skin_treatment_list_id INTO treatment_id
    FROM public.skin_treatment_list
    WHERE name = treatment_name
    LIMIT 1;
  END IF;

  first_image := NULL;
  IF eff_image_urls IS NOT NULL AND array_length(eff_image_urls, 1) >= 1 THEN
    first_image := NULLIF(btrim(eff_image_urls[1]), '');
  END IF;

  SELECT notes INTO existing_notes
  FROM public.skin_wound_log
  WHERE skin_wound_log_id = ev_id;

  existing := COALESCE(public.try_parse_jsonb(existing_notes), '{}'::jsonb);

  legacy := existing || jsonb_strip_nulls(
    jsonb_build_object(
      'has_skin_condition', eff_has_skin_condition,
      'skin_condition', eff_skin_condition,
      'treatments', public.text_array_to_jsonb(eff_treatments),
      'image_urls', public.text_array_to_jsonb(eff_image_urls),
      'notes', eff_notes,
      'deleted_at', eff_deleted_at,
      'created_by_member_id', eff_created_by_member_id,
      'created_by_member_name', eff_created_by_member_name
    )
  );

  INSERT INTO public.skin_wound_log (
    skin_wound_log_id,
    care_space_id,
    skin_wound_list_id,
    skin_treatment_list_id,
    content_image_url,
    observed_at,
    notes,
    voice_note_url,
    created_by,
    created_at
  ) VALUES (
    ev_id,
    eff_care_team_id,
    wound_id,
    treatment_id,
    first_image,
    eff_event_time,
    legacy::text,
    NULL,
    auth.uid(),
    COALESCE(NEW.created_at, CASE WHEN TG_OP = 'UPDATE' THEN OLD.created_at ELSE NULL END, now())
  )
  ON CONFLICT (skin_wound_log_id)
  DO UPDATE SET
    care_space_id = EXCLUDED.care_space_id,
    skin_wound_list_id = EXCLUDED.skin_wound_list_id,
    skin_treatment_list_id = EXCLUDED.skin_treatment_list_id,
    content_image_url = EXCLUDED.content_image_url,
    observed_at = EXCLUDED.observed_at,
    notes = EXCLUDED.notes;

  NEW.id := ev_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_skin_wound_events_view_write ON public.skin_wound_events;
CREATE TRIGGER trg_skin_wound_events_view_write
INSTEAD OF INSERT OR UPDATE OR DELETE ON public.skin_wound_events
FOR EACH ROW
EXECUTE FUNCTION public.skin_wound_events_view_write();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.skin_wound_events TO authenticated;
GRANT SELECT ON public.skin_wound_events TO anon;

-- ------------------------------------------------------------
-- care_plans -> public.care_plan (versioned)
-- ------------------------------------------------------------

SELECT public.assert_not_table('care_plans');

CREATE OR REPLACE VIEW public.care_plans AS
SELECT
  -- Legacy expects a single row per care_team_id.
  p.care_space_id AS care_team_id,
  (public.try_parse_jsonb(p.goals) ->> 'medications_summary')     AS medications_summary,
  (public.try_parse_jsonb(p.goals) ->> 'positioning_turning')     AS positioning_turning,
  (public.try_parse_jsonb(p.goals) ->> 'transfers')               AS transfers,
  (public.try_parse_jsonb(p.goals) ->> 'mobility')                AS mobility,
  (public.try_parse_jsonb(p.goals) ->> 'personal_care')           AS personal_care,
  (public.try_parse_jsonb(p.goals) ->> 'other_instructions')      AS other_instructions,
  (public.try_parse_jsonb(p.goals) ->> 'hospice_instructions')    AS hospice_instructions,
  p.updated_at                                                     AS updated_at,
  (public.try_parse_jsonb(p.goals) ->> 'updated_by_member_id')    AS updated_by_member_id
FROM public.care_plan p
WHERE p.is_current = true;

CREATE OR REPLACE FUNCTION public.care_plans_view_write()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  care_space uuid;
  payload jsonb;
  next_version smallint;
BEGIN
  -- We treat INSERT/UPDATE the same: create a new current version.
  IF TG_OP = 'DELETE' THEN
    UPDATE public.care_plan
      SET is_current = false,
          updated_at = now()
    WHERE care_space_id = OLD.care_team_id::uuid
      AND is_current = true;
    RETURN OLD;
  END IF;

  care_space := NULLIF(NEW.care_team_id::text, '')::uuid;

  payload := jsonb_build_object(
    'medications_summary', NEW.medications_summary,
    'positioning_turning', NEW.positioning_turning,
    'transfers', NEW.transfers,
    'mobility', NEW.mobility,
    'personal_care', NEW.personal_care,
    'other_instructions', NEW.other_instructions,
    'hospice_instructions', NEW.hospice_instructions,
    'updated_by_member_id', NEW.updated_by_member_id
  );

  SELECT COALESCE(max(version), 0)::smallint + 1
    INTO next_version
  FROM public.care_plan
  WHERE care_space_id = care_space;

  -- Close out previous current plan.
  UPDATE public.care_plan
    SET is_current = false,
        updated_at = now()
  WHERE care_space_id = care_space
    AND is_current = true;

  INSERT INTO public.care_plan (
    care_plan_id,
    care_space_id,
    version,
    is_current,
    effective_date,
    goals,
    special_instructions,
    created_by,
    created_at,
    updated_at
  ) VALUES (
    gen_random_uuid(),
    care_space,
    next_version,
    true,
    now()::date,
    payload::text,
    NULL,
    auth.uid(),
    now(),
    now()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_care_plans_view_write ON public.care_plans;
CREATE TRIGGER trg_care_plans_view_write
INSTEAD OF INSERT OR UPDATE OR DELETE ON public.care_plans
FOR EACH ROW
EXECUTE FUNCTION public.care_plans_view_write();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.care_plans TO authenticated;
GRANT SELECT ON public.care_plans TO anon;

-- ------------------------------------------------------------
-- observations -> public.quick_notes
-- ------------------------------------------------------------

SELECT public.assert_not_table('observations');

CREATE OR REPLACE VIEW public.observations AS
SELECT
  q.quick_notes_id      AS id,
  q.care_space_id       AS care_team_id,
  q.content_text        AS content,
  q.visibility          AS category,
  q.created_at          AS created_at,
  q.deleted_at          AS deleted_at,
  q.user_profile_id     AS created_by_member_id,
  NULL::text            AS created_by_member_name
FROM public.quick_notes q;

CREATE OR REPLACE FUNCTION public.observations_view_write()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  note_id uuid;
  eff_care_team_id uuid;
  eff_content text;
  eff_category text;
  eff_created_at timestamptz;
  eff_deleted_at timestamptz;
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE public.quick_notes
      SET deleted_at = COALESCE(deleted_at, now()),
          updated_at = now()
    WHERE quick_notes_id = OLD.id::uuid;
    RETURN OLD;
  END IF;

  note_id := COALESCE(NULLIF(NEW.id::text, '')::uuid, gen_random_uuid());

  eff_care_team_id := COALESCE(
    NULLIF(NEW.care_team_id::text, '')::uuid,
    CASE WHEN TG_OP = 'UPDATE' THEN NULLIF(OLD.care_team_id::text, '')::uuid ELSE NULL END
  );
  eff_content := COALESCE(NEW.content, CASE WHEN TG_OP = 'UPDATE' THEN OLD.content ELSE NULL END, '');
  eff_category := COALESCE(NEW.category, CASE WHEN TG_OP = 'UPDATE' THEN OLD.category ELSE NULL END);
  eff_created_at := COALESCE(NEW.created_at, CASE WHEN TG_OP = 'UPDATE' THEN OLD.created_at ELSE NULL END, now());
  eff_deleted_at := COALESCE(NEW.deleted_at, CASE WHEN TG_OP = 'UPDATE' THEN OLD.deleted_at ELSE NULL END);

  INSERT INTO public.quick_notes (
    quick_notes_id,
    care_space_id,
    user_profile_id,
    content_text,
    visibility,
    created_at,
    updated_at,
    deleted_at
  ) VALUES (
    note_id,
    eff_care_team_id,
    auth.uid(),
    eff_content,
    NULLIF(eff_category, ''),
    eff_created_at,
    now(),
    eff_deleted_at
  )
  ON CONFLICT (quick_notes_id)
  DO UPDATE SET
    care_space_id = EXCLUDED.care_space_id,
    content_text = EXCLUDED.content_text,
    visibility = EXCLUDED.visibility,
    updated_at = now(),
    deleted_at = EXCLUDED.deleted_at;

  NEW.id := note_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_observations_view_write ON public.observations;
CREATE TRIGGER trg_observations_view_write
INSTEAD OF INSERT OR UPDATE OR DELETE ON public.observations
FOR EACH ROW
EXECUTE FUNCTION public.observations_view_write();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.observations TO authenticated;
GRANT SELECT ON public.observations TO anon;

-- ------------------------------------------------------------
-- moments -> public.moment
-- ------------------------------------------------------------

SELECT public.assert_not_table('moments');

CREATE OR REPLACE VIEW public.moments AS
SELECT
  m.moment_id           AS id,
  m.care_space_id       AS care_team_id,
  NULL::text            AS category,
  m.content_text        AS content,
  m.visibility          AS visibility,
  m.content_image_url   AS photo_url,
  m.created_at          AS created_at,
  m.user_profile_id     AS created_by_member_id,
  NULL::text            AS created_by_member_name
FROM public.moment m;

CREATE OR REPLACE FUNCTION public.moments_view_write()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  moment_id uuid;
  eff_care_team_id uuid;
  eff_content text;
  eff_photo_url text;
  eff_visibility text;
  eff_created_at timestamptz;
BEGIN
  IF TG_OP = 'DELETE' THEN
    UPDATE public.moment
      SET deleted_at = COALESCE(deleted_at, now()),
          updated_at = now()
    WHERE moment_id = OLD.id::uuid;
    RETURN OLD;
  END IF;

  moment_id := COALESCE(NULLIF(NEW.id::text, '')::uuid, gen_random_uuid());

  eff_care_team_id := COALESCE(
    NULLIF(NEW.care_team_id::text, '')::uuid,
    CASE WHEN TG_OP = 'UPDATE' THEN NULLIF(OLD.care_team_id::text, '')::uuid ELSE NULL END
  );
  eff_content := COALESCE(NEW.content, CASE WHEN TG_OP = 'UPDATE' THEN OLD.content ELSE NULL END, '');
  eff_photo_url := COALESCE(NEW.photo_url, CASE WHEN TG_OP = 'UPDATE' THEN OLD.photo_url ELSE NULL END);
  eff_visibility := COALESCE(NEW.visibility, CASE WHEN TG_OP = 'UPDATE' THEN OLD.visibility ELSE NULL END);
  eff_created_at := COALESCE(NEW.created_at, CASE WHEN TG_OP = 'UPDATE' THEN OLD.created_at ELSE NULL END, now());

  INSERT INTO public.moment (
    moment_id,
    care_space_id,
    user_profile_id,
    content_text,
    content_image_url,
    visibility,
    created_at,
    updated_at,
    deleted_at
  ) VALUES (
    moment_id,
    eff_care_team_id,
    auth.uid(),
    eff_content,
    NULLIF(eff_photo_url, ''),
    NULLIF(eff_visibility, ''),
    eff_created_at,
    now(),
    NULL
  )
  ON CONFLICT (moment_id)
  DO UPDATE SET
    care_space_id = EXCLUDED.care_space_id,
    content_text = EXCLUDED.content_text,
    content_image_url = EXCLUDED.content_image_url,
    visibility = EXCLUDED.visibility,
    updated_at = now(),
    deleted_at = EXCLUDED.deleted_at;

  NEW.id := moment_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_moments_view_write ON public.moments;
CREATE TRIGGER trg_moments_view_write
INSTEAD OF INSERT OR UPDATE OR DELETE ON public.moments
FOR EACH ROW
EXECUTE FUNCTION public.moments_view_write();

GRANT SELECT, INSERT, UPDATE, DELETE ON public.moments TO authenticated;
GRANT SELECT ON public.moments TO anon;
