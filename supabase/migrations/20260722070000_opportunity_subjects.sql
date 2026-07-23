-- Structured details about the PERSON an opportunity is researching (not the
-- requester's own account) — name variants, country, photos, and supporting
-- documents that help a Finder/Indexer do the work. Deliberately kept out of
-- the public board: visible only to the requester who entered it, whoever
-- claims the opportunity, and platform admins — enforced here via RLS, not
-- just by which screens the client happens to show it on. Run AFTER
-- 20260707000000_opportunities.sql.

create table if not exists public.opportunity_subjects (
  opportunity_id  text primary key
                    references public.opportunities (id) on delete cascade,
  first_name      text not null default '',
  middle_name     text not null default '',
  last_name       text not null default '',
  nick_name       text not null default '',
  country         text not null default '',
  additional_info text,
  photo_urls      text[] not null default '{}',
  document_urls   text[] not null default '{}',
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

drop trigger if exists opportunity_subjects_set_updated_at on public.opportunity_subjects;
create trigger opportunity_subjects_set_updated_at
  before update on public.opportunity_subjects
  for each row execute function public.set_updated_at();

alter table public.opportunity_subjects enable row level security;

-- Visible only to the opportunity's own requester/claimer/admin — same
-- reasoning as the `for_company` opportunities policy, applied per-row here
-- instead of per-opportunity since this is a satellite table.
drop policy if exists "opportunity_subjects_select" on public.opportunity_subjects;
create policy "opportunity_subjects_select" on public.opportunity_subjects
  for select
  to authenticated
  using (
    exists (
      select 1 from public.opportunities o
      where o.id = opportunity_subjects.opportunity_id
        and (
          o.requester_id = auth.uid()
          or o.claimer_id = auth.uid()
          or public.is_platform_admin()
        )
    )
  );

-- Only the requester can write it, and only for their own opportunity.
drop policy if exists "opportunity_subjects_insert" on public.opportunity_subjects;
create policy "opportunity_subjects_insert" on public.opportunity_subjects
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.opportunities o
      where o.id = opportunity_subjects.opportunity_id
        and o.requester_id = auth.uid()
    )
  );

drop policy if exists "opportunity_subjects_update" on public.opportunity_subjects;
create policy "opportunity_subjects_update" on public.opportunity_subjects
  for update
  to authenticated
  using (
    exists (
      select 1 from public.opportunities o
      where o.id = opportunity_subjects.opportunity_id
        and o.requester_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.opportunities o
      where o.id = opportunity_subjects.opportunity_id
        and o.requester_id = auth.uid()
    )
  );

drop policy if exists "opportunity_subjects_delete" on public.opportunity_subjects;
create policy "opportunity_subjects_delete" on public.opportunity_subjects
  for delete
  to authenticated
  using (
    exists (
      select 1 from public.opportunities o
      where o.id = opportunity_subjects.opportunity_id
        and o.requester_id = auth.uid()
    )
  );

-- ── Storage (photos / documents) ─────────────────────────────────────────────
-- Same public-bucket-with-unguessable-path convention as `records` and
-- `role-verification-documents` — the DB row (URLs) is what's actually
-- access-controlled via the RLS above; the object storage read policy stays
-- public to match how every other upload bucket in this app works.

insert into storage.buckets (id, name, public)
values ('opportunity-subjects', 'opportunity-subjects', true)
on conflict (id) do nothing;

drop policy if exists "opportunity_subjects_files_insert" on storage.objects;
create policy "opportunity_subjects_files_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'opportunity-subjects'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "opportunity_subjects_files_delete" on storage.objects;
create policy "opportunity_subjects_files_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'opportunity-subjects'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "opportunity_subjects_files_read" on storage.objects;
create policy "opportunity_subjects_files_read" on storage.objects
  for select to public
  using (bucket_id = 'opportunity-subjects');
