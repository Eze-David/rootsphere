-- Apple side of recurring donations: auto-renewable subscriptions (2 fixed
-- products — Monthly and Annual — created in App Store Connect under a
-- subscription group, distinct from the 5 one-time consumable tiers).
--
-- Unlike Paystack, Apple never calls us back on renewal — nothing here is
-- pushed. Instead `apple-subscription-poll` (scheduled via pg_cron) queries
-- the App Store Server API once a day for every active Apple subscription
-- and records any new renewal charge, matched by
-- `apple_original_transaction_id` (Apple's stable per-subscription id,
-- constant across every renewal) with `apple_last_transaction_id` tracking
-- the most recent charge already recorded so renewals aren't double-counted.

alter table public.donation_subscriptions
  alter column plan_code drop not null;

alter table public.donation_subscriptions
  add column if not exists provider text not null default 'paystack'
    check (provider in ('paystack', 'apple_iap')),
  add column if not exists apple_original_transaction_id text unique,
  add column if not exists apple_last_transaction_id text,
  add column if not exists apple_product_id text;

create index if not exists donation_subscriptions_provider_idx
  on public.donation_subscriptions (provider);

comment on column public.donation_subscriptions.apple_original_transaction_id is
  'Apple''s stable subscription identifier — constant across every renewal, used to query the App Store Server API.';
comment on column public.donation_subscriptions.apple_last_transaction_id is
  'The most recent renewal transaction already recorded as a donations row — lets the poll skip renewals it has already seen.';
