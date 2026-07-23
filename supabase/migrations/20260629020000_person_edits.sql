-- Rootsphere — edit audit log for person records.
--
-- Every time an existing person is edited, the client records why. Member-based
-- RLS reuses `is_tree_member()` so collaborators on a tree can read the history
-- and add their own entries. Run AFTER 20260617000000_tree_members.sql.

-- ── Table ──────────────────────────────────────────────────────────────────────

create table if not exists public.person_edits (
  id             text primary key,                     -- client-generated id
  tree_id        text not null
                    references public.trees (id) on delete cascade,
  person_id      text not null
                    references public.persons (id) on delete cascade,
  editor_id      uuid default auth.uid()
                    references auth.users (id) on delete set null,
  editor_name    text,
  reason         text not null,
  changed_fields text[] not null default '{}',
  created_at     timestamptz not null default now()
);

create index if not exists person_edits_person_id_idx
  on public.person_edits (person_id);
create index if not exists person_edits_tree_id_idx
  on public.person_edits (tree_id);

-- ── Row-level security (member-based) ─────────────────────────────────────────

alter table public.person_edits enable row level security;

drop policy if exists "person_edits_member_all" on public.person_edits;
create policy "person_edits_member_all" on public.person_edits
  for all
  to authenticated
  using (public.is_tree_member(tree_id))
  with check (public.is_tree_member(tree_id));
