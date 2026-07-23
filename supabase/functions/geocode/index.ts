// Rootsphere — Location Map geocoding Edge Function.
//
// Resolves a free-text place name (e.g. "Kubwa, Abuja, Nigeria") to
// coordinates so the person profile's Map section can plot a pin. The
// Flutter client sends { query } and gets back
//   { available: true, lat, lon, displayName }
// or { available: false, message } when nothing matches.
//
// Provider: OpenStreetMap Nominatim (https://nominatim.org) — free, no API
// key, but rate-limited and requires a real identifying User-Agent per its
// usage policy. Results are cached in `geocode_cache` (keyed by the
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

async function geocode(query: string): Promise<GeocodeResult | null> {
  const res = await fetch(
    `https://nominatim.openstreetmap.org/search?format=jsonv2&limit=1&q=${encodeURIComponent(query)}`,
    {
      headers: {
        // Nominatim's usage policy requires a real identifying User-Agent.
        "User-Agent": "Rootsphere/1.0 (family tree app; geocode Edge Function)",
      },
    },
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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: { query?: string };
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const query = body.query?.trim() ?? "";
  if (!query) {
    return json({ available: false, message: "No location given." });
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
