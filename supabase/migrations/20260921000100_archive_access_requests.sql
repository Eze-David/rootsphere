-- Digital Records Repository, phase 2: "Permission" tier access requests.
-- Mirrors role_verifications' request/review shape (20260722020000) —
-- a user requests access to a Permission-tier record, every admin gets
-- notified, an admin approves/rejects. Approving flips the record to
-- Online for everyone (no per-user file ACLs in this pass — see plan).
-- Run AFTER 20260921000000_archive_records_access_tiers.sql and
-- 20260722010000_notifications.sql.

create table if not exists public.archive_access_requests (
  id          uuid primary key default gen_random_uuid(),
  record_id   text not null references public.archive_records (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  status      text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  note        text,
  created_at  timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users (id),
  unique (record_id, user_id)
);

create index if not exists archive_access_requests_record_id_idx
  on public.archive_access_requests (record_id);

alter table public.archive_access_requests enable row level security;

drop policy if exists "archive_access_requests_select" on public.archive_access_requests;
create policy "archive_access_requests_select" on public.archive_access_requests
  for select
  to authenticated
  using (user_id = auth.uid() or public.is_platform_admin());

drop policy if exists "archive_access_requests_insert" on public.archive_access_requests;
create policy "archive_access_requests_insert" on public.archive_access_requests
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- Only an admin reviews (approve/reject).
drop policy if exists "archive_access_requests_update" on public.archive_access_requests;
create policy "archive_access_requests_update" on public.archive_access_requests
  for update
  to authenticated
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

alter publication supabase_realtime add table public.archive_access_requests;

-- ── Notifications wiring ──────────────────────────────────────────────────

alter table public.notifications
  add column if not exists archive_record_id text
    references public.archive_records (id) on delete cascade;
alter table public.notifications
  add column if not exists archive_access_request_id uuid
    references public.archive_access_requests (id) on delete cascade;

create or replace function public.notify_archive_access_requested()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  record_title text;
begin
  select title into record_title from public.archive_records where id = new.record_id;
  insert into public.notifications
    (user_id, type, title, body, archive_record_id, archive_access_request_id)
  select a.user_id, 'archive_access_requested', 'Access requested',
    left(coalesce(record_title, 'A record'), 140), new.record_id, new.id
  from public.platform_admins a;
  return new;
end;
$$;

drop trigger if exists archive_access_requests_notify_insert on public.archive_access_requests;
create trigger archive_access_requests_notify_insert
  after insert on public.archive_access_requests
  for each row execute function public.notify_archive_access_requested();

create or replace function public.notify_archive_access_reviewed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  record_title text;
begin
  if new.status = old.status or new.status = 'pending' then
    return new;
  end if;

  select title into record_title from public.archive_records where id = new.record_id;

  insert into public.notifications
    (user_id, type, title, body, archive_record_id, archive_access_request_id)
  values (
    new.user_id,
    case when new.status = 'approved' then 'archive_access_approved' else 'archive_access_rejected' end,
    case when new.status = 'approved' then 'Access approved' else 'Access request rejected' end,
    left(coalesce(record_title, 'A record'), 140),
    new.record_id,
    new.id
  );

  if new.status = 'approved' then
    update public.archive_records set access_status = 'online' where id = new.record_id;
  end if;

  return new;
end;
$$;

drop trigger if exists archive_access_requests_notify_review on public.archive_access_requests;
create trigger archive_access_requests_notify_review
  after update on public.archive_access_requests
  for each row execute function public.notify_archive_access_reviewed();
