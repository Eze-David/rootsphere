-- Rootsphere — Phase 6: AI Research Assistant.
--
-- Backs the `assistant` Edge Function, which covers eight Claude-powered
-- capabilities: summarize / translate / identify locations / transcribe
-- handwriting (document-level, results cached on the record) and suggest
-- ancestors / generate timeline / suggest missing records / research
-- recommendations (tree/person-level, ephemeral — not persisted).
-- Run AFTER 20260709000000_hint_generation_throttle.sql.

-- ── Cached document-level AI results ──────────────────────────────────────────

alter table public.records
  add column if not exists ai_summary          text,
  add column if not exists ai_translation      text,
  add column if not exists ai_translation_lang text,
  add column if not exists ai_locations        text[] not null default '{}';

-- ── Generic cost-guard log ────────────────────────────────────────────────────
-- One row per (action, target) pair, e.g. "summarize:record123" or
-- "generateTimeline:person456". Same throttle pattern as
-- hint_generation_log — only the Edge Function (service role) touches this,
-- so it needs no client-facing RLS policy.

create table if not exists public.assistant_generation_log (
  scope              text primary key,
  last_requested_at  timestamptz not null default now()
);

alter table public.assistant_generation_log enable row level security;
-- Intentionally no policies: locked to the service role.
