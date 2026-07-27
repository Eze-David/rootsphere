-- In-app "Contact us" — lets a signed-in user write and submit a support
-- message directly from Profile, instead of only offering a mailto: link.
-- Every platform admin gets notified (reusing the existing notifications
-- system) so it's actually seen, not just logged. Run AFTER
-- 20260722010000_notifications.sql and 20260722020000_role_verifications.sql
-- (for is_platform_admin()).

create table if not exists public.support_messages (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  email      text not null,
  message    text not null,
  status     text not null default 'open' check (status in ('open', 'resolved')),
  created_at timestamptz not null default now()
);

create index if not exists support_messages_created_at_idx
  on public.support_messages (created_at desc);

alter table public.support_messages enable row level security;

-- A user sees their own messages; an admin sees everyone's (to respond).
drop policy if exists "support_messages_select" on public.support_messages;
create policy "support_messages_select" on public.support_messages
  for select
  to authenticated
  using (user_id = auth.uid() or public.is_platform_admin());

drop policy if exists "support_messages_insert" on public.support_messages;
create policy "support_messages_insert" on public.support_messages
  for insert
  to authenticated
  with check (user_id = auth.uid());

-- Only an admin marks a message resolved.
drop policy if exists "support_messages_update" on public.support_messages;
create policy "support_messages_update" on public.support_messages
  for update
  to authenticated
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

alter publication supabase_realtime add table public.support_messages;

-- ── Notify every platform admin ──────────────────────────────────────────────

alter table public.notifications
  add column if not exists support_message_id uuid
    references public.support_messages (id) on delete cascade;

create or replace function public.notify_support_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (user_id, type, title, body, support_message_id)
  select a.user_id, 'support_message', 'New support message', left(new.message, 140), new.id
  from public.platform_admins a;
  return new;
end;
$$;

drop trigger if exists support_messages_notify on public.support_messages;
create trigger support_messages_notify
  after insert on public.support_messages
  for each row execute function public.notify_support_message();
