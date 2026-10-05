-- Admins hear about and can review signed Researcher Code of Conduct
-- undertakings. Run AFTER 20261006000000_researcher_undertakings.sql.

-- Notify every platform admin once a researcher accepts.
create or replace function public.notify_researcher_undertaking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.notifications (user_id, type, title, body)
  select
    a.user_id,
    'researcher_undertaking',
    'Code of Conduct signed',
    new.signed_name || ' accepted the Researcher Code of Conduct and '
      || 'Confidentiality Undertaking.'
  from public.platform_admins a
  where a.user_id <> new.user_id;
  return new;
end;
$$;

drop trigger if exists researcher_undertakings_notify on public.researcher_undertakings;
create trigger researcher_undertakings_notify
  after insert on public.researcher_undertakings
  for each row execute function public.notify_researcher_undertaking();

-- Admin list with the signer's account email (auth.users isn't readable
-- from the client, hence SECURITY DEFINER + an explicit admin check).
create or replace function public.list_researcher_undertakings()
returns table (
  user_id     uuid,
  signed_name text,
  email       text,
  version     text,
  accepted_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_platform_admin() then
    raise exception 'admin_only' using errcode = 'insufficient_privilege';
  end if;
  return query
    select ru.user_id, ru.signed_name, u.email::text, ru.version, ru.accepted_at
    from public.researcher_undertakings ru
    left join auth.users u on u.id = ru.user_id
    order by ru.accepted_at desc;
end;
$$;

grant execute on function public.list_researcher_undertakings() to authenticated;
