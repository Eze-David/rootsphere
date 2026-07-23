-- Lets a requester send an opportunity directly to "the company" (Rootsphere
-- staff) instead of posting it to the public community board — for requests
-- they'd rather trust to the platform's own team. Run AFTER
-- 20260722020000_role_verifications.sql (needs is_platform_admin()).

alter table public.opportunities
  add column if not exists for_company boolean not null default false;

-- ── Visibility ────────────────────────────────────────────────────────────────
-- Company-routed requests are hidden from the public board — only the
-- requester (who sent it), whoever claimed it, and platform admins can see
-- the row. `claimer_id` matters here specifically: Postgres requires a row to
-- pass the SELECT policy for it to come back from an UPDATE ... RETURNING
-- (which is what claiming does), so without it the claiming admin's own
-- claim would appear to fail with "Cannot coerce the result to a single JSON
-- object" even though the update itself succeeded.

drop policy if exists "opportunities_select" on public.opportunities;
create policy "opportunities_select" on public.opportunities
  for select
  to authenticated
  using (
    for_company = false
    or requester_id = auth.uid()
    or claimer_id = auth.uid()
    or public.is_platform_admin()
  );

-- ── Claim gating ──────────────────────────────────────────────────────────────
-- Company requests skip the Finder/Indexer qualification check (the company's
-- own staff take these on directly) but can only ever be claimed by an admin.

create or replace function public.check_claim_qualification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'open' and new.status = 'claimed' and new.claimer_id is not null then
    if new.for_company then
      if not public.is_platform_admin() then
        raise exception 'company_request_admin_only'
          using errcode = 'insufficient_privilege';
      end if;
    elsif not exists (
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

-- ── Notify the company ───────────────────────────────────────────────────────

create or replace function public.notify_company_opportunity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.for_company then
    insert into public.notifications (user_id, type, title, body, tree_id, opportunity_id)
    select
      a.user_id,
      'opportunity_company_request',
      'New request for the company',
      coalesce(new.requester_name, 'Someone') || ' sent "' || new.title || '" directly to the company.',
      new.tree_id,
      new.id
    from public.platform_admins a;
  end if;
  return new;
end;
$$;

drop trigger if exists opportunities_notify_company_request on public.opportunities;
create trigger opportunities_notify_company_request
  after insert on public.opportunities
  for each row execute function public.notify_company_opportunity();
