-- Lets someone support Rootsphere generally — not tied to any specific
-- research opportunity — so a visitor who doesn't want an account can still
-- donate straight from the auth screen. Opportunity-linked donations
-- (`opportunity_id`/`tree_id` set) work exactly as before; a general
-- donation just leaves both null.

alter table public.donations
  alter column opportunity_id drop not null,
  alter column tree_id drop not null;

-- The existing FK constraints already tolerate nulls (they only fire when a
-- value is present), so no further change is needed there.
