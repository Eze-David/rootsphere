-- tree_members was never added to the realtime publication, so
-- FamilyTreeRepositorySupabase.watchMyPersonId()'s `.stream()` only ever
-- emitted its initial snapshot — "Mark as me" changes never reached the
-- dashboard live, only after a hot reload (which recreates the provider and
-- re-fetches). Same fix pattern as every other watched table in this app.

alter publication supabase_realtime add table public.tree_members;
