-- Index the donations table's donor_id: the new "My donations" screen
-- queries `donor_id = auth.uid()` (see the donations_select RLS policy),
-- which the existing opportunity_id/status indexes don't help with.

create index if not exists donations_donor_id_idx on public.donations (donor_id);
