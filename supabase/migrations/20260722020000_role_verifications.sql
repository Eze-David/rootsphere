-- Not everyone claiming a Finder/Indexer opportunity is actually qualified
-- to do that work, so claiming now requires the company to have approved
-- the claimer for that specific role first. Run AFTER
-- 20260707000000_opportunities.sql.

-- ── Platform admins ("the company") ─────────────────────────────────────────
-- A deliberately tiny, RLS-locked-down allow-list — no client policy grants
-- read/write on this table at all, so the only way onto it is a direct SQL
-- insert (Supabase SQL Editor / `supabase db` as the project owner), never
-- through the app. is_platform_admin() is how everything else checks it.

create table if not exists public.platform_admins (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.platform_admins enable row level security;

create or replace function public.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_admins a where a.user_id = auth.uid()
  );
$$;

-- ── Role verifications (Finder / Indexer qualification) ─────────────────────

-- `applicant_name`/`applicant_email` are denormalized onto the row (captured
-- client-side at application time) rather than joined from `auth.users` —
-- the client (including an admin reviewing applications) can't query that
-- table directly. Same pattern `opportunities.requester_name` and
-- `donations.donor_name` already use.
create table if not exists public.role_verifications (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users (id) on delete cascade,
  applicant_name  text not null,
  applicant_email text not null,
  role            text not null check (role in ('finder', 'indexer')),
  status          text not null default 'pending'
                     check (status in ('pending', 'approved', 'rejected')),
  note            text,
  created_at      timestamptz not null default now(),
  reviewed_at     timestamptz,
  reviewed_by     uuid references auth.users (id),
  unique (user_id, role)
);

create index if not exists role_verifications_status_idx
  on public.role_verifications (status);

alter table public.role_verifications enable row level security;

-- A user sees their own applications; an admin sees everyone's (to review).
drop policy if exists "role_verifications_select" on public.role_verifications;
create policy "role_verifications_select" on public.role_verifications
  for select
  to authenticated
  using (user_id = auth.uid() or public.is_platform_admin());

-- Applying for the first time.
drop policy if exists "role_verifications_insert" on public.role_verifications;
create policy "role_verifications_insert" on public.role_verifications
  for insert
  to authenticated
  with check (user_id = auth.uid() and status = 'pending');

-- A user may only resubmit their own (back to pending, e.g. after a
-- rejection); only an admin can actually set approved/rejected.
drop policy if exists "role_verifications_update" on public.role_verifications;
create policy "role_verifications_update" on public.role_verifications
  for update
  to authenticated
  using (user_id = auth.uid() or public.is_platform_admin())
  with check (
    (user_id = auth.uid() and status = 'pending')
    or public.is_platform_admin()
  );

alter publication supabase_realtime add table public.role_verifications;

-- ── Enforce it on claiming ───────────────────────────────────────────────────
-- Defense in depth: the app checks this before showing "Claim" at all, but
-- the actual permission lives here, server-side, so it can't be bypassed by
-- calling the API directly.

create or replace function public.check_claim_qualification()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'open' and new.status = 'claimed' and new.claimer_id is not null then
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

drop trigger if exists opportunities_check_qualification on public.opportunities;
create trigger opportunities_check_qualification
  before update on public.opportunities
  for each row execute function public.check_claim_qualification();
