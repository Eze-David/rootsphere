// Rootsphere — Historical records search Edge Function (multi-provider).
//
// The Flutter client sends { type, firstName, lastName, place, year } and gets
// back a merged, normalised { records: [...] } list, each tagged with its
// `source`. Credentials never live on the client (brief: "keys never on
// client").
//
// Providers (each runs only when usable; failures are isolated):
//   • FamilySearch        — needs FAMILYSEARCH_ACCESS_TOKEN
//   • WikiTree            — free, no key (searchPerson)
//   • Wikidata            — free, no key
//   • Chronicling America — free, no key (US historical newspapers)
//   • DPLA                — needs DPLA_API_KEY (free to request)
//   • Europeana           — needs EUROPEANA_API_KEY (free to request)
//   • NARA (US Archives)  — needs NARA_API_KEY (Catalog API v2)
//
// Optional secrets:
//   FAMILYSEARCH_ACCESS_TOKEN, FAMILYSEARCH_BASE_URL,
//   DPLA_API_KEY, EUROPEANA_API_KEY, NARA_API_KEY
//
// Deploy:  supabase functions deploy records-search

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

interface SearchBody {
  type?: string;
  firstName?: string;
  lastName?: string;
  place?: string;
  year?: number | null;
}

interface Normalized {
  id: string;
  name: string;
  type: string;
  eventDate: string | null;
  eventPlace: string | null;
  collection: string | null;
  sourceUrl: string | null;
  source: string;
}

function fullName(b: SearchBody): string {
  return [b.firstName?.trim(), b.lastName?.trim()]
    .filter((s) => s && s.length > 0)
    .join(" ")
    .trim();
}

// ── FamilySearch ──────────────────────────────────────────────────────────────

function fsEventPrefix(type: string): "birth" | "death" | "marriage" | "any" {
  switch (type) {
    case "birth":
    case "baptism":
      return "birth";
    case "death":
      return "death";
    case "marriage":
      return "marriage";
    default:
      return "any";
  }
}

async function searchFamilySearch(b: SearchBody): Promise<Normalized[]> {
  const token = Deno.env.get("FAMILYSEARCH_ACCESS_TOKEN");
  if (!token) return [];
  const base = Deno.env.get("FAMILYSEARCH_BASE_URL") ??
    "https://api.familysearch.org";

  const q: string[] = [];
  if (b.firstName?.trim()) q.push(`givenName:"${b.firstName.trim()}"`);
  if (b.lastName?.trim()) q.push(`surname:"${b.lastName.trim()}"`);
  const prefix = fsEventPrefix(b.type ?? "any");
  const placeField = prefix === "any" ? "anyPlace" : `${prefix}LikePlace`;
  const dateField = prefix === "any" ? "anyDate" : `${prefix}LikeDate`;
  if (b.place?.trim()) q.push(`${placeField}:"${b.place.trim()}"`);
  if (b.year != null) q.push(`${dateField}:${b.year}`);

  const params = new URLSearchParams({ q: q.join(" "), count: "20" });
  const res = await fetch(`${base}/platform/records/search?${params}`, {
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/x-gedcomx-atom+json",
    },
  });
  if (res.status === 204 || !res.ok) return [];

  const data = await res.json();
  const entries = (data.entries as Array<Record<string, unknown>>) ?? [];
  return entries.map((entry) => {
    const gedcomx =
      (entry.content as { gedcomx?: Record<string, unknown> })?.gedcomx ?? {};
    const persons = (gedcomx.persons as Array<Record<string, unknown>>) ?? [];
    const person = persons[0] ?? {};
    const names = (person.names as Array<Record<string, unknown>>) ?? [];
    const name =
      (entry.title as string) ??
      ((names[0]?.nameForms as Array<{ fullText?: string }>)?.[0]?.fullText) ??
      "Unknown";
    const facts = (person.facts as Array<Record<string, unknown>>) ?? [];
    const fact = facts[0] ?? {};
    const sources =
      (gedcomx.sourceDescriptions as Array<Record<string, unknown>>) ?? [];
    const links = entry.links as Record<string, { href?: string }> | undefined;
    return {
      id: (entry.id as string) ?? crypto.randomUUID(),
      name,
      type: b.type ?? "other",
      eventDate: (fact.date as { original?: string })?.original ?? null,
      eventPlace: (fact.place as { original?: string })?.original ?? null,
      collection:
        ((sources[0]?.titles as Array<{ value?: string }>)?.[0]?.value) ?? null,
      sourceUrl: links?.self?.href ?? (entry.id as string) ?? null,
      source: "FamilySearch",
    };
  });
}

// ── Wikidata (free, no key) ───────────────────────────────────────────────────

