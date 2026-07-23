-- Platform admins ("the company") can claim any opportunity, not just ones
-- explicitly routed to the company — same trust level as approving/
-- rejecting submissions, so requiring a separate Finder/Indexer application
-- from staff who are already vetted as admins was redundant. Run AFTER
-- 20260722050000_opportunity_company_requests.sql.

create or replace function public.check_claim_qualification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'open' and new.status = 'claimed' and new.claimer_id is not null then
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
