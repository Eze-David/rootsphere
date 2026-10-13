// Rootsphere — pay an accepted research quotation via Paystack.
//
// The requester accepts a quotation in the app (respond_research_quotation
// RPC), then calls this with { quotationId }. We check — server-side, with
// the caller's own JWT — that they're the request's requester and that the
// quotation is accepted and unpaid, then initialise a Paystack transaction
// for the quotation's total and return { available: true, authorizationUrl }.
//
// Payment is only confirmed by `paystack-webhook` (references starting with
// "quo_"), which calls mark_quotation_paid to release the request.
//
// Secrets: reuses PAYSTACK_SECRET_KEY.
// Deploy:
//   supabase functions deploy create-quotation-payment

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

// Hash-routed, like the donation callback — Paystack returns the browser to
// the request itself on the Collab tab.
const SITE_URL = "https://www.rootsphere.ink";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const paystackKey = Deno.env.get("PAYSTACK_SECRET_KEY");
  if (!url || !serviceKey || !anonKey) {
    return json({ available: false, message: "Server misconfigured." });
  }
  if (!paystackKey) {
    return json({
      available: false,
      message: "Payments are not configured yet (PAYSTACK_SECRET_KEY unset).",
    });
  }

  let quotationId = "";
  try {
    quotationId = String((await req.json()).quotationId ?? "").trim();
  } catch (_) {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (!quotationId) {
    return json({ available: false, message: "Missing quotation." });
  }

  // Who is calling?
  const authHeader = req.headers.get("Authorization") ?? "";
  const userRes = await fetch(`${url}/auth/v1/user`, {
    headers: { apikey: anonKey, Authorization: authHeader },
  });
  if (!userRes.ok) {
    return json({ available: false, message: "Please sign in again." }, 401);
  }
  const user = await userRes.json();
  const userId: string = user?.id ?? "";
  const email: string = user?.email ?? "";
  if (!userId || !email) {
    return json({ available: false, message: "Your account has no email address." });
  }

  const service = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };

  const qRes = await fetch(
    `${url}/rest/v1/research_quotations?id=eq.${encodeURIComponent(quotationId)}` +
      `&select=id,status,total_cents,currency,opportunity_id,` +
      `opportunities(requester_id,title,tree_id)`,
    { headers: service },
  );
  const rows = qRes.ok ? await qRes.json() : [];
  const q = Array.isArray(rows) ? rows[0] : null;
  if (!q) {
    return json({ available: false, message: "Quotation not found." });
  }
  if (q.opportunities?.requester_id !== userId) {
    return json({ available: false, message: "This quotation isn't yours." }, 403);
  }
  if (q.status === "paid") {
    return json({ available: false, message: "This quotation is already paid." });
  }
  if (q.status !== "accepted") {
    return json({ available: false, message: "Accept the quotation before paying." });
  }

  const reference = `quo_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

  const psRes = await fetch("https://api.paystack.co/transaction/initialize", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${paystackKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      reference,
      email,
      amount: q.total_cents, // smallest currency unit (kobo for NGN)
      currency: String(q.currency ?? "ngn").toUpperCase(),
      callback_url: `${SITE_URL}/#/collab?openId=${encodeURIComponent(q.opportunity_id)}`,
      metadata: {
        kind: "research_quotation",
        quotation_id: q.id,
        opportunity_id: q.opportunity_id,
        title: q.opportunities?.title,
      },
    }),
  });
  const ps = await psRes.json();
  if (!psRes.ok || ps.status !== true) {
    return json({
      available: false,
      message: ps?.message ?? `Paystack returned ${psRes.status}`,
    });
  }

  const attach = await fetch(`${url}/rest/v1/rpc/attach_quotation_payment_reference`, {
    method: "POST",
    headers: service,
    body: JSON.stringify({ p_quotation_id: q.id, p_reference: reference }),
  });
  if (!attach.ok) {
    return json({ available: false, message: "Could not start payment. Please try again." });
  }

  return json({ available: true, authorizationUrl: ps.data.authorization_url });
});