async function searchWikidata(b: SearchBody): Promise<Normalized[]> {
  const name = fullName(b);
  if (!name) return [];
  const params = new URLSearchParams({
    action: "wbsearchentities",
    search: name,
    language: "en",
    format: "json",
    type: "item",
    limit: "8",
    origin: "*",
  });
  const res = await fetch(`https://www.wikidata.org/w/api.php?${params}`, {
    headers: { "User-Agent": "Rootsphere/1.0 (genealogy app)" },
  });
  if (!res.ok) return [];
  const data = await res.json();
  const items = (data.search as Array<Record<string, unknown>>) ?? [];
  return items.map((it) => ({
    id: (it.id as string) ?? crypto.randomUUID(),
    name: (it.label as string) ?? name,
    type: b.type ?? "other",
    eventDate: null,
    eventPlace: null,
    collection: (it.description as string) ?? "Wikidata",
    sourceUrl: (it.concepturi as string) ??
      `https://www.wikidata.org/wiki/${it.id}`,
    source: "Wikidata",
  }));
}

// ── Chronicling America (free, no key) ────────────────────────────────────────

async function searchChroniclingAmerica(b: SearchBody): Promise<Normalized[]> {
  const name = fullName(b);
  if (!name) return [];
  const params = new URLSearchParams({
    andtext: name,
    format: "json",
    rows: "8",
  });
  const res = await fetch(
    `https://chroniclingamerica.loc.gov/search/pages/results/?${params}`,
  );
  if (!res.ok) return [];
  const data = await res.json();
  const items = (data.items as Array<Record<string, unknown>>) ?? [];
  return items.map((it) => {
    const raw = (it.date as string) ?? ""; // yyyymmdd
    const date = raw.length === 8
      ? `${raw.slice(0, 4)}-${raw.slice(4, 6)}-${raw.slice(6, 8)}`
      : null;
    const id = (it.id as string) ?? crypto.randomUUID();
    return {
      id,
      name: (it.title as string) ?? "Newspaper page",
      type: "newspaper",
      eventDate: date,
      eventPlace: ((it.place_of_publication as string) ?? null),
      collection: "Chronicling America",
      sourceUrl: id.startsWith("/")
        ? `https://chroniclingamerica.loc.gov${id}`
        : id,
      source: "Chronicling America",
    };
  });
}

// ── WikiTree (free, no key) ───────────────────────────────────────────────────

/** Cleans a WikiTree date ("1853-00-00" -> "1853", "1857-04-00" -> "1857-04"). */
function cleanWikiTreeDate(raw: unknown): string | null {
  if (typeof raw !== "string" || raw.length < 4) return null;
  const parts = raw.split("-");
  const kept: string[] = [];
  for (const p of parts) {
    if (p === "00" || p === "0000") break;
    kept.push(p);
  }
  return kept.length > 0 ? kept.join("-") : null;
}

async function searchWikiTree(b: SearchBody): Promise<Normalized[]> {
  if (!fullName(b)) return [];
  const params = new URLSearchParams({
    action: "searchPerson",
    fields:
      "Id,Name,FirstName,LastNameAtBirth,BirthDate,DeathDate,BirthLocation,DeathLocation",
    limit: "10",
  });
  if (b.firstName?.trim()) params.set("FirstName", b.firstName.trim());
  if (b.lastName?.trim()) params.set("LastName", b.lastName.trim());
  if (b.place?.trim()) params.set("BirthLocation", b.place.trim());
  if (b.year != null) {
    params.set("BirthDate", `${b.year}-00-00`);
    params.set("dateSpread", "5");
  }

  const res = await fetch(`https://api.wikitree.com/api.php?${params}`, {
    headers: { "User-Agent": "Rootsphere/1.0 (genealogy app)" },
  });
  if (!res.ok) return [];

  const data = await res.json();
  const block = Array.isArray(data) ? data[0] : data;
  const matches = (block?.matches as Array<Record<string, unknown>>) ?? [];

  return matches
    .filter((m) => m.FirstName || m.LastNameAtBirth)
    .map((m) => {
      const name = [m.FirstName, m.LastNameAtBirth]
        .filter((s) => typeof s === "string" && s.length > 0)
        .join(" ")
        .trim();
      const birth = cleanWikiTreeDate(m.BirthDate);
      const death = cleanWikiTreeDate(m.DeathDate);
      const life = [birth, death].filter((x) => x).join(" – ");
      const wikiId = m.Name as string | undefined;
      return {
        id: `wt_${m.Id ?? crypto.randomUUID()}`,
        name: name || "Unknown",
        type: b.type ?? "other",
        eventDate: life || null,
        eventPlace: (m.BirthLocation as string) ??
          (m.DeathLocation as string) ?? null,
        collection: "WikiTree",
        sourceUrl: wikiId ? `https://www.wikitree.com/wiki/${wikiId}` : null,
        source: "WikiTree",
      };
    });
}

