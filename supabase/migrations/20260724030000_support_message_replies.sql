-- Lets an admin (and the original sender) reply within a support message's
-- thread, rather than only being able to mark it resolved. Run AFTER
-- 20260724020000_support_messages.sql.

create table if not exists public.support_message_replies (
  id                 uuid primary key default gen_random_uuid(),
  support_message_id uuid not null
                       references public.support_messages (id) on delete cascade,
  author_id          uuid not null references auth.users (id) on delete cascade,
  is_admin_reply     boolean not null default false,
  body               text not null,
  created_at         timestamptz not null default now()
);

create index if not exists support_message_replies_message_id_idx
  on public.support_message_replies (support_message_id, created_at);

alter table public.support_message_replies enable row level security;

-- Visible to the message's own sender and any platform admin — same
-- audience as the message itself.
drop policy if exists "support_message_replies_select" on public.support_message_replies;
create policy "support_message_replies_select" on public.support_message_replies
  for select
  to authenticated
  using (
    public.is_platform_admin()
    or exists (
      select 1 from public.support_messages sm
      where sm.id = support_message_id and sm.user_id = auth.uid()
    )
  );

-- Either side of the conversation can reply.
drop policy if exists "support_message_replies_insert" on public.support_message_replies;
create policy "support_message_replies_insert" on public.support_message_replies
  for insert
  to authenticated
  with check (
    public.is_platform_admin()
    or exists (
      select 1 from public.support_messages sm
      where sm.id = support_message_id and sm.user_id = auth.uid()
    )
  );

alter publication supabase_realtime add table public.support_message_replies;

-- Force author_id/is_admin_reply from the session rather than trusting
-- whatever the client sends, so a regular user can't claim an admin reply.
create or replace function public.set_support_reply_flag()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.author_id := auth.uid();
  new.is_admin_reply := public.is_platform_admin();
  return new;
end;
$$;

drop trigger if exists support_message_replies_set_flag on public.support_message_replies;
create trigger support_message_replies_set_flag
  before insert on public.support_message_replies
  for each row execute function public.set_support_reply_flag();

-- New activity reopens a resolved message, and notifies whichever side of
-- the conversation didn't just write.
create or replace function public.notify_support_message_reply()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  sender uuid;
begin
  update public.support_messages set status = 'open' where id = new.support_message_id;
  select user_id into sender from public.support_messages where id = new.support_message_id;

  if new.is_admin_reply then
    insert into public.notifications (user_id, type, title, body, support_message_id)
    values (sender, 'support_reply', 'Reply to your message', left(new.body, 140), new.support_message_id);
  else
    insert into public.notifications (user_id, type, title, body, support_message_id)
    select a.user_id, 'support_message', 'New reply to a support message', left(new.body, 140), new.support_message_id
    from public.platform_admins a;
  end if;
  return new;
end;
$$;

drop trigger if exists support_message_replies_notify on public.support_message_replies;
create trigger support_message_replies_notify
  after insert on public.support_message_replies
  for each row execute function public.notify_support_message_reply();
