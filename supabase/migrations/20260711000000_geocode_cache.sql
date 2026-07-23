-- Rootsphere — geocoding cache for the person profile's location map.
--
-- Backs the `geocode` Edge Function, which resolves a free-text location
-- (e.g. "Kubwa, Abuja, Nigeria") to coordinates via OpenStreetMap's Nominatim
-- and caches the result here so the same place name — likely shared across
-- many people/trees — isn't re-geocoded (and re-rate-limited) every time.
-- Not tree-scoped: a place name means the same thing for everyone, so the
-- cache is shared globally. Only the Edge Function (service role) touches
-- this table; clients have no direct policy and therefore no access.

create table if not exists public.geocode_cache (
  query        text primary key,   -- normalised (lowercased, trimmed) input
  lat          double precision not null,
  lon          double precision not null,
  display_name text,
  created_at   timestamptz not null default now()
);

alter table public.geocode_cache enable row level security;
-- Intentionally no policies: locked to the service role.