// ── DPLA (needs free key) ─────────────────────────────────────────────────────

async function searchDpla(b: SearchBody): Promise<Normalized[]> {
  const key = Deno.env.get("DPLA_API_KEY");
  const name = fullName(b);
  if (!key || !name) return [];
  const params = new URLSearchParams({
    q: name,
    page_size: "8",
    api_key: key,
  });
  const res = await fetch(`https://api.dp.la/v2/items?${params}`);
  if (!res.ok) return [];
  const data = await res.json();
  const docs = (data.docs as Array<Record<string, unknown>>) ?? [];
  return docs.map((d) => {
    const src = d.sourceResource as Record<string, unknown> ?? {};
    const title = Array.isArray(src.title)
      ? (src.title as string[])[0]
      : (src.title as string) ?? "Record";
    return {
      id: (d.id as string) ?? crypto.randomUUID(),
      name: title,
      type: b.type ?? "other",
      eventDate: (Array.isArray(src.date) ? null : (src.date as { displayDate?: string })?.displayDate) ?? null,
      eventPlace: null,
      collection: (d.provider as { name?: string })?.name ?? "DPLA",
      sourceUrl: (d.isShownAt as string) ?? null,
      source: "DPLA",
    };
  });
}

// ── Europeana (needs free key) ────────────────────────────────────────────────

async function searchEuropeana(b: SearchBody): Promise<Normalized[]> {
  const key = Deno.env.get("EUROPEANA_API_KEY");
  const name = fullName(b);
  if (!key || !name) return [];
  const params = new URLSearchParams({
    wskey: key,
    query: name,
    rows: "8",
  });
  const res = await fetch(`https://api.europeana.eu/record/v2/search.json?${params}`);
  if (!res.ok) return [];
  const data = await res.json();
  const items = (data.items as Array<Record<string, unknown>>) ?? [];
  return items.map((it) => {
    const title = Array.isArray(it.title)
      ? (it.title as string[])[0]
      : (it.title as string) ?? "Record";
    const provider = Array.isArray(it.dataProvider)
      ? (it.dataProvider as string[])[0]
      : (it.dataProvider as string) ?? "Europeana";
    return {
      id: (it.id as string) ?? crypto.randomUUID(),
      name: title,
      type: b.type ?? "other",
      eventDate: null,
      eventPlace: null,
      collection: provider,
      sourceUrl: (it.guid as string) ?? null,
      source: "Europeana",
    };
  });
}

// ── NARA (US National Archives Catalog v2, needs key) ─────────────────────────

async function searchNara(b: SearchBody): Promise<Normalized[]> {
  const key = Deno.env.get("NARA_API_KEY");
  const name = fullName(b);
  if (!key || !name) return [];
  const params = new URLSearchParams({ q: name, limit: "8" });
  const res = await fetch(
    `https://catalog.archives.gov/api/v2/records/search?${params}`,
    { headers: { "x-api-key": key } },
  );
  if (!res.ok) return [];
  const data = await res.json();
  const hits =
    ((data.body as { hits?: { hits?: Array<Record<string, unknown>> } })?.hits
      ?.hits) ?? [];
  return hits.map((h) => {
    const rec = (h._source as { record?: Record<string, unknown> })?.record ??
      {};
    return {
      id: (h._id as string) ?? crypto.randomUUID(),
      name: (rec.title as string) ?? "Archival record",
      type: b.type ?? "other",
      eventDate: null,
      eventPlace: null,
      collection: "US National Archives",
      sourceUrl: (rec.id as string)
        ? `https://catalog.archives.gov/id/${rec.id}`
        : null,
      source: "NARA",
    };
  });
}

// ── Orchestrator ──────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: SearchBody;
  try {
    body = (await req.json()) as SearchBody;
  } catch {
    return json({ error: "Invalid JSON body." }, 400);
  }

  const providers = [
    searchFamilySearch,
    searchWikiTree,
    searchWikidata,
    searchChroniclingAmerica,
    searchDpla,
    searchEuropeana,
    searchNara,
  ];

  // Run every provider in parallel; a failing provider yields no results
  // instead of failing the whole request.
  const settled = await Promise.allSettled(providers.map((p) => p(body)));
  const records: Normalized[] = [];
  for (const r of settled) {
    if (r.status === "fulfilled") records.push(...r.value);
  }

  return json({ records });
});
