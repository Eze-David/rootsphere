-- Rootsphere — Phase 2 family-tree backend.
--
-- Mirrors the client `Person` model: relationships are stored as id arrays and
-- timeline events as JSONB, so the Supabase repository maps 1:1 with the local
-- implementation. Run this in the Supabase SQL editor (or via the CLI).

-- ── Tables ───────────────────────────────────────────────────────────────────

create table if not exists public.trees (
  id          text primary key,                       -- client-generated id/slug
  owner_id    uuid not null default auth.uid()
                 references auth.users (id) on delete cascade,
  name        text not null default 'My Family Tree',
  created_at  timestamptz not null default now()
);

create table if not exists public.persons (
  id            text primary key,                      -- client-generated id
  tree_id       text not null
                   references public.trees (id) on delete cascade,
  owner_id      uuid not null default auth.uid()
                   references auth.users (id) on delete cascade,
  given_name    text not null default '',
  surname       text not null default '',
  sex           text not null default 'unknown',
  birth_date    timestamptz,
  death_date    timestamptz,
  birth_place   text,
  death_place   text,
  photo_url     text,
  notes         text,
  parent_ids    text[]  not null default '{}',
  spouse_ids    text[]  not null default '{}',
  events        jsonb   not null default '[]'::jsonb,
  photo_gallery text[]  not null default '{}',
  updated_at    timestamptz not null default now()
);

create index if not exists persons_tree_id_idx on public.persons (tree_id);
create index if not exists persons_owner_id_idx on public.persons (owner_id);

-- Keep updated_at fresh on every write.
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists persons_set_updated_at on public.persons;
create trigger persons_set_updated_at
  before update on public.persons
  for each row execute function public.set_updated_at();

-- ── Row-level security ───────────────────────────────────────────────────────
-- Owner-only access for Phase 2. Phase 5 (collaboration) can add member-based
-- policies on top of this without changing the client.

alter table public.trees   enable row level security;
alter table public.persons enable row level security;

drop policy if exists "trees_owner_all" on public.trees;
create policy "trees_owner_all" on public.trees
  for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists "persons_owner_all" on public.persons;
create policy "persons_owner_all" on public.persons
  for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- ── Realtime ─────────────────────────────────────────────────────────────────
-- Enables `.stream()` from the client for live tree updates.

alter publication supabase_realtime add table public.persons;

-- ── Storage policies (photos bucket) ─────────────────────────────────────────
-- Mirrors the upload paths written by PhotoStorageService: `<uid>/<personId>/…`.
-- The bucket itself ("photos") must be created in the dashboard (public read).

drop policy if exists "photos_auth_insert" on storage.objects;
create policy "photos_auth_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "photos_auth_update" on storage.objects;
create policy "photos_auth_update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "photos_auth_delete" on storage.objects;
create policy "photos_auth_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "photos_public_read" on storage.objects;
create policy "photos_public_read" on storage.objects
  for select to public
  using (bucket_id = 'photos');
