-- Monthly/Annual recurring donations (Paystack Plans + Subscriptions) —
-- web/Android only. iOS keeps one-time donations via Apple IAP; a real
-- auto-renewable-subscription IAP product would need its own separate App
-- Store Connect setup and review, so recurring giving is intentionally
-- Paystack-only for now.
--
-- Flow: `create-donation-subscription` creates a Paystack Plan + initializes
-- a transaction against it (reference = this table's id), inserting a
-- `pending` row here plus a matching `pending` row in `donations` (so the
-- first charge behaves exactly like a one-time donation as far as
-- `paystack-webhook`'s existing charge.success handling is concerned).
-- `subscription.create` (fires once Paystack turns that first payment into
-- an active subscription) fills in `paystack_subscription_code`/
-- `email_token` (matched by `plan_code`, which is unique per subscription
-- since each gets its own freshly-created plan) and flips status to
-- `active`. Every renewal charge becomes its own new row in `donations`
-- (via `subscription_id`), matched by `plan_code` since Paystack mints a
-- fresh charge reference for each one, not ours.

create table if not exists public.donation_subscriptions (
  id                        text primary key,             -- our own reference, used for the first charge
  plan_code                 text not null unique,          -- Paystack plan code — unique per subscription
  paystack_subscription_code text,                          -- filled in once subscription.create arrives
  email_token               text,                          -- needed to call POST /subscription/disable
  donor_id                  uuid references auth.users (id) on delete set null,
  donor_name                text not null default 'Anonymous',
  donor_email               text,
  message                   text,
  purpose                   text,
  amount_cents              int not null,
  currency                  text not null default 'ngn',
  interval                  text not null check (interval in ('monthly', 'annually')),
  status                    text not null default 'pending', -- pending | active | cancelled | failed
  created_at                timestamptz not null default now(),
  cancelled_at               timestamptz
);

create index if not exists donation_subscriptions_donor_id_idx
  on public.donation_subscriptions (donor_id);

alter table public.donations
  add column if not exists subscription_id text
    references public.donation_subscriptions (id) on delete set null;

create index if not exists donations_subscription_id_idx
  on public.donations (subscription_id);

-- ── Row-level security ──────────────────────────────────────────────────────

alter table public.donation_subscriptions enable row level security;

-- A donor can see their own subscriptions (to manage/cancel them); no public
-- visibility (unlike completed one-time donations) since this row also
-- carries the email_token needed to cancel — nobody else should ever see it.
drop policy if exists "donation_subscriptions_select" on public.donation_subscriptions;
create policy "donation_subscriptions_select" on public.donation_subscriptions
  for select
  to authenticated
  using (donor_id = auth.uid());

-- No insert/update/delete policy for authenticated: rows are only ever
-- written by the create-donation-subscription/paystack-webhook/
-- cancel-donation-subscription Edge Functions via the service role.
