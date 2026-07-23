-- Rootsphere — let anybody with an account upload a record even before
-- they've built out a tree.
--
-- `records.tree_id` has a foreign key to `trees(id)`, and every signed-in
-- user's implicit personal tree id (`t_<uid>`, see activeTreeIdProvider) only
-- becomes a real row in `trees` once they add their first person
-- (TreeRepositorySupabase._ensureTree). A brand-new user with zero people has
-- no such row yet, so uploading a record — which the app already lets you do
-- with no linked people, see the "Linked people (optional)" picker — would
-- fail on the FK constraint.
--
-- This mirrors _ensureTree's client-side upsert at the DB layer instead, so
-- it's guaranteed regardless of which path creates the record. Runs BEFORE
-- INSERT so by the time records' own RLS (`is_tree_member`) is checked, the
-- tree (and, via trees_add_owner_member, the owner's membership row) already
-- exists — see 20260617000000_tree_members.sql for that trigger chain.

create or replace function public.ensure_tree_for_record()
returns trigger
language plpgsql
as $$
begin
  insert into public.trees (id, owner_id, name)
  values (new.tree_id, auth.uid(), 'My Family Tree')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists records_ensure_tree on public.records;
create trigger records_ensure_tree
  before insert on public.records
  for each row execute function public.ensure_tree_for_record();
