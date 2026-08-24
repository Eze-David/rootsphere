-- Apple rejected the app (Guideline 3.1.1) for processing donations via
-- Paystack instead of In-App Purchase on iOS. Android/web keep the existing
-- Paystack flow; iOS donations now go through Apple IAP instead, verified
-- server-side via the `apple-iap-verify` Edge Function (mirrors
-- `paystack-webhook`'s "only an Edge Function can mark a donation completed"
-- guarantee — see 20260712000000_donations.sql).

alter table public.donations
  add column if not exists provider text not null default 'paystack';

alter table public.donations
  add constraint donations_provider_check
    check (provider in ('paystack', 'apple_iap'));

comment on column public.donations.provider is
  'Which payment rail processed this donation — paystack (web/Android) or apple_iap (iOS, required by App Store Guideline 3.1.1).';
