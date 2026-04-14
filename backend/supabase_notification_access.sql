-- Notification table access + RLS policies
--
-- Run this in Supabase SQL editor (Cloud or Local).
--
-- Why this is needed:
-- - If `public.notification` lacks GRANTs, authenticated users can't read/write it.
-- - If RLS is enabled (or gets enabled later), inserts/selects may be blocked.
--
-- This setup allows:
-- - Recipients to SELECT/UPDATE their own notifications
-- - Any active care-space member to INSERT notifications for other members
--   (validated via `public.is_active_member_of_care_space()` using `data.care_space_id`)

BEGIN;

-- Ensure privileges exist
GRANT SELECT, INSERT, UPDATE ON TABLE public.notification TO authenticated;

-- Enable RLS (safe even if already enabled)
ALTER TABLE public.notification ENABLE ROW LEVEL SECURITY;

-- Recipients can read their own inbox
DROP POLICY IF EXISTS notification_select_own ON public.notification;
CREATE POLICY notification_select_own
ON public.notification
FOR SELECT
TO authenticated
USING (auth.uid() = user_profile_id);

-- Recipients can mark their own notifications as read
DROP POLICY IF EXISTS notification_update_own ON public.notification;
CREATE POLICY notification_update_own
ON public.notification
FOR UPDATE
TO authenticated
USING (auth.uid() = user_profile_id)
WITH CHECK (auth.uid() = user_profile_id);

-- Active care-space members can create notifications for other users
-- NOTE: notification rows must include `data.care_space_id`.
DROP POLICY IF EXISTS notification_insert_for_members ON public.notification;
CREATE POLICY notification_insert_for_members
ON public.notification
FOR INSERT
TO authenticated
WITH CHECK (
  user_profile_id <> auth.uid()
  AND public.is_active_member_of_care_space((data->>'care_space_id')::uuid)
);

COMMIT;
