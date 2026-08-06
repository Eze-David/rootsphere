-- "What to watch" media strip on the Home dashboard (Ancestry-style): a
-- horizontal row of admin-curated photos/videos shown to every signed-in
-- user. Content is entirely admin-managed — everyone can view, only
-- platform admins can add or remove items.

create table if not exists public.watch_items (
  id            text primary key,                    -- client-generated id
  media_type    text not null check (media_type in ('image', 'video')),
  media_url     text not null,                        -- the uploaded photo, or the uploaded video file
  thumbnail_url text,                                  -- cover image for a video card; unused for images
  category      text not null default '',              -- small eyebrow label, e.g. "Family stories"
  title         text not null,
  sort_order    integer not null default 0,
  created_by    uuid references auth.users (id),
  created_at    timestamptz not null default now()
);

alter table public.watch_items enable row level security;

-- Every signed-in user can see the strip.
drop policy if exists "watch_items_select" on public.watch_items;
create policy "watch_items_select" on public.watch_items
  for select
  to authenticated
  using (true);

-- Only platform admins can add, edit or remove items.
drop policy if exists "watch_items_admin_write" on public.watch_items;
create policy "watch_items_admin_write" on public.watch_items
  for all
  to authenticated
  using (public.is_platform_admin())
  with check (public.is_platform_admin());

-- ── Storage ──────────────────────────────────────────────────────────────────
-- Public-read bucket, same as every other upload bucket in this app. Unlike
-- the ownership-scoped buckets elsewhere, writes here are gated on
-- is_platform_admin() rather than the uploading user's own folder, since
-- this is curated, admin-only content rather than per-user data.

insert into storage.buckets (id, name, public)
values ('watch-media', 'watch-media', true)
on conflict (id) do nothing;

drop policy if exists "watch_media_admin_insert" on storage.objects;
create policy "watch_media_admin_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'watch-media' and public.is_platform_admin());

drop policy if exists "watch_media_admin_update" on storage.objects;
create policy "watch_media_admin_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'watch-media' and public.is_platform_admin());

drop policy if exists "watch_media_admin_delete" on storage.objects;
create policy "watch_media_admin_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'watch-media' and public.is_platform_admin());

drop policy if exists "watch_media_public_read" on storage.objects;
create policy "watch_media_public_read" on storage.objects
  for select to public
  using (bucket_id = 'watch-media');
