-- Grants platform-admin access to vdst20029@gmail.com (see platform_admins /
-- is_platform_admin() in 20260722020000_role_verifications.sql). Looked up by
-- email rather than a hardcoded uuid so this is safe to run before or after
-- the account signs up — it's a no-op (with a NOTICE) if the account doesn't
-- exist yet.

do $$
declare
  target_uid uuid;
begin
  select id into target_uid from auth.users where email = 'vdst20029@gmail.com';

  if target_uid is null then
    raise notice 'No auth.users row for vdst20029@gmail.com yet — admin NOT granted. Re-run after they sign up.';
  else
    insert into public.platform_admins (user_id)
    values (target_uid)
    on conflict (user_id) do nothing;
    raise notice 'Granted platform_admin to % (vdst20029@gmail.com)', target_uid;
  end if;
end $$;
