-- Add video and voice-note media galleries to the persons table.

alter table public.persons
  add column if not exists video_gallery text[] not null default '{}',
  add column if not exists voice_notes   text[] not null default '{}';
