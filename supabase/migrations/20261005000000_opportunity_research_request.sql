-- The RootSphere Family History Foundation's research request form
-- (requester contact details, ancestor facts, research question, sources
-- already checked, desired output, declaration & consent), captured when an
-- opportunity is posted. Lives on opportunity_subjects so it inherits that
-- table's RLS — readable only by the requester, the claimer and platform
-- admins; never shown on the public board.

alter table public.opportunity_subjects
  add column if not exists research_request jsonb not null default '{}'::jsonb;
