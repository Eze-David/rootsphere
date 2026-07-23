-- Rootsphere — Global person discovery search.
--
-- Lets a signed-in user search for people across ALL trees (not just the ones
-- they belong to), powering cross-tree "hints". This deliberately bypasses the
-- member-based RLS on `persons` via SECURITY DEFINER, so it returns only a
-- minimal, privacy-conscious projection — names, life years, birth place, and
-- the owning tree — never notes, photos, relationships, or contact data.
--
-- Run AFTER 20260617000000_tree_members.sql.

create or replace function public.search_persons_global(
  p_first text default null,
  p_last  text default null,
  p_place text default null,
  p_year  int  default null
)
returns table (
  id          text,
  tree_id     text,
  tree_name   text,
  given_name  text,
  surname     text,
  sex         text,
  birth_year  int,
  death_year  int,
  birth_place text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.tree_id,
    t.name as tree_name,
    p.given_name,
    p.surname,
    p.sex,
    extract(year from p.birth_date)::int as birth_year,
    extract(year from p.death_date)::int as death_year,
    p.birth_place
  from public.persons p
  join public.trees t on t.id = p.tree_id
  where
    -- Require at least one search criterion (no "return everything").
    (
      coalesce(nullif(trim(p_first), ''), '') <> '' or
      coalesce(nullif(trim(p_last), ''), '') <> '' or
      coalesce(nullif(trim(p_place), ''), '') <> '' or
      p_year is not null
    )
    and (nullif(trim(p_first), '') is null
         or p.given_name ilike '%' || trim(p_first) || '%')
    and (nullif(trim(p_last), '') is null
         or p.surname ilike '%' || trim(p_last) || '%')
    and (nullif(trim(p_place), '') is null
         or p.birth_place ilike '%' || trim(p_place) || '%'
         or p.death_place ilike '%' || trim(p_place) || '%')
    and (p_year is null
         or extract(year from p.birth_date)::int = p_year
         or extract(year from p.death_date)::int = p_year)
  order by p.surname, p.given_name
  limit 50;
$$;

grant execute on function public.search_persons_global(text, text, text, int)
  to authenticated;
