-- Add religion, residence/origin location, education, language, occupation and research fields to the persons table.

alter table public.persons
  add column if not exists religion          text,
  add column if not exists city              text,
  add column if not exists state_province    text,
  add column if not exists region            text,
  add column if not exists country           text,
  add column if not exists education         text,
  add column if not exists language          text,
  add column if not exists occupation        text,
  add column if not exists research_notes    text,
  add column if not exists research_questions text;
