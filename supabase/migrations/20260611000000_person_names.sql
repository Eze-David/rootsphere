-- Add extra name fields to the persons table.

alter table public.persons
  add column if not exists other_names text,
  add column if not exists nickname   text,
  add column if not exists suffix      text;
