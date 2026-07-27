-- Admins and approved Finders/Indexers review records across the whole
-- platform, not just trees they belong to — so they need read access beyond
-- what `records_member_all` (tree-membership-only, 20260618000000_records.sql)
-- grants. Run AFTER 20260722020000_role_verifications.sql.

create or replace function public.is_approved_collaborator()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.is_platform_admin() or exists (
    select 1 from public.role_verifications rv
    where rv.user_id = auth.uid()
      and rv.status = 'approved'
  );
$$;

-- Additive (permissive) policy — Postgres OR's this together with
-- `records_member_all` for select, so ordinary tree members are unaffected
-- and only gain visibility if they're also an admin/approved reviewer.
drop policy if exists "records_reviewer_select" on public.records;
create policy "records_reviewer_select" on public.records
  for select
  to authenticated
  using (public.is_approved_collaborator());
