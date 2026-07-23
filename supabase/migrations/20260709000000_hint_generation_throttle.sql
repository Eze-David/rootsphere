-- Rootsphere — Phase 4 follow-up: throttle AI hint generation.
--
-- The `hints` Edge Function calls the Claude API, which is billed per call.
-- This table lets the function remember when a tree last asked for AI hints
-- so repeated taps within the cooldown window are answered for free (no
-- Claude call) instead of re-charging the account.
--
-- Only the Edge Function touches this table, using the service-role key
-- (which bypasses RLS) — clients have no direct policy and therefore no
-- access at all. Run AFTER 20260630000000_hints.sql.

create table if not exists public.hint_generation_log (
  tree_id            text primary key
                        references public.trees (id) on delete cascade,
  last_requested_at  timestamptz not null default now()
);

alter table public.hint_generation_log enable row level security;
-- Intentionally no policies: locked to the service role.
