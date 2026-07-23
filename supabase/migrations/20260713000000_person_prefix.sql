-- Add a name-prefix (title) field to the persons table, e.g. "Chief", "Dr.",
-- "Alhaji", "Otunba" — the counterpart to the existing suffix field.

alter table public.persons
  add column if not exists prefix text;
