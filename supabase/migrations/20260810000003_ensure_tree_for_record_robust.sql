-- Rootsphere — harden ensure_tree_for_record().
--
-- Reported bug: a brand-new account got "row-level security policy" on its
-- very first record upload despite 20260715000000_records_ensure_tree.sql
-- existing specifically to prevent that. The original function ran as
-- SECURITY INVOKER, so its own `insert into trees` was itself subject to
-- the *caller's* grants/RLS rather than running with reliable, unambiguous
-- privilege — and it depended on a *second*, separate AFTER trigger
-- (trees_add_owner_member) to grant membership, adding a cross-trigger
-- timing dependency. This rewrite is SECURITY DEFINER (bypasses that
-- ambiguity entirely, same pattern as add_owner_as_member/is_tree_member)
-- and grants membership to the CURRENT caller directly, inline, in the same
-- statement — but only when this call is the one that actually just created
-- the tree (`returning` into v_inserted), never for a tree that already
-- existed. That guard matters: without it, any authenticated caller could
-- upload a record against a *pre-existing* tree_id belonging to someone
-- else and silently grant themselves membership in it — a privilege
-- escalation this must not introduce.

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
