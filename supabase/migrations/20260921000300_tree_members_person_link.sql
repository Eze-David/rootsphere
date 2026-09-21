-- Home dashboard "Family at a glance": lets a signed-in user mark which
-- Person node in a (possibly shared) tree represents them. Stored per
-- (tree, user) on tree_members rather than as a flag on persons, since a
-- shared tree can have multiple collaborators each needing their own
-- pointer. Run AFTER 20260617000000_tree_members.sql.

alter table public.tree_members
  add column if not exists person_id text
    references public.persons (id) on delete set null;

-- No update policy exists on tree_members today (only select/insert-self/
-- delete) — required for a user to set/clear their own person_id.
drop policy if exists "tree_members_update_self" on public.tree_members;
create policy "tree_members_update_self" on public.tree_members
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
