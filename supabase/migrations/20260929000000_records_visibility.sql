-- Explicit Private/Public choice on records, replacing the implicit rule
-- "a record is globally searchable iff it has no linked people"
-- (20260716000000_global_records_search.sql), which users couldn't see.
--
-- Private = the tree's members + platform admins only.
-- Public  = also discoverable by every signed-in user via community search,
--           and visible to approved Finders/Indexers.
--
-- Run AFTER 20260716000000_global_records_search.sql and
-- 20260724000000_records_reviewer_visibility.sql.

alter table public.records
  add column if not exists is_public boolean not null default false;

-- Preserve every existing record's current effective visibility: unlinked
-- records were already globally searchable, linked ones were not.
update public.records set is_public = (person_ids = '{}');

-- Community search now keys off the explicit flag.
create or replace function public.search_records_global(
  p_query text default null,
  p_type  text default null,
  p_year  int  default null
)
returns table (
  id          text,
  type        text,
  title       text,
  repository  text,
  event_date  timestamptz,
  file_url    text,
  file_name   text,
  ocr_text    text,
  created_at  timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    r.id,
    r.type,
    r.title,
    r.repository,
    r.date as event_date,
    r.file_url,
    r.file_name,
    r.ocr_text,
    r.created_at
  from public.records r
  where
    r.is_public
    and (
      coalesce(nullif(trim(p_query), ''), '') <> '' or
      coalesce(nullif(trim(p_type), ''), '') <> '' or
      p_year is not null
    )
    and (nullif(trim(p_query), '') is null
         or r.title ilike '%' || trim(p_query) || '%'
         or r.repository ilike '%' || trim(p_query) || '%'
         or r.ocr_text ilike '%' || trim(p_query) || '%')
    and (nullif(trim(p_type), '') is null or r.type = trim(p_type))
    and (p_year is null or extract(year from r.date)::int = p_year)
  order by r.created_at desc
  limit 50;
$$;

-- Admins still see everything; approved Finders/Indexers now only see
-- public records outside their own trees (tree members are unaffected —
-- records_member_all still grants them their own trees' records).
drop policy if exists "records_reviewer_select" on public.records;
create policy "records_reviewer_select" on public.records
  for select
  to authenticated
  using (
    public.is_platform_admin()
    or (is_public and public.is_approved_collaborator())
  );
