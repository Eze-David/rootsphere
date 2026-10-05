-- Researcher Code of Conduct and Confidentiality Undertaking. Every
-- researcher or volunteer (including platform admins) must accept it once,
-- for the current version, before they can claim an opportunity — enforced
-- in check_claim_qualification below, not just in the client. Run AFTER
-- 20260722090000_admin_claim_any_opportunity.sql.

create table if not exists public.researcher_undertakings (
  user_id      uuid not null references auth.users (id) on delete cascade,
  version      text not null,
  signed_name  text not null,
  accepted_at  timestamptz not null default now(),
  primary key (user_id, version)
);

alter table public.researcher_undertakings enable row level security;

drop policy if exists "researcher_undertakings_select" on public.researcher_undertakings;
create policy "researcher_undertakings_select" on public.researcher_undertakings
  for select to authenticated
  using (user_id = auth.uid() or public.is_platform_admin());

-- Accept-only: no update/delete policies, so an acceptance can't be
-- rewritten or withdrawn from the client.
drop policy if exists "researcher_undertakings_insert" on public.researcher_undertakings;
create policy "researcher_undertakings_insert" on public.researcher_undertakings
  for insert to authenticated
  with check (user_id = auth.uid());

create or replace function public.check_claim_qualification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'open' and new.status = 'claimed' and new.claimer_id is not null then
    if not exists (
      select 1 from public.researcher_undertakings ru
      where ru.user_id = new.claimer_id
        and ru.version = '2026-10'
    ) then
      raise exception 'undertaking_required'
        using errcode = 'insufficient_privilege';
    end if;
    if public.is_platform_admin() then
      return new;
    end if;
    if new.for_company then
      raise exception 'company_request_admin_only'
        using errcode = 'insufficient_privilege';
    end if;
    if not exists (
      select 1 from public.role_verifications rv
      where rv.user_id = new.claimer_id
        and rv.role = new.required_role
        and rv.status = 'approved'
    ) then
      raise exception 'not_qualified_for_role: %', new.required_role
        using errcode = 'insufficient_privilege';
    end if;
  end if;
  return new;
end;
$$;
