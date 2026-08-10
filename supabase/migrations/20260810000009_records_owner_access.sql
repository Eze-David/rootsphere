-- Rootsphere — let record ownership alone be enough, independent of tree
-- membership timing.
--
-- 20260715000000_records_ensure_tree.sql's auto-heal trigger (now hardened
-- as SECURITY DEFINER in 20260810000003) correctly creates the uploader's
-- implicit personal tree (`t_<uid>`) and membership before the row is
-- written — verified directly against the live database. But a brand-new
-- account should be able to upload records even before any tree exists at
-- all, not just once the auto-heal trigger has run for the first time — and
-- relying solely on tree membership ties record access to tree machinery
-- that a records-only user may never otherwise touch. Widening the policy
-- so a user can always read/write records they own, in addition to records
-- in any tree they're a member of, removes that dependency entirely and
-- matches how the client already scopes "my records" (Record.ownerId).

-- 1) Restore ensure_tree_for_record to its real (non-debug) working form —
--    proven correct via direct testing, temporarily replaced with debug
--    variants while diagnosing this.
create or replace function public.ensure_tree_for_record()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_inserted boolean := false;
begin
  insert into public.trees (id, owner_id, name)
  values (new.tree_id, auth.uid(), 'My Family Tree')
  on conflict (id) do nothing
  returning true into v_inserted;

  if v_inserted then
    insert into public.tree_members (tree_id, user_id, role)
    values (new.tree_id, auth.uid(), 'owner')
    on conflict (tree_id, user_id) do nothing;
  end if;

  return new;
end;
$$;

-- 2) Widen records access: owner OR tree member (previously tree-member-only).
drop policy if exists "records_member_all" on public.records;
create policy "records_member_all" on public.records
  for all
  to authenticated
  using (owner_id = auth.uid() or public.is_tree_member(tree_id))
  with check (owner_id = auth.uid() or public.is_tree_member(tree_id));
