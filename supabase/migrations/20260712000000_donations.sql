-- Rootsphere — Phase 6: Donations (crowdfunding a research opportunity).
--
-- People can support a specific opportunity (e.g. "help find the origin of
-- the Deo family") with a one-time Paystack payment, separate from the paid
-- collaboration work itself (Finder/Indexer submissions). Paystack (not
-- Stripe, which doesn't support Nigerian payouts) processes the actual
-- charge. Donations are only ever written by the
-- `create-donation-transaction` and `paystack-webhook` Edge Functions
-- (service role) — clients read but never write directly, so nobody can fake
-- a "completed" row from the app. Run AFTER 20260707000000_opportunities.sql.

create table if not exists public.donations (
  id                 text primary key,                    -- Paystack transaction reference
  opportunity_id     text not null
                        references public.opportunities (id) on delete cascade,
  tree_id            text not null
                        references public.trees (id) on delete cascade,
  donor_id           uuid references auth.users (id) on delete set null,
  donor_name         text not null default 'Anonymous',
  donor_email        text,
  message            text,
  amount_cents       int not null,                        -- smallest currency unit (kobo for NGN)
  currency           text not null default 'ngn',
  status             text not null default 'pending',      -- pending | completed | failed | refunded
  provider_reference text,                                 -- Paystack's own transaction id, once charged
  created_at         timestamptz not null default now(),
  completed_at       timestamptz
);

create index if not exists donations_opportunity_id_idx on public.donations (opportunity_id);
create index if not exists donations_status_idx on public.donations (status);

-- ── Row-level security ─────────────────────────────────────────────────────────

alter table public.donations enable row level security;

-- Completed donations are visible to everyone (public support / social
-- proof, matches the opportunities board being a public community board);
-- a donor can also see their own still-pending/failed attempts.
drop policy if exists "donations_select" on public.donations;
create policy "donations_select" on public.donations
  for select
  to authenticated
  using (status = 'completed' or donor_id = auth.uid());

-- Intentionally no insert/update/delete policy for `authenticated`: rows are
-- only ever written by the Edge Functions via the service role (which
-- bypasses RLS), so a donation can't be marked "completed" without an actual
-- confirmed Paystack payment.

-- ── Realtime ──────────────────────────────────────────────────────────────────

alter publication supabase_realtime add table public.donations;
