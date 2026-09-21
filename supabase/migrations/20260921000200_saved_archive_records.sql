-- Digital Records Repository, phase 2: "Save collection" bookmarks. Simple
-- per-user saved-records list, no bookmark concept existed before this.

create table if not exists public.saved_archive_records (
  user_id    uuid not null references auth.users (id) on delete cascade,
  record_id  text not null references public.archive_records (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, record_id)
);

alter table public.saved_archive_records enable row level security;

drop policy if exists "saved_archive_records_own" on public.saved_archive_records;
create policy "saved_archive_records_own" on public.saved_archive_records
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

alter publication supabase_realtime add table public.saved_archive_records;
