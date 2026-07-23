// Rootsphere — Phase 6 AI Research Assistant Edge Function.
//
// One endpoint, eight actions, dispatched by `action` in the request body:
//
//   Document-level (operate on a single record's text/attachment):
//     summarize              { text }                    -> { summary }
//     translate              { text, targetLanguage }     -> { translation, detectedLanguage? }
//     identifyLocations      { text }                    -> { locations: string[] }
//     transcribeHandwriting  { fileUrl }                 -> { text }
//
//   Tree/person-level (operate on a person + their tree context):
//     suggestAncestors       { person, relatives }        -> { suggestions: [...] }
//     generateTimeline       { person, events, records }   -> { entries: [...] }
//     suggestMissingRecords  { person, existingRecordTypes } -> { suggestions: [...] }
//     researchRecommendations{ person, relatives, records } -> { recommendations: [...] }
//
// Every request also carries `scope` (a stable id for cooldown purposes, e.g.
// a record id or person id) so repeated taps on the same target within the
// cooldown window are answered for free instead of re-billing Claude — see
// `checkCooldown` / `assistant_generation_log` (mirrors the `hints` function's
// cost guard).
//
// Secrets:
//   supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//   (optional) supabase secrets set CLAUDE_MODEL=claude-sonnet-4-6
//   (optional) supabase secrets set ASSISTANT_COOLDOWN_MINUTES=10
// Deploy:
//   supabase functions deploy assistant

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
const DEFAULT_COOLDOWN_MINUTES = 10;

// ── Cost guard (same pattern as the `hints` function) ─────────────────────────

async function checkCooldown(scope: string): Promise<number> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return 0; // Fail open — never block on misconfiguration.

  const cooldownMinutes = Number(
    Deno.env.get("ASSISTANT_COOLDOWN_MINUTES") ?? DEFAULT_COOLDOWN_MINUTES,
  );
  const headers = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };

  const res = await fetch(
    `${url}/rest/v1/assistant_generation_log?scope=eq.${encodeURIComponent(scope)}&select=last_requested_at`,
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

  await fetch(`${url}/rest/v1/assistant_generation_log`, {
    method: "POST",
    headers: { ...headers, Prefer: "resolution=merge-duplicates" },
    body: JSON.stringify({ scope, last_requested_at: new Date().toISOString() }),
  });
  return 0;
}

// ── Claude ─────────────────────────────────────────────────────────────────────

type ContentBlock =
  | { type: "text"; text: string }
  | { type: "image"; source: { type: "base64"; media_type: string; data: string } };

