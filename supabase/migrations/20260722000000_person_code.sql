-- Every person gets a short, human-shareable 6-character alphanumeric code,
-- generated client-side on creation (see Person.generateCode) and shown on
-- both their profile and their card in the tree. Unique so it can double as
-- a lookup key later; nullable so existing rows (created before this
-- feature) don't need a backfill to stay valid.

alter table public.persons
  add column if not exists code text;

create unique index if not exists persons_code_key
  on public.persons (code)
  where code is not null;
