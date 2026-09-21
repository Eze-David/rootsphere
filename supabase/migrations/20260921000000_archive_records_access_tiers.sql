-- Digital Records Repository, phase 2: 3-tier access (Online / Permission /
-- Archive) replacing the phase-1 restricted/public label, plus the RLS
-- needed to let end users actually browse published catalogue records —
-- phase 1 locked archive_records down to admins only (see
-- 20260916000000_archive_records.sql), with no way for anyone else to read
-- even a published row. Run AFTER that migration.

-- Relabel existing data: public -> online, restricted -> permission.
update public.archive_records set access_status = 'online' where access_status = 'public';
update public.archive_records set access_status = 'permission' where access_status = 'restricted';

alter table public.archive_records alter column access_status set default 'permission';

-- Any signed-in user can see the CATALOGUE METADATA of a published record —
-- browsing/search works even for archive-tier (not digitized) records,
-- which is the point (it's a research aid to where records are held, not
-- just a file index). Actual FILE access is gated separately below by
-- access_status. Admins keep full access via the existing
-- archive_records_admin_all policy (unaffected, still `for all`).
drop policy if exists "archive_records_published_select" on public.archive_records;
create policy "archive_records_published_select" on public.archive_records
  for select
  to authenticated
  using (review_status = 'published');

-- Authenticated users can read a stored file only when it belongs to a
-- published + online record. Object paths are `<uid>/<recordId>/<file>`
-- (see ArchiveStorageService), so the record id is the 2nd path segment.
drop policy if exists "archive_records_online_file_select" on storage.objects;
create policy "archive_records_online_file_select" on storage.objects
  for select
  to authenticated
  using (
    bucket_id = 'archive_records'
    and exists (
      select 1 from public.archive_records ar
      where ar.id = (storage.foldername(name))[2]
        and ar.review_status = 'published'
        and ar.access_status = 'online'
    )
  );
