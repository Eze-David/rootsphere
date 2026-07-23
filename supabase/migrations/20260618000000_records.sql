-- Rootsphere — Phase 3: Records & Media.
--
-- Source documents / media attached to a family tree. Mirrors the client
-- `Record` model (person links as a text[] array). Member-based RLS reuses
-- `is_tree_member()` from 20260617000000_tree_members.sql so every tree member
-- can read/write its records. Run this AFTER the tree-members migration.

-- ── Table ──────────────────────────────────────────────────────────────────────

create table if not exists public.records (
  id                text primary key,                    -- client-generated id
  tree_id           text not null
                       references public.trees (id) on delete cascade,
  owner_id          uuid not null default auth.uid()
                       references auth.users (id) on delete cascade,
  type              text not null default 'other',
  title             text not null default '',
  repository        text not null default '',
  date              timestamptz,
  file_url          text,
  file_name         text,
  ocr_text          text,
  citation_override text,
  notes             text,
  person_ids        text[] not null default '{}',
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create index if not exists records_tree_id_idx on public.records (tree_id);
create index if not exists records_owner_id_idx on public.records (owner_id);

-- Keep updated_at fresh (reuses set_updated_at() from the tree migration).
drop trigger if exists records_set_updated_at on public.records;
create trigger records_set_updated_at
  before update on public.records
  for each row execute function public.set_updated_at();

-- ── Row-level security (member-based) ─────────────────────────────────────────

alter table public.records enable row level security;

drop policy if exists "records_member_all" on public.records;
create policy "records_member_all" on public.records
  for all
  to authenticated
  using (public.is_tree_member(tree_id))
  with check (public.is_tree_member(tree_id));

-- ── Realtime ──────────────────────────────────────────────────────────────────

alter publication supabase_realtime add table public.records;

-- ── Storage policies (records bucket) ─────────────────────────────────────────
-- Mirrors the upload paths written by RecordStorageService: `<uid>/<recordId>/…`.
-- Create the bucket ("records", public read) in the dashboard or via:
--   insert into storage.buckets (id, name, public)
--   values ('records', 'records', true) on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('records', 'records', true)
on conflict (id) do nothing;

drop policy if exists "records_auth_insert" on storage.objects;
create policy "records_auth_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'records'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "records_auth_update" on storage.objects;
create policy "records_auth_update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'records'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "records_auth_delete" on storage.objects;
create policy "records_auth_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'records'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "records_public_read" on storage.objects;
create policy "records_public_read" on storage.objects
  for select to public
  using (bucket_id = 'records');