async function callClaude(
  system: string,
  content: string | ContentBlock[],
  maxTokens = 1024,
): Promise<string> {
  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) throw new Error("unconfigured");
  const model = Deno.env.get("CLAUDE_MODEL") ?? DEFAULT_MODEL;

  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    },
    body: JSON.stringify({
      model,
      max_tokens: maxTokens,
      system,
      messages: [{ role: "user", content }],
    }),
  });

  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Claude returned ${res.status}: ${detail.slice(0, 200)}`);
  }

  const data = await res.json();
  return (data.content ?? [])
    .filter((b: { type?: string }) => b.type === "text")
    .map((b: { text?: string }) => b.text ?? "")
    .join("")
    .trim();
}

/** Extracts a JSON object/array from a reply, tolerating stray prose. */
function extractJson(text: string): unknown {
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch (_) {
    const starts = [text.indexOf("{"), text.indexOf("[")].filter((i) => i >= 0);
    const start = starts.length ? Math.min(...starts) : -1;
    const end = Math.max(text.lastIndexOf("}"), text.lastIndexOf("]"));
    if (start >= 0 && end > start) {
      try {
        return JSON.parse(text.slice(start, end + 1));
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

const MEDIA_TYPES: Record<string, string> = {
  jpg: "image/jpeg",
  jpeg: "image/jpeg",
  png: "image/png",
  gif: "image/gif",
  webp: "image/webp",
};

async function fetchImageAsBase64(
  fileUrl: string,
): Promise<{ data: string; mediaType: string }> {
  const res = await fetch(fileUrl);
  if (!res.ok) throw new Error(`Could not fetch the attachment (${res.status}).`);
  const ext = fileUrl.split("?")[0].split(".").pop()?.toLowerCase() ?? "";
  const mediaType = MEDIA_TYPES[ext] ?? "image/jpeg";
  const bytes = new Uint8Array(await res.arrayBuffer());
  let binary = "";
  for (let i = 0; i < bytes.length; i++) binary += String.fromCharCode(bytes[i]);
  return { data: btoa(binary), mediaType };
}

// ── Shared types ─────────────────────────────────────────────────────────────

interface PersonSummary {
  id: string;
  name: string;
  sex?: string;
  birthYear?: number | null;
  deathYear?: number | null;
  birthPlace?: string | null;
  deathPlace?: string | null;
}

// ── Document-level actions ───────────────────────────────────────────────────

async function summarize(text: string): Promise<{ summary: string }> {
  const summary = await callClaude(
    "You are a professional genealogist. Summarise the given document in 2-4 " +
      "plain sentences, focused on genealogically relevant facts (names, " +
      "dates, places, relationships, events). Return prose only, no markdown, " +
      "no preamble.",
    text.slice(0, 8000),
    400,
  );
  return { summary };
}

async function translate(
  text: string,
  targetLanguage: string,
): Promise<{ translation: string }> {
  const translation = await callClaude(
    `You are a professional translator. Translate the given document text into ` +
      `${targetLanguage}. Preserve names, dates and places exactly. Return only ` +
      `the translation, no preamble or commentary.`,
    text.slice(0, 8000),
    2048,
  );
  return { translation };
}

async function identifyLocations(text: string): Promise<{ locations: string[] }> {
  const raw = await callClaude(
    "You are a professional genealogist. Read the document text and list every " +
      "place name it mentions (towns, counties, states, countries, churches, " +
      "cemeteries, etc.), most specific first. Return ONLY a JSON array of " +
      'strings, e.g. ["Enugu, Nigeria", "St. Mary\'s Church"]. No prose, no ' +
      "markdown. Return [] if none are found.",
    text.slice(0, 8000),
    500,
  );
  const parsed = extractJson(raw);
  const locations = Array.isArray(parsed)
    ? parsed.map((v) => String(v)).filter((v) => v.trim().length > 0)
    : [];
  return { locations };
}

async function transcribeHandwriting(fileUrl: string): Promise<{ text: string }> {
  const { data, mediaType } = await fetchImageAsBase64(fileUrl);
  const text = await callClaude(
    "You are an expert archivist transcribing handwritten historical documents. " +
      "Transcribe all legible text exactly as written, preserving line breaks. " +
      "If a word is illegible, write [illegible]. Return only the transcription, " +
      "no preamble or commentary.",
    [
      { type: "image", source: { type: "base64", media_type: mediaType, data } },
      { type: "text", text: "Transcribe this document." },
    ],
    2048,
  );
  return { text };
}

// ── Tree/person-level actions ────────────────────────────────────────────────

async function suggestAncestors(
  person: PersonSummary,
  relatives: PersonSummary[],
): Promise<{ suggestions: unknown[] }> {
  const raw = await callClaude(
    "You are a professional genealogist. Given a person and their already-known " +
      "relatives, suggest likely ancestors or relatives that appear to be " +
      "missing from the tree (e.g. a father implied by a surname/patronym, a " +
      "second spouse implied by a large age gap between children). Return ONLY " +
      "a JSON array of objects: " +
      '{ "relation": string, "reasoning": string, "confidence": integer 0-100 }. ' +
      "Be conservative — only suggest what the given data actually implies. " +
      "Return [] if there is nothing to suggest. At most 6 suggestions.",
    JSON.stringify({ person, relatives }),
    800,
  );
  const parsed = extractJson(raw);
  return { suggestions: Array.isArray(parsed) ? parsed : [] };
}

async function generateTimeline(
  person: PersonSummary,
  events: unknown[],
  records: unknown[],
): Promise<{ entries: unknown[] }> {
  const raw = await callClaude(
    "You are a professional genealogist writing a biographical timeline. Given " +
      "a person's structured life events and linked records, produce a " +
      "chronological narrative timeline. Return ONLY a JSON array of objects: " +
      '{ "year": integer|null, "title": string, "description": string }, ' +
      "ordered chronologically, weaving events and records into a coherent " +
      "narrative (not just restating the input). At most 15 entries.",
    JSON.stringify({ person, events, records }),
    1200,
  );
  const parsed = extractJson(raw);
  return { entries: Array.isArray(parsed) ? parsed : [] };
}

async function suggestMissingRecords(
  person: PersonSummary,
  existingRecordTypes: string[],
): Promise<{ suggestions: unknown[] }> {
  const raw = await callClaude(
    "You are a professional genealogist. Given a person and the record types " +
      "already on file for them, suggest which additional record types would " +
      "most likely exist and be worth searching for (from: birth, marriage, " +
      "death, census, military, immigration, baptism, photo, newspaper, " +
      "community, cemetery, school, exam, other). Return ONLY a JSON array of " +
      'objects: { "type": string, "reasoning": string, "confidence": integer 0-100 }. ' +
      "Don't repeat types already on file. At most 6 suggestions.",
    JSON.stringify({ person, existingRecordTypes }),
    600,
  );
  const parsed = extractJson(raw);
  return { suggestions: Array.isArray(parsed) ? parsed : [] };
}

async function researchRecommendations(
  person: PersonSummary,
  relatives: PersonSummary[],
  records: unknown[],
): Promise<{ recommendations: unknown[] }> {
  const raw = await callClaude(
    "You are a professional genealogy research advisor. Given a person, their " +
      "known relatives and their records, recommend concrete next research " +
      "steps (e.g. specific archives, record types, or comparisons to try). " +
      "Return ONLY a JSON array of objects: " +
      '{ "title": string (<= 60 chars), "description": string (1-2 sentences) }. ' +
      "At most 6 recommendations, ordered by usefulness.",
    JSON.stringify({ person, relatives, records }),
    900,
  );
  const parsed = extractJson(raw);
  return { recommendations: Array.isArray(parsed) ? parsed : [] };
}

// ── Request handling ─────────────────────────────────────────────────────────

interface RequestBody {
  action?: string;
  scope?: string;
  text?: string;
  targetLanguage?: string;
  fileUrl?: string;
  person?: PersonSummary;
  relatives?: PersonSummary[];
  events?: unknown[];
  records?: unknown[];
  existingRecordTypes?: string[];
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: RequestBody;
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const action = body.action ?? "";
  const scope = body.scope?.trim() || action;

  const waitMinutes = await checkCooldown(`${action}:${scope}`);
  if (waitMinutes > 0) {
    return json({
      available: false,
      message: `You can request this again in ${waitMinutes} minute${waitMinutes === 1 ? "" : "s"}.`,
    });
  }

  try {
    switch (action) {
      case "summarize":
        return json({ available: true, ...(await summarize(body.text ?? "")) });
      case "translate":
        return json({
          available: true,
          ...(await translate(body.text ?? "", body.targetLanguage ?? "English")),
        });
      case "identifyLocations":
        return json({
          available: true,
          ...(await identifyLocations(body.text ?? "")),
        });
      case "transcribeHandwriting":
        if (!body.fileUrl) return json({ available: false, message: "No attachment." });
        return json({
          available: true,
          ...(await transcribeHandwriting(body.fileUrl)),
        });
      case "suggestAncestors":
        if (!body.person) return json({ available: false, message: "No person given." });
        return json({
          available: true,
          ...(await suggestAncestors(body.person, body.relatives ?? [])),
        });
      case "generateTimeline":
        if (!body.person) return json({ available: false, message: "No person given." });
        return json({
          available: true,
          ...(await generateTimeline(body.person, body.events ?? [], body.records ?? [])),
        });
      case "suggestMissingRecords":
        if (!body.person) return json({ available: false, message: "No person given." });
        return json({
          available: true,
          ...(await suggestMissingRecords(body.person, body.existingRecordTypes ?? [])),
        });
      case "researchRecommendations":
        if (!body.person) return json({ available: false, message: "No person given." });
        return json({
          available: true,
          ...(await researchRecommendations(
            body.person,
            body.relatives ?? [],
            body.records ?? [],
          )),
        });
      default:
        return json({ error: `Unknown action: ${action}` }, 400);
    }
  } catch (err) {
    const message = err instanceof Error ? err.message : "Assistant request failed";
    if (message === "unconfigured") {
      return json({
        available: false,
        message: "AI Assistant is not configured (ANTHROPIC_API_KEY unset).",
      });
    }
    return json({ available: false, message }, 200);
  }
});
