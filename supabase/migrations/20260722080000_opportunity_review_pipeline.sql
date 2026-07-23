-- A Finder/Indexer's submission no longer goes straight to the requester —
-- it now passes through the company first: claimed -> submitted ->
-- company_approved -> verified. The company can also reject a submission
-- back to the claimer with feedback (submitted -> claimed). Run AFTER
-- 20260722020000_role_verifications.sql (needs is_platform_admin()) and
-- 20260722010000_notifications.sql.

alter table public.opportunities
  add column if not exists company_feedback text,
  add column if not exists submitted_at timestamptz,
  add column if not exists company_approved_at timestamptz,
  add column if not exists company_reviewed_by uuid references auth.users (id);

-- ── Let admins actually reach these rows to update them ─────────────────────
-- The existing USING clause only covers the requester, the claimer, or an
-- open (unclaimed) row — an admin approving/rejecting someone else's
-- submission is none of those, so without this the UPDATE would be silently
-- blocked by RLS before the transition trigger below ever runs.

drop policy if exists "opportunities_update" on public.opportunities;
create policy "opportunities_update" on public.opportunities
  for update
  to authenticated
  using (
    requester_id = auth.uid()
    or claimer_id = auth.uid()
    or status = 'open'
    or public.is_platform_admin()
  )
  with check (true);

-- ── Enforce the pipeline ──────────────────────────────────────────────────────
-- Defense in depth, same reasoning as check_claim_qualification: the app
-- gates which buttons show, but the actual permission lives here so it can't
-- be bypassed by calling the API directly. open->claimed stays governed by
-- check_claim_qualification (unchanged); this covers every transition after
-- that, and rejects anything not explicitly recognised.

create or replace function public.check_status_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = old.status then
    return new;
  end if;

  if old.status = 'open' and new.status = 'claimed' then
    return new; -- handled by check_claim_qualification
  elsif old.status = 'claimed' and new.status = 'open' then
    if old.claimer_id is distinct from auth.uid() then
      raise exception 'only_claimer_can_unclaim'
        using errcode = 'insufficient_privilege';
    end if;
  elsif old.status = 'claimed' and new.status = 'submitted' then
    if old.claimer_id is distinct from auth.uid() then
      raise exception 'only_claimer_can_submit'
        using errcode = 'insufficient_privilege';
    end if;
  elsif old.status = 'submitted' and new.status = 'claimed' then
    if not public.is_platform_admin() then
      raise exception 'only_company_can_reject'
        using errcode = 'insufficient_privilege';
    end if;
    if new.company_feedback is null or length(trim(new.company_feedback)) = 0 then
      raise exception 'feedback_required_to_reject'
        using errcode = 'insufficient_privilege';
    end if;
  elsif old.status = 'submitted' and new.status = 'company_approved' then
    if not public.is_platform_admin() then
      raise exception 'only_company_can_approve'
        using errcode = 'insufficient_privilege';
    end if;
  elsif old.status = 'company_approved' and new.status = 'verified' then
    if old.requester_id is distinct from auth.uid() then
      raise exception 'only_requester_can_verify'
        using errcode = 'insufficient_privilege';
    end if;
  else
    raise exception 'invalid_status_transition: % -> %', old.status, new.status
      using errcode = 'insufficient_privilege';
  end if;

  return new;
end;
$$;

drop trigger if exists opportunities_check_status_transition on public.opportunities;
create trigger opportunities_check_status_transition
  before update on public.opportunities
  for each row execute function public.check_status_transition();

-- ── Notifications for each stage ─────────────────────────────────────────────

create or replace function public.notify_opportunity_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'claimed' and old.status = 'open' and new.claimer_id is not null then
    insert into public.notifications (user_id, type, title, body, tree_id, opportunity_id)
    values (
      new.requester_id,
      'opportunity_claimed',
      'Your request was claimed',
      coalesce(new.claimer_name, 'Someone') || ' claimed "' || new.title || '".',
      new.tree_id,
      new.id
    );
  elsif new.status = 'submitted' and old.status = 'claimed' then
    insert into public.notifications (user_id, type, title, body, tree_id, opportunity_id)
    select
      a.user_id,
      'opportunity_submitted',
      'New submission to review',
      coalesce(new.claimer_name, 'Someone') || ' submitted work for "' || new.title || '".',
      new.tree_id,
      new.id
    from public.platform_admins a;
  elsif new.status = 'claimed' and old.status = 'submitted' then
    insert into public.notifications (user_id, type, title, body, tree_id, opportunity_id)
    values (
      new.claimer_id,
      'opportunity_company_rejected',
      'Changes requested',
      'The company sent back "' || new.title || '": ' || coalesce(new.company_feedback, ''),
      new.tree_id,
      new.id
    );
  elsif new.status = 'company_approved' and old.status = 'submitted' then
    insert into public.notifications (user_id, type, title, body, tree_id, opportunity_id)
    values (
      new.requester_id,
      'opportunity_company_approved',
      'Ready for your review',
      'The company approved work on "' || new.title || '" — take a look and verify.',
      new.tree_id,
      new.id
    );
  elsif new.status = 'verified' and old.status = 'company_approved' and new.claimer_id is not null then
    insert into public.notifications (user_id, type, title, body, tree_id, opportunity_id)
    values (
      new.claimer_id,
      'opportunity_verified',
      'Your work was verified',
      '"' || new.title || '" was verified. Thank you for contributing.',
      new.tree_id,
      new.id
    );
  end if;
  return new;
end;
$$;
