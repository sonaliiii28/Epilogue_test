-- Create calendar table (DOCX schema compatible)
--
-- Run this in Supabase SQL editor AFTER you have applied the DOCX schema.
-- Assumes these already exist:
--   - public.care_space
--   - public.user_profile
--   - public.medication
--   - public.set_updated_at() trigger function
--   - public.is_active_member_of_care_space(uuid) SECURITY DEFINER helper

BEGIN;

-- Ensure UUID generation is available.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.calendar_events (
  calendar_event_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  care_space_id uuid NOT NULL REFERENCES public.care_space (care_space_id) ON DELETE CASCADE,

  -- Finalized event types (use stable codes; map to display strings in the app)
  --   medication            -> "Medications"
  --   hospice_visit         -> "Hospice visit"
  --   caregiver_visit       -> "Caregiver visit"
  --   family_friend_visit   -> "Family or friend visit"
  --   other_visit           -> "Other visit"
  --   reminder              -> "Reminders"
  event_type text NOT NULL,

  -- Used for the 3 top-of-calendar filters.
  -- Keep redundant (instead of computed) so queries stay simple.
  category text NOT NULL,

  -- When the event happens.
  scheduled_at timestamptz NOT NULL,
  duration_minutes integer,

  -- What shows in the day list.
  title text,
  detail text,
  notes text,

  -- Medication auto-population support.
  source text NOT NULL DEFAULT 'manual',
  source_medication_id uuid REFERENCES public.medication (medication_id) ON DELETE SET NULL,

  -- Recurrence support (optional).
  -- If you store a single row for a recurring series, set recurrence_rule.
  -- If you store one row per occurrence, leave recurrence_rule null and use series_id.
  series_id uuid,
  recurrence_rule text,
  recurrence_until date,

  -- Audit + soft delete.
  created_by uuid REFERENCES public.user_profile (user_profile_id) DEFAULT auth.uid(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,

  CONSTRAINT calendar_events_event_type_check CHECK (
    event_type IN (
      'medication',
      'hospice_visit',
      'caregiver_visit',
      'family_friend_visit',
      'other_visit',
      'reminder'
    )
  ),
  CONSTRAINT calendar_events_category_check CHECK (category IN ('medications', 'visits', 'other')),
  CONSTRAINT calendar_events_medication_link_check CHECK (
    (event_type = 'medication') = (category = 'medications')
  )
);

-- Keep updated_at current.
DROP TRIGGER IF EXISTS trg_calendar_events_set_updated_at ON public.calendar_events;
CREATE TRIGGER trg_calendar_events_set_updated_at
BEFORE UPDATE ON public.calendar_events
FOR EACH ROW
EXECUTE FUNCTION public.set_updated_at();

-- Helpful indexes for month + day view.
CREATE INDEX IF NOT EXISTS calendar_event_care_space_scheduled_at_idx
ON public.calendar_events (care_space_id, scheduled_at)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS calendar_event_care_space_category_idx
ON public.calendar_events (care_space_id, category)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS calendar_event_care_space_event_type_idx
ON public.calendar_events (care_space_id, event_type)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS calendar_event_care_space_series_idx
ON public.calendar_events (care_space_id, series_id)
WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS calendar_event_source_medication_idx
ON public.calendar_events (source_medication_id)
WHERE deleted_at IS NULL;

-- RLS
ALTER TABLE public.calendar_events ENABLE ROW LEVEL SECURITY;

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.calendar_events TO authenticated;

DROP POLICY IF EXISTS "calendar_events_select_for_members" ON public.calendar_events;
CREATE POLICY "calendar_events_select_for_members"
ON public.calendar_events
FOR SELECT
TO authenticated
USING (
  public.is_active_member_of_care_space(care_space_id)
  AND deleted_at IS NULL
);

DROP POLICY IF EXISTS "calendar_events_insert_for_members" ON public.calendar_events;
CREATE POLICY "calendar_events_insert_for_members"
ON public.calendar_events
FOR INSERT
TO authenticated
WITH CHECK (
  public.is_active_member_of_care_space(care_space_id)
  AND (created_by = auth.uid() OR created_by IS NULL)
);

DROP POLICY IF EXISTS "calendar_events_update_for_members" ON public.calendar_events;
CREATE POLICY "calendar_events_update_for_members"
ON public.calendar_events
FOR UPDATE
TO authenticated
USING (
  public.is_active_member_of_care_space(care_space_id)
)
WITH CHECK (
  public.is_active_member_of_care_space(care_space_id)
);

DROP POLICY IF EXISTS "calendar_events_delete_for_members" ON public.calendar_events;
CREATE POLICY "calendar_events_delete_for_members"
ON public.calendar_events
FOR DELETE
TO authenticated
USING (
  public.is_active_member_of_care_space(care_space_id)
);

COMMIT;
