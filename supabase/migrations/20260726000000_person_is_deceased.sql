-- Lets a person be explicitly marked living/deceased independent of
-- whether an exact death date is known — previously "Living" was purely
-- inferred from death_date being null, so there was no way to mark someone
-- deceased without knowing when. Null defers to the old death_date-based
-- inference (for people added before this column existed); true/false is
-- set explicitly via the editor's Living/Dead picker.

alter table public.persons
  add column if not exists is_deceased boolean;
