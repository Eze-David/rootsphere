// Rootsphere — Location Map geocoding Edge Function.
//
// Resolves a free-text place name (e.g. "Kubwa, Abuja, Nigeria") to
// coordinates so the person profile's Map section can plot a pin. The
// Flutter client sends { query } and gets back
//   { available: true, lat, lon, displayName }
// or { available: false, message } when nothing matches. Sending
// { query, suggest: true, country? } instead returns type-ahead
// { suggestions: [{ name, detail }] }.
//
// Secrets (optional; suggestions fall back to Photon without it):
//   supabase secrets set GOOGLE_PLACES_API_KEY=...
//
// Providers: Photon (https://photon.komoot.io), then OpenStreetMap Nominatim
// (https://nominatim.org) — both free OpenStreetMap-based services with no API
// key, rate-limited, so send a real identifying User-Agent. Results are cached in `geocode_cache` (keyed by the
// normalised query) so the same place name — likely shared across many
// people/trees — is only ever geocoded once.
//
// Deploy:
//   supabase functions deploy geocode

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

interface GeocodeResult {
  lat: number;
  lon: number;
  displayName: string | null;
}

function normalise(query: string): string {
  return query.trim().toLowerCase().replace(/\s+/g, " ");
}

async function readCache(key: string): Promise<GeocodeResult | null> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return null;

  const res = await fetch(
    `${url}/rest/v1/geocode_cache?query=eq.${encodeURIComponent(key)}&select=lat,lon,display_name`,
    { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } },
  );
  if (!res.ok) return null;
  const rows = await res.json();
  const row = rows[0];
  if (!row) return null;
  return { lat: row.lat, lon: row.lon, displayName: row.display_name ?? null };
}

async function writeCache(key: string, result: GeocodeResult): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return;

  await fetch(`${url}/rest/v1/geocode_cache`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      Prefer: "resolution=merge-duplicates",
    },
    body: JSON.stringify({
      query: key,
      lat: result.lat,
      lon: result.lon,
      display_name: result.displayName,
    }),
  });
}

const USER_AGENT = "Rootsphere/1.0 (family tree app; geocode Edge Function)";

async function geocodeWithPhoton(query: string): Promise<GeocodeResult | null> {
  const res = await fetch(
    `https://photon.komoot.io/api/?limit=1&q=${encodeURIComponent(query)}`,
    { headers: { "User-Agent": USER_AGENT } },
  );
  if (!res.ok) throw new Error(`Photon returned ${res.status}`);
  const data = await res.json();
  const first = data.features?.[0];
  const coordinates = first?.geometry?.coordinates;
  if (!Array.isArray(coordinates) || coordinates.length < 2) return null;
  const p = first.properties ?? {};
  const name = [p.name, p.state, p.country].filter(Boolean).join(", ");
  return {
    // GeoJSON order is [longitude, latitude].
    lat: Number(coordinates[1]),
    lon: Number(coordinates[0]),
    displayName: name || null,
  };
}

async function geocodeWithNominatim(query: string): Promise<GeocodeResult | null> {
  const res = await fetch(
    `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&q=${encodeURIComponent(query)}`,
    // Nominatim's usage policy requires a real identifying User-Agent.
    { headers: { "User-Agent": USER_AGENT } },
  );
  if (!res.ok) throw new Error(`Nominatim returned ${res.status}`);
  const results = await res.json();
  const first = results[0];
  if (!first) return null;
  return {
    lat: Number(first.lat),
    lon: Number(first.lon),
    displayName: typeof first.display_name === "string" ? first.display_name : null,
  };
}

// Photon first: Nominatim answers Supabase's servers with 403, so it's only a
// backstop. One provider failing moves on to the next, and an error is only
// reported when no provider gave a usable answer.
async function lookup(query: string): Promise<GeocodeResult | null> {
  let failure: unknown = null;
  let answered = false;
  for (const provider of [geocodeWithPhoton, geocodeWithNominatim]) {
    try {
      const result = await provider(query);
      if (result) return result;
      answered = true;
    } catch (err) {
      failure = err;
    }
  }
  if (!answered && failure) throw failure;
  return null;
}

// Addresses run most to least specific ("makurdi, EUNEB"), so a mistyped
// trailing part shouldn't lose the pin: retry without it, keeping the town.
async function geocode(query: string): Promise<GeocodeResult | null> {
  const parts = query.split(",").map((p) => p.trim()).filter(Boolean);
  for (let count = parts.length; count > 0; count--) {
    const result = await lookup(parts.slice(0, count).join(", "));
    if (result) return result;
  }
  return null;
}

