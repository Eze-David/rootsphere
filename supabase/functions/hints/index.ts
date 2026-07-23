// Rootsphere — Phase 4 Hints & AI Edge Function.
//
// The Flutter client sends a compact tree summary
//   { treeId, people: [...], records: [...] }
// and receives confidence-ranked suggestions
//   { hints: [ { type, title, description, confidence, personId, ... } ] }.
//
// Powered by Claude (Anthropic Messages API). The API key lives ONLY here
// (brief: "keys never on client"). When ANTHROPIC_API_KEY is unset the function
// returns { available: false } so the client degrades gracefully to its local
// heuristic isolate.
//
// Secrets:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   (optional) supabase secrets set CLAUDE_MODEL=claude-sonnet-4-6
//   (optional) supabase secrets set HINTS_COOLDOWN_MINUTES=15
// Deploy:
//   supabase functions deploy hints
//
// Cost guard: Claude is billed per call, so repeated taps on "Generate hints"
// for the same tree are throttled server-side (see `checkCooldown` /
// `hint_generation_log`) rather than trusting the client not to spam the
// button — `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` are auto-injected into
// every Edge Function's environment.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const DEFAULT_MODEL = "claude-sonnet-4-6";
const DEFAULT_COOLDOWN_MINUTES = 15;

/**
 * Checks (and, if the cooldown has elapsed, immediately stamps) the last time
 * a tree asked for AI hints. Stamping happens *before* the Claude call so two
 * rapid taps race the DB, not the API — only one gets through per window.
 *
 * Returns the number of minutes the caller must still wait, or `0` when the
 * call is allowed to proceed.
 */
async function checkCooldown(treeId: string): Promise<number> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return 0; // Fail open — never block on misconfiguration.

  const cooldownMinutes = Number(
    Deno.env.get("HINTS_COOLDOWN_MINUTES") ?? DEFAULT_COOLDOWN_MINUTES,
  );
  const headers = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };

  const res = await fetch(
    `${url}/rest/v1/hint_generation_log?tree_id=eq.${encodeURIComponent(treeId)}&select=last_requested_at`,
    { headers },
  );
  if (res.ok) {
    const rows = await res.json();
    const lastRequestedAt = rows[0]?.last_requested_at as string | undefined;
    if (lastRequestedAt) {
      const elapsedMs = Date.now() - new Date(lastRequestedAt).getTime();
      const remaining = cooldownMinutes - elapsedMs / 60_000;
      if (remaining > 0) return Math.ceil(remaining);
    }
  }

  // Cooldown has elapsed (or there's no prior record) — stamp now and proceed.
  await fetch(`${url}/rest/v1/hint_generation_log`, {
    method: "POST",
    headers: { ...headers, Prefer: "resolution=merge-duplicates" },
    body: JSON.stringify({
      tree_id: treeId,
      last_requested_at: new Date().toISOString(),
    }),
  });
  return 0;
}

interface PersonSummary {
  id: string;
  name: string;
  sex?: string;
  birthYear?: number | null;
  deathYear?: number | null;
  birthPlace?: string | null;
  deathPlace?: string | null;
  parentIds?: string[];
  spouseIds?: string[];
}

interface RecordSummary {
  id: string;
  type: string;
  title: string;
  year?: number | null;
  personIds?: string[];
}

const SYSTEM_PROMPT = `You are a professional genealogist assisting with a family tree.
Analyse the provided people and records and produce actionable, confidence-ranked hints.

Return ONLY a JSON array (no prose, no markdown) of hint objects. Each object:
{
  "type": "missingData" | "duplicate" | "recordMatch" | "relationship",
  "title": short imperative title (<= 60 chars),
  "description": one or two sentences explaining the suggestion and your reasoning,
  "confidence": integer 0-100,
  "personId": id of the primary person (required),
  "relatedPersonId": id of a second person (duplicates / relationships only),
  "recordId": id of a record (recordMatch only),
  "field": one of "birthDate","deathDate","birthPlace","deathPlace","religion" (missingData only),
  "suggestedValue": a concrete value to apply when you can confidently infer one (optional),
  "relation": "parent" | "child" | "spouse" (relationship only; how relatedPersonId relates to personId)
}

Rules:
- Only reference ids that appear in the input.
- Prefer high-value, non-obvious suggestions. Avoid duplicating the same hint.
- Be conservative with confidence; reserve 85+ for strong evidence.
- Return at most 12 hints. If nothing useful, return [].`;

