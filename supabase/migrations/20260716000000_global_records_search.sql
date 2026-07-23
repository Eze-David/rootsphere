-- Rootsphere — Global (cross-tree) record discovery search.
--
-- Lets any signed-in user search for records nobody has linked to a person —
-- a standalone community contribution ("upload a record that isn't attached
-- to anybody") — regardless of which tree originally holds it. Mirrors
-- search_persons_global's approach (SECURITY DEFINER bypassing the
-- member-based RLS on `records`), scoped to `person_ids = '{}'` so a record
-- someone attached to their own family stays private to that tree as before;
-- only deliberately-unattached records become globally searchable.
--
-- Deliberately omits owner_id/notes/citation_override from the projection —
-- the searcher sees the document itself, not who uploaded it or their private
-- annotations.
--
-- Run AFTER 20260618000000_records.sql.

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
    r.person_ids = '{}'
    -- Require at least one search criterion (no "return everything").
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

grant execute on function public.search_records_global(text, text, int)
  to authenticated;
