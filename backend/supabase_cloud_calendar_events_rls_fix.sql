-- Fix: "new row violates row-level security policy" for public.calendar_events (Postgres error 42501)
--
-- Run this in Supabase Cloud: Dashboard → SQL Editor.
-- Keeps RLS ENABLED but replaces existing policies with non-recursive, permissive
-- policies for anon/authenticated (matches a client app using the anon key).

-- Inspect existing policies
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'calendar_events'
order by policyname;

-- 1) Drop all existing policies on public.calendar_events
do $$
declare p record;
begin
  for p in (
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'calendar_events'
  ) loop
    execute format('drop policy if exists %I on public.calendar_events', p.policyname);
  end loop;
end $$;

-- 2) Ensure the API roles can access the table (RLS still applies)
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on table public.calendar_events to anon, authenticated;

-- 3) Enable RLS and create permissive policies (non-recursive)
alter table public.calendar_events enable row level security;

create policy calendar_events_select_all
on public.calendar_events
for select
to anon, authenticated
using (true);

create policy calendar_events_insert_all
on public.calendar_events
for insert
to anon, authenticated
with check (true);

create policy calendar_events_update_all
on public.calendar_events
for update
to anon, authenticated
using (true)
with check (true);

create policy calendar_events_delete_all
on public.calendar_events
for delete
to anon, authenticated
using (true);

-- Notes:
-- - This is intentionally permissive because the Flutter app is not using Supabase Auth.
-- - If you later add Supabase Auth, replace these with auth.uid()-based policies.
