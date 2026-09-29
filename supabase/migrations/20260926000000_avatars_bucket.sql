-- Profile "About me" edit: lets a signed-in user upload their own avatar.
-- Mirrors the `records`/`photos` bucket pattern (20260618000000_records.sql)
-- — public read, write restricted to the uploader's own uid-prefixed path.
-- Object paths are `<uid>/avatar.<ext>` (see AvatarStorageService), one file
-- per user, always overwritten.

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

drop policy if exists "avatars_auth_insert" on storage.objects;
create policy "avatars_auth_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_auth_update" on storage.objects;
create policy "avatars_auth_update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_auth_delete" on storage.objects;
create policy "avatars_auth_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "avatars_public_read" on storage.objects;
create policy "avatars_public_read" on storage.objects
  for select to public
  using (bucket_id = 'avatars');
