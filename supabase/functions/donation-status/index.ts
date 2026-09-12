// Rootsphere — read-only donation status lookup, by reference.
//
// The Paystack checkout callback redirects back to
// /#/donation-thank-you?reference=... without telling us whether the
// payment actually succeeded (that's only known once `paystack-webhook`
// fires, asynchronously). The thank-you page polls this function to show a
// real "processing / succeeded / failed" state instead of one generic
// message regardless of outcome.
//
// Deployed with --no-verify-jwt: a guest donor (no Supabase session) needs
// to reach this too. The reference itself — an unguessable
// `don_<timestamp>_<random>` string only the donor's own browser ever saw —
// is the access control, same trust model as a payment receipt link. This
// intentionally returns only the fields needed to render a receipt, never
// donor PII beyond what the donor themselves already knows.
//
// Deploy:
//   supabase functions deploy donation-status --no-verify-jwt

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "GET") {
    return json({ error: "Method not allowed" }, 405);
  }

  const reference = new URL(req.url).searchParams.get("reference")?.trim();
  if (!reference) {
    return json({ found: false, message: "Missing reference." }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    return json({ found: false, message: "Not configured." }, 500);
  }

  const res = await fetch(
    `${url}/rest/v1/donations?id=eq.${encodeURIComponent(reference)}&select=status,amount_cents,currency,purpose,donor_name,created_at`,
    {
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
    },
  );
  if (!res.ok) {
    return json({ found: false, message: "Lookup failed." }, 502);
  }

  const rows = await res.json();
  if (!Array.isArray(rows) || rows.length === 0) {
    return json({ found: false });
  }

  const row = rows[0];
  return json({
    found: true,
    status: row.status,
    amountCents: row.amount_cents,
    currency: row.currency,
    purpose: row.purpose,
    donorName: row.donor_name,
    createdAt: row.created_at,
  });
});
