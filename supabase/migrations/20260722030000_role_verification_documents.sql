-- Lets an applicant attach supporting certificates/credentials to a Finder
-- or Indexer application — optional, since not everyone has a formal
-- certificate but may still be worth approving on experience alone. Run
-- AFTER 20260722020000_role_verifications.sql.

alter table public.role_verifications
  add column if not exists document_urls text[] not null default '{}';

-- ── Storage (role-verification-documents bucket) ─────────────────────────────
-- Mirrors the upload path written by RoleVerificationStorageService:
-- `<uid>/<applicationId>/<timestamp>.<ext>`. Same public-bucket-with-
-- unguessable-path model as the existing `records`/`photos` buckets — create
-- the bucket in the dashboard or via:
--   insert into storage.buckets (id, name, public)
--   values ('role-verification-documents', 'role-verification-documents', true)
--   on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('role-verification-documents', 'role-verification-documents', true)
on conflict (id) do nothing;

drop policy if exists "role_verification_documents_auth_insert" on storage.objects;
create policy "role_verification_documents_auth_insert" on storage.objects
  for insert
  to authenticated
  with check (
    bucket_id = 'role-verification-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "role_verification_documents_auth_delete" on storage.objects;
create policy "role_verification_documents_auth_delete" on storage.objects
  for delete
  to authenticated
  using (
    bucket_id = 'role-verification-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "role_verification_documents_public_read" on storage.objects;
create policy "role_verification_documents_public_read" on storage.objects
  for select
  to public
  using (bucket_id = 'role-verification-documents');
