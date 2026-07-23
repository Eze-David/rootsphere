-- The company needs a way to actually reach an approved Finder/Indexer and
-- confirm who they are, so an application now also collects a phone number
-- and one government-issued ID document, alongside the email address
-- (already collected, now user-editable rather than silently taken from the
-- account). Run AFTER 20260722030000_role_verification_documents.sql.

alter table public.role_verifications
  add column if not exists applicant_phone text not null default '',
  add column if not exists government_id_url text;