// ISO codes for the countries in the app's dropdown (african_locations.dart),
// which Google needs to limit suggestions to one country.
const COUNTRY_CODES: Record<string, string> = {
  "algeria": "dz", "angola": "ao", "benin": "bj", "botswana": "bw",
  "burkina faso": "bf", "burundi": "bi", "cabo verde": "cv", "cameroon": "cm",
  "central african republic": "cf", "chad": "td", "comoros": "km",
  "congo (republic of the)": "cg", "democratic republic of the congo": "cd",
  "djibouti": "dj", "egypt": "eg", "equatorial guinea": "gq", "eritrea": "er",
  "eswatini": "sz", "ethiopia": "et", "gabon": "ga", "gambia": "gm",
  "ghana": "gh", "guinea": "gn", "guinea-bissau": "gw", "ivory coast": "ci",
  "kenya": "ke", "lesotho": "ls", "liberia": "lr", "libya": "ly",
  "madagascar": "mg", "malawi": "mw", "mali": "ml", "mauritania": "mr",
  "mauritius": "mu", "morocco": "ma", "mozambique": "mz", "namibia": "na",
  "niger": "ne", "nigeria": "ng", "rwanda": "rw",
  "sao tome and principe": "st", "senegal": "sn", "seychelles": "sc",
  "sierra leone": "sl", "somalia": "so", "south africa": "za",
  "south sudan": "ss", "sudan": "sd", "tanzania": "tz", "togo": "tg",
  "tunisia": "tn", "uganda": "ug", "zambia": "zm", "zimbabwe": "zw",
};

// Google Places Autocomplete (New). Knows estates and matches partial words
// far better than OpenStreetMap data, but is billed per request, so the client
// only calls this after a pause in typing.
async function suggestWithGoogle(
  query: string,
  country: string,
  apiKey: string,
): Promise<Suggestion[]> {
  const code = COUNTRY_CODES[country.trim().toLowerCase()];
  const res = await fetch("https://places.googleapis.com/v1/places:autocomplete", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Goog-Api-Key": apiKey },
    body: JSON.stringify({
      input: query,
      ...(code ? { includedRegionCodes: [code] } : {}),
    }),
  });
  if (!res.ok) throw new Error(`Google Places returned ${res.status}`);
  const data = await res.json();
  // deno-lint-ignore no-explicit-any
  return (data.suggestions ?? []).flatMap((s: any) => {
    const format = s.placePrediction?.structuredFormat;
    const name = format?.mainText?.text;
    if (typeof name !== "string" || !name.trim()) return [];
    return [{ name, detail: format?.secondaryText?.text ?? "" }];
  });
}

// Places first, then named buildings/businesses, so towns and districts lead.
const AREA_TYPES = new Set(["city", "district", "locality", "county", "street"]);

interface Suggestion {
  name: string;
  detail: string;
}

// Backup for location type-ahead. Photon has no country filter, so fetch more
// than needed, then keep only the country selected on the form — a worldwide
// search for "brick city" otherwise returns only US results.
async function suggestWithPhoton(query: string, country: string): Promise<Suggestion[]> {
  const q = country ? `${query} ${country}` : query;
  const res = await fetch(
    `https://photon.komoot.io/api/?limit=40&lang=en&q=${encodeURIComponent(q)}`,
    { headers: { "User-Agent": USER_AGENT } },
  );
  if (!res.ok) throw new Error(`Photon returned ${res.status}`);
  const data = await res.json();
  // deno-lint-ignore no-explicit-any
  const features: any[] = data.features ?? [];
  const wanted = country.trim().toLowerCase();
  const matching = features
    .filter((f) => !wanted || String(f.properties?.country ?? "").toLowerCase() === wanted)
    .sort((a, b) =>
      Number(AREA_TYPES.has(b.properties?.type)) - Number(AREA_TYPES.has(a.properties?.type))
    );

  const seen = new Set<string>();
  const out: Suggestion[] = [];
  for (const f of matching) {
    const p = f.properties ?? {};
    if (typeof p.name !== "string" || !p.name.trim()) continue;
    const detail = [p.district, p.city, p.state]
      .filter((v) => typeof v === "string" && v && v !== p.name)
      .join(", ");
    const key = `${p.name}|${detail}`.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ name: p.name, detail });
    if (out.length === 6) break;
  }
  return out;
}

// Google when configured; Photon only if Google is unavailable, not when it
// simply finds nothing. Not cached: partial words aren't worth storing.
async function suggest(query: string, country: string): Promise<Suggestion[]> {
  const apiKey = Deno.env.get("GOOGLE_PLACES_API_KEY");
  if (apiKey) {
    try {
      return await suggestWithGoogle(query, country, apiKey);
    } catch (err) {
      console.error("Google Places failed, using Photon:", err);
    }
  }
  return await suggestWithPhoton(query, country);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: { query?: string; suggest?: boolean; country?: string };
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const query = body.query?.trim() ?? "";
  if (!query) {
    return json({ available: false, message: "No location given." });
  }

  if (body.suggest === true) {
    try {
      return json({ suggestions: await suggest(query, body.country?.trim() ?? "") });
    } catch (_) {
      // Suggestions are optional; the user can always keep their typed text.
      return json({ suggestions: [] });
    }
  }

  const key = normalise(query);

  try {
    const cached = await readCache(key);
    if (cached) {
      return json({ available: true, ...cached });
    }

    const result = await geocode(query);
    if (!result) {
      return json({ available: false, message: "Location not found." });
    }
    await writeCache(key, result);
    return json({ available: true, ...result });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Geocoding failed";
    return json({ available: false, message }, 200);
  }
});
