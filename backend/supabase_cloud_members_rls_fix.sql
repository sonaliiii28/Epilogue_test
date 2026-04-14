-- Fix: "infinite recursion detected in policy for relation members" (Postgres error 42P17)
--
-- Run this in Supabase Cloud: Dashboard → SQL Editor.
--
-- Why this happens:
-- Some RLS policies on public.members query public.members inside the policy,
-- which causes Postgres to recurse evaluating the policy.
--
-- This script provides two options:
--   Option A (recommended for this app right now): DISABLE RLS on public.members
--   Option B: KEEP RLS enabled but replace with permissive (dev) policies (still non-recursive)

-- See existing policies on members
select schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'members'
order by policyname;

-- ============
-- Option A: Disable RLS on members (simple + avoids recursion)
-- ============
-- NOTE: This makes members accessible based on table grants (anon/authenticated).
-- Use for development or when you are NOT using Supabase Auth in the client.
alter table public.members disable row level security;

-- ============
-- Option B: KEEP RLS enabled but replace with permissive dev policies
-- (use this if you don't want to disable RLS)
-- ============
-- 1) Drop all existing policies on public.members
-- do $$
-- declare p record;
-- begin
--   for p in (
--     select policyname from pg_policies
--     where schemaname = 'public' and tablename = 'members'
--   ) loop
--     execute format('drop policy if exists %I on public.members', p.policyname);
--   end loop;
-- end $$;
--
-- 2) Ensure the API roles can access the table (RLS still applies)
-- grant usage on schema public to anon, authenticated;
-- grant select, insert, update, delete on table public.members to anon, authenticated;
--
-- 3) Enable RLS and create NON-RECURSIVE policies
-- alter table public.members enable row level security;
--
-- create policy members_select_all
-- on public.members
-- for select
-- to anon, authenticated
-- using (true);
--
-- create policy members_insert_all
-- on public.members
-- for insert
-- to anon, authenticated
-- with check (true);
--
-- create policy members_update_all
-- on public.members
-- for update
-- to anon, authenticated
-- using (true)
-- with check (true);
--
-- create policy members_delete_all
-- on public.members
-- for delete
-- to anon, authenticated
-- using (true);

-- If you later add Supabase Auth, replace Option A/B with proper auth-based policies.