async function generateHints(
  people: PersonSummary[],
  records: RecordSummary[],
): Promise<unknown[]> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    throw new Error("unconfigured");
  }
  const model = Deno.env.get("CLAUDE_MODEL") ?? DEFAULT_MODEL;

  const userContent =
    `People (${people.length}):\n${JSON.stringify(people)}\n\n` +
    `Records (${records.length}):\n${JSON.stringify(records)}`;

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: 2048,
      system: SYSTEM_PROMPT,
      messages: [{ role: "user", content: userContent }],
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Claude returned ${res.status}: ${detail.slice(0, 200)}`);
  }

  const data = await res.json();
  const text: string = (data.content ?? [])
    .filter((b: { type?: string }) => b.type === "text")
    .map((b: { text?: string }) => b.text ?? "")
    .join("")
    .trim();

  return parseHintArray(text);
}

/** Extracts the JSON array from the model's reply, tolerating stray prose. */
function parseHintArray(text: string): unknown[] {
  if (!text) return [];
  try {
    const parsed = JSON.parse(text);
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    // Fallback: grab the first [...] block.
    const start = text.indexOf("[");
    const end = text.lastIndexOf("]");
    if (start >= 0 && end > start) {
      try {
        const parsed = JSON.parse(text.slice(start, end + 1));
        return Array.isArray(parsed) ? parsed : [];
      } catch (_) {
        return [];
      }
    }
    return [];
  }
}

/** Clamps/normalises a model hint to the client's expected shape. */
function sanitize(raw: unknown): Record<string, unknown> | null {
  if (typeof raw !== "object" || raw === null) return null;
  const h = raw as Record<string, unknown>;
  const type = String(h.type ?? "");
  if (!["missingData", "duplicate", "recordMatch", "relationship"].includes(type)) {
    return null;
  }
  const personId = h.personId ? String(h.personId) : null;
  if (!personId) return null;

  let confidence = Number(h.confidence ?? 50);
  if (!Number.isFinite(confidence)) confidence = 50;
  confidence = Math.max(0, Math.min(100, Math.round(confidence)));

  return {
    type,
    title: String(h.title ?? "").slice(0, 120),
    description: String(h.description ?? "").slice(0, 600),
    confidence,
    personId,
    relatedPersonId: h.relatedPersonId ? String(h.relatedPersonId) : null,
    recordId: h.recordId ? String(h.recordId) : null,
    field: h.field ? String(h.field) : null,
    suggestedValue: h.suggestedValue ? String(h.suggestedValue) : null,
    relation: h.relation ? String(h.relation) : null,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: { treeId?: string; people?: PersonSummary[]; records?: RecordSummary[] };
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const treeId = typeof body.treeId === "string" ? body.treeId : "";
  const people = Array.isArray(body.people) ? body.people : [];
  const records = Array.isArray(body.records) ? body.records : [];

  if (treeId) {
    const waitMinutes = await checkCooldown(treeId);
    if (waitMinutes > 0) {
      return json({
        available: false,
        message: `Hints were generated recently. Try again in ${waitMinutes} minute${waitMinutes === 1 ? "" : "s"}.`,
      });
    }
  }

  try {
    const raw = await generateHints(people, records);
    const hints = raw
      .map(sanitize)
      .filter((h): h is Record<string, unknown> => h !== null);
    return json({ hints });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Hint generation failed";
    if (message === "unconfigured") {
      return json({
        available: false,
        message: "AI hints are not configured (ANTHROPIC_API_KEY unset).",
      });
    }
    return json({ available: false, message }, 200);
  }
});
