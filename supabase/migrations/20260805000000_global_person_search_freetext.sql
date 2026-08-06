-- Free-text variant of search_persons_global (20260619000000), for the main
-- "All records" library's single search box — which has one term, not
-- separate first/last/place fields, so it needs OR-across-fields matching
-- rather than AND. Additive: the original stays as-is for the per-category
-- search screens' structured form.
--
-- Run AFTER 20260617000000_tree_members.sql.

create or replace function public.search_persons_global_freetext(
  p_query text default null,
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
      coalesce(nullif(trim(p_query), ''), '') <> '' or
      p_year is not null
    )
    and (nullif(trim(p_query), '') is null
         or p.given_name ilike '%' || trim(p_query) || '%'
         or p.surname ilike '%' || trim(p_query) || '%'
         or p.birth_place ilike '%' || trim(p_query) || '%'
         or p.death_place ilike '%' || trim(p_query) || '%')
    and (p_year is null
         or extract(year from p.birth_date)::int = p_year
         or extract(year from p.death_date)::int = p_year)
  order by p.surname, p.given_name
  limit 50;
$$;

grant execute on function public.search_persons_global_freetext(text, int)
  to authenticated;
