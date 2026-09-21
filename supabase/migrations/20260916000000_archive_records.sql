-- Rootsphere — Digital Records Repository (admin-only archive/catalogue).
--
-- Distinct from `public.records` (a source document attached to one person/
-- tree): these rows belong to a curated, admin-only catalogue of digitized
-- civil/historical records (collection, country/region, date range, review
-- workflow, generated catalogue reference) with no tree_id at all. Reuses
-- `public.is_platform_admin()` from 20260722020000_role_verifications.sql —
-- run this migration after that one.

-- ── Table ──────────────────────────────────────────────────────────────────────

create table if not exists public.archive_records (
  id                 text primary key,                    -- client-generated id
  record_ref         text unique,                          -- e.g. RS-NGA-BEN-BIR-000142, assigned on submit
  title              text not null default '',
  type               text not null default 'other',        -- shares RecordType values with public.records
  collection         text not null default '',
  country            text not null default '',
  state_region       text not null default '',
  locality           text not null default '',
  date_range_start   int,
  date_range_end     int,
  repository_source  text not null default '',
  contributor        text not null default '',
  keywords           text[] not null default '{}',
  description        text,
  files              jsonb not null default '[]',          -- [{url, fileName, kind, contentType}]
  search_text        text,                                  -- OCR + manual index, concatenated for search
  access_status      text not null default 'restricted',    -- restricted | public
  review_status      text not null default 'draft',         -- draft | pending_review | published | rejected
  reviewer_note      text,
  created_by         uuid not null default auth.uid()
                       references auth.users (id) on delete cascade,
  reviewed_by        uuid references auth.users (id),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  reviewed_at        timestamptz
);

create index if not exists archive_records_review_status_idx
  on public.archive_records (review_status);
create index if not exists archive_records_created_by_idx
  on public.archive_records (created_by);

drop trigger if exists archive_records_set_updated_at on public.archive_records;
create trigger archive_records_set_updated_at
  before update on public.archive_records
  for each row execute function public.set_updated_at();

-- ── Catalogue reference generation ───────────────────────────────────────────
-- Best-effort internal scheme (not an ISO-strict code), assigned once a
-- record first moves to pending_review: RS-<country>-<state>-<type>-<seq>.

create sequence if not exists public.archive_records_seq;

create or replace function public.generate_archive_record_ref(
  p_country text, p_state text, p_type text
) returns text
language plpgsql
as $$
declare
  country_code text;
  state_code text;
  type_code text;
  seq_no bigint;
begin
  country_code := upper(substring(regexp_replace(coalesce(p_country, ''), '[^a-zA-Z]', '', 'g') from 1 for 3));
  if country_code = '' then country_code := 'GEN'; end if;

  state_code := upper(substring(regexp_replace(coalesce(p_state, ''), '[^a-zA-Z]', '', 'g') from 1 for 3));
  if state_code = '' then state_code := 'GEN'; end if;

  type_code := upper(substring(regexp_replace(coalesce(p_type, ''), '[^a-zA-Z]', '', 'g') from 1 for 3));
  if type_code = '' then type_code := 'GEN'; end if;

  seq_no := nextval('public.archive_records_seq');
  return 'RS-' || country_code || '-' || state_code || '-' || type_code || '-' || lpad(seq_no::text, 6, '0');
end;
$$;

create or replace function public.set_archive_record_ref()
returns trigger
language plpgsql
as $$
begin
  if new.review_status = 'pending_review' and (new.record_ref is null or new.record_ref = '') then
    new.record_ref := public.generate_archive_record_ref(new.country, new.state_region, new.type);
  end if;
  return new;
end;
$$;

drop trigger if exists archive_records_set_ref on public.archive_records;
create trigger archive_records_set_ref
  before insert or update on public.archive_records
  for each row execute function public.set_archive_record_ref();

-- ── Row-level security (admin-only — no end-user visibility in this phase) ────

alter table public.archive_records enable row level security;

drop policy if exists "archive_records_admin_all" on public.archive_records;
create policy "archive_records_admin_all" on public.archive_records
  for all
  to authenticated
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

-- ── Realtime ──────────────────────────────────────────────────────────────────

alter publication supabase_realtime add table public.archive_records;

-- ── Storage (archive_records bucket, private — admin-only) ────────────────────
-- Mirrors the upload paths written by ArchiveStorageService: `<uid>/<recordId>/…`.

insert into storage.buckets (id, name, public)
values ('archive_records', 'archive_records', false)
on conflict (id) do nothing;

drop policy if exists "archive_records_admin_insert" on storage.objects;
create policy "archive_records_admin_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'archive_records' and public.is_platform_admin());

drop policy if exists "archive_records_admin_update" on storage.objects;
create policy "archive_records_admin_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'archive_records' and public.is_platform_admin());

drop policy if exists "archive_records_admin_delete" on storage.objects;
create policy "archive_records_admin_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'archive_records' and public.is_platform_admin());

drop policy if exists "archive_records_admin_read" on storage.objects;
create policy "archive_records_admin_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'archive_records' and public.is_platform_admin());
