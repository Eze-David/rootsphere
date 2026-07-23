-- Rootsphere — Phase 5 (collaboration): tree membership.
--
-- Adds a `tree_members` join table so multiple users can share a family tree.
-- Knowing a tree's id acts as the invite: any signed-in user can join via the
-- `join_tree` RPC. Owner-only RLS on `trees`/`persons` is widened to
-- member-based access. Run this in the Supabase SQL editor (or via the CLI)
-- AFTER 20260607000000_tree.sql.

-- ── Membership table ─────────────────────────────────────────────────────────

create table if not exists public.tree_members (
  tree_id     text not null
                 references public.trees (id) on delete cascade,
  user_id     uuid not null default auth.uid()
                 references auth.users (id) on delete cascade,
  role        text not null default 'viewer',   -- owner | editor | viewer
  created_at  timestamptz not null default now(),
  primary key (tree_id, user_id)
);

create index if not exists tree_members_user_id_idx
  on public.tree_members (user_id);

-- ── Membership check (SECURITY DEFINER avoids RLS recursion) ──────────────────
-- Used inside the trees/persons policies. Defined as SECURITY DEFINER so it can
-- read `tree_members` without re-triggering that table's own RLS policies.

create or replace function public.is_tree_member(p_tree_id text)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.tree_members m
    where m.tree_id = p_tree_id
      and m.user_id = auth.uid()
  );
$$;

-- ── Backfill: make every existing tree owner a member ─────────────────────────

insert into public.tree_members (tree_id, user_id, role)
select t.id, t.owner_id, 'owner'
from public.trees t
on conflict (tree_id, user_id) do nothing;

-- ── Auto-enrol the owner whenever a tree is created ───────────────────────────

create or replace function public.add_owner_as_member()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.tree_members (tree_id, user_id, role)
  values (new.id, new.owner_id, 'owner')
  on conflict (tree_id, user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists trees_add_owner_member on public.trees;
create trigger trees_add_owner_member
  after insert on public.trees
  for each row execute function public.add_owner_as_member();

-- ── Row-level security ────────────────────────────────────────────────────────

alter table public.tree_members enable row level security;

drop policy if exists "tree_members_select" on public.tree_members;
create policy "tree_members_select" on public.tree_members
  for select
  to authenticated
  using (user_id = auth.uid() or public.is_tree_member(tree_id));

-- Self-join: a user may add only their own membership row.
drop policy if exists "tree_members_insert_self" on public.tree_members;
create policy "tree_members_insert_self" on public.tree_members
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- Leave (self) or owner removing a member.
drop policy if exists "tree_members_delete" on public.tree_members;
create policy "tree_members_delete" on public.tree_members
  for delete
  to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.trees t
      where t.id = tree_id and t.owner_id = auth.uid()
    )
  );

-- Widen trees access: members can read; only the owner can write.
drop policy if exists "trees_owner_all" on public.trees;

drop policy if exists "trees_member_select" on public.trees;
create policy "trees_member_select" on public.trees
  for select
  to authenticated
  using (owner_id = auth.uid() or public.is_tree_member(id));

drop policy if exists "trees_owner_insert" on public.trees;
create policy "trees_owner_insert" on public.trees
  for insert
  to authenticated
  with check (owner_id = auth.uid());

drop policy if exists "trees_owner_update" on public.trees;
create policy "trees_owner_update" on public.trees
  for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists "trees_owner_delete" on public.trees;
create policy "trees_owner_delete" on public.trees
  for delete
  to authenticated
  using (owner_id = auth.uid());

-- Widen persons access: any member of the tree can read/write its persons.
drop policy if exists "persons_owner_all" on public.persons;
drop policy if exists "persons_member_all" on public.persons;
create policy "persons_member_all" on public.persons
  for all
  to authenticated
  using (public.is_tree_member(tree_id))
  with check (public.is_tree_member(tree_id));

-- ── RPCs ──────────────────────────────────────────────────────────────────────

-- Join a tree by id. Raises if the tree does not exist; idempotent otherwise.
-- Returns the joined tree row.
create or replace function public.join_tree(p_tree_id text)
returns public.trees
language plpgsql
security definer
set search_path = public
as $$
declare
  t public.trees;
begin
  select * into t from public.trees where id = p_tree_id;
  if not found then
    raise exception 'Tree not found' using errcode = 'no_data_found';
  end if;

  insert into public.tree_members (tree_id, user_id, role)
  values (p_tree_id, auth.uid(), 'viewer')
  on conflict (tree_id, user_id) do nothing;

  return t;
end;
$$;

-- Trees the current user belongs to, with their role and the member count.
create or replace function public.my_trees()
returns table (
  id           text,
  name         text,
  role         text,
  member_count bigint
)
language sql
stable
security definer
set search_path = public
as $$
  select
    t.id,
    t.name,
    m.role,
    (select count(*) from public.tree_members mc where mc.tree_id = t.id)
      as member_count
  from public.tree_members m
  join public.trees t on t.id = m.tree_id
  where m.user_id = auth.uid()
  order by t.created_at;
$$;
