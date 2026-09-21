-- Corrects 20260916000100_grant_admin_vdst20029.sql: that email had a typo
-- and matched no account (logged a NOTICE, granted nothing). Correct email
-- is vdst2009@gmail.com. Same idempotent lookup-by-email approach.

do $$
declare
  target_uid uuid;
begin
  select id into target_uid from auth.users where email = 'vdst2009@gmail.com';

  if target_uid is null then
    raise notice 'No auth.users row for vdst2009@gmail.com yet — admin NOT granted. Re-run after they sign up.';
  else
    insert into public.platform_admins (user_id)
    values (target_uid)
    on conflict (user_id) do nothing;
    raise notice 'Granted platform_admin to % (vdst2009@gmail.com)', target_uid;
  end if;
end $$;
