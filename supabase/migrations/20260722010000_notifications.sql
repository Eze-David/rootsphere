-- In-app notifications (the bell icon on Home). Rows are only ever written
-- by the triggers below (SECURITY DEFINER, running as the table owner), the
-- same pattern donations already uses for "only the system can write
-- this" — a client can never fake a notification for itself or spoof one to
-- another user. Run AFTER 20260712000000_donations.sql and
-- 20260617000000_tree_members.sql.

create table if not exists public.notifications (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  type           text not null,   -- tree_activity | opportunity_claimed | opportunity_verified | donation_received | tree_member_joined
  title          text not null,
  body           text not null,
  tree_id        text references public.trees (id) on delete cascade,
  person_id      text references public.persons (id) on delete cascade,
  opportunity_id text references public.opportunities (id) on delete cascade,
  read           boolean not null default false,
  created_at     timestamptz not null default now()
);

create index if not exists notifications_user_id_idx
  on public.notifications (user_id, created_at desc);

alter table public.notifications enable row level security;

-- A user can only ever see/update their own notifications (marking read).
drop policy if exists "notifications_select" on public.notifications;
create policy "notifications_select" on public.notifications
  for select
  to authenticated
  using (user_id = auth.uid());

drop policy if exists "notifications_update_own" on public.notifications;
create policy "notifications_update_own" on public.notifications
  for update
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Intentionally no insert policy for `authenticated` — rows are only ever
-- written by the SECURITY DEFINER trigger functions below.

alter publication supabase_realtime add table public.notifications;

-- ── 1. Tree activity: a person is added or edited ───────────────────────────
-- Fans out to every OTHER member of the tree (not the person who made the
-- change). Skips no-op updates (e.g. an upsert that changed nothing).

create or replace function public.notify_person_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  actor uuid := auth.uid();
  person_name text;
  tree_name text;
begin
  if tg_op = 'UPDATE' and old is not distinct from new then
    return new;
  end if;

  person_name := nullif(trim(coalesce(new.given_name, '') || ' ' || coalesce(new.surname, '')), '');
  select t.name into tree_name from public.trees t where t.id = new.tree_id;

  insert into public.notifications (user_id, type, title, body, tree_id, person_id)
  select
    m.user_id,
    'tree_activity',
    case when tg_op = 'INSERT' then 'New person added' else 'Person updated' end,
    coalesce(person_name, 'Someone') || ' was ' ||
      (case when tg_op = 'INSERT' then 'added to' else 'updated in' end) || ' ' ||
      coalesce(tree_name, 'your family tree'),
    new.tree_id,
    new.id
  from public.tree_members m
  where m.tree_id = new.tree_id
    and m.user_id is distinct from actor;

  return new;
end;
$$;

drop trigger if exists persons_notify_change on public.persons;
create trigger persons_notify_change
  after insert or update on public.persons
  for each row execute function public.notify_person_change();

-- ── 2. Opportunity claimed / verified ────────────────────────────────────────

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
  elsif new.status = 'verified' and old.status = 'claimed' and new.claimer_id is not null then
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

drop trigger if exists opportunities_notify_status on public.opportunities;
create trigger opportunities_notify_status
  after update on public.opportunities
  for each row execute function public.notify_opportunity_status_change();

-- ── 3. Donation received ─────────────────────────────────────────────────────
-- Only ever written by the paystack-webhook Edge Function (service role),
-- which bypasses this table's own RLS — the trigger still fires normally.

create or replace function public.notify_donation_completed()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  opp public.opportunities;
begin
  if new.status = 'completed' and (tg_op = 'INSERT' or old.status is distinct from 'completed') then
    select * into opp from public.opportunities where id = new.opportunity_id;
    if found then
      insert into public.notifications (user_id, type, title, body, tree_id, opportunity_id)
      values (
        opp.requester_id,
        'donation_received',
        'You received a donation',
        coalesce(new.donor_name, 'Someone') || ' supported "' || opp.title || '".',
        new.tree_id,
        new.opportunity_id
      );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists donations_notify_completed on public.donations;
create trigger donations_notify_completed
  after insert or update on public.donations
  for each row execute function public.notify_donation_completed();

-- ── 4. Someone joins your tree ───────────────────────────────────────────────
-- Skips the owner's own auto-enrolment row (trees_add_owner_member, from
-- 20260617000000_tree_members.sql) so the owner isn't notified about
-- themselves the moment they create a tree.

create or replace function public.notify_tree_member_joined()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  owner uuid;
begin
  select owner_id into owner from public.trees where id = new.tree_id;
  if owner is not null and owner is distinct from new.user_id then
    insert into public.notifications (user_id, type, title, body, tree_id)
    values (
      owner,
      'tree_member_joined',
      'New member joined your tree',
      'Someone joined your family tree.',
      new.tree_id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists tree_members_notify_join on public.tree_members;
create trigger tree_members_notify_join
  after insert on public.tree_members
  for each row execute function public.notify_tree_member_joined();
