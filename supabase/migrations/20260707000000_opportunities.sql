-- Rootsphere — Phase 5: Collaboration / Opportunities board.
--
-- Stores record-gathering requests that tree members can claim, work on, and
-- verify. Run AFTER 20260617000000_tree_members.sql.

-- ── Table ─────────────────────────────────────────────────────────────────────

create table if not exists public.opportunities (
  id             text primary key,                        -- client-generated id
  tree_id        text not null references public.trees (id) on delete cascade,
  title          text not null,
  description    text not null,
  location       text,                                   -- e.g. "Lagos, Nigeria"
  latitude       double precision,
  longitude      double precision,
  required_role  text not null default 'finder',          -- finder | indexer
  requester_id   uuid not null references auth.users (id) on delete cascade,
  requester_name text not null,
  claimer_id     uuid references auth.users (id) on delete set null,
  claimer_name   text,
  status         text not null default 'open',            -- open | claimed | verified
  result_notes   text,
  result_url     text,
  finder_submission  jsonb,
  indexer_submission jsonb,
  created_at     timestamptz not null default now(),
  claimed_at     timestamptz,
  verified_at    timestamptz
);

-- Add columns if the table already existed without them.
alter table public.opportunities
  add column if not exists required_role text not null default 'finder',
  add column if not exists finder_submission jsonb,
  add column if not exists indexer_submission jsonb;

-- Indexes for the board filters.
create index if not exists opportunities_tree_id_idx on public.opportunities (tree_id);
create index if not exists opportunities_status_idx on public.opportunities (status);
create index if not exists opportunities_requester_id_idx on public.opportunities (requester_id);
create index if not exists opportunities_claimer_id_idx on public.opportunities (claimer_id);

-- ── Row-level security ─────────────────────────────────────────────────────────

alter table public.opportunities enable row level security;

-- All authenticated users can view opportunities on the community board.
drop policy if exists "opportunities_select" on public.opportunities;
create policy "opportunities_select" on public.opportunities
  for select
  to authenticated
  using (true);

-- Any authenticated user can create an opportunity.
drop policy if exists "opportunities_insert" on public.opportunities;
create policy "opportunities_insert" on public.opportunities
  for insert
  to authenticated
  with check (true);

-- Update rules:
--  * Anyone can claim an open opportunity.
--  * The claimer can submit results or unclaim.
--  * The requester can verify a claimed opportunity.
--  * The requester can edit their own opportunity metadata at any time.
drop policy if exists "opportunities_update" on public.opportunities;
create policy "opportunities_update" on public.opportunities
  for update
  to authenticated
  using (
    requester_id = auth.uid()
    or claimer_id = auth.uid()
    or status = 'open'
  )
  with check (true);

-- Only the requester can delete their own opportunity.
drop policy if exists "opportunities_delete" on public.opportunities;
create policy "opportunities_delete" on public.opportunities
  for delete
  to authenticated
  using (requester_id = auth.uid());
