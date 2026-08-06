// Rootsphere — Donations Edge Function (Paystack).
//
// Initializes a Paystack transaction so someone can support the research on a
// specific opportunity (e.g. "help find the origin of the Deo family") — a
// one-time payment, separate from the paid Finder/Indexer collaboration work
// itself. Paystack (not Stripe, which doesn't support Nigerian payouts)
// processes the actual charge.
//
// The client sends
//   { opportunityId, opportunityTitle, treeId, amountCents, currency?,
//     donorName?, donorEmail, message? }
// and gets back { available: true, authorizationUrl } to open in a browser,
// or { available: false, message } on failure.
//
// The actual confirmation of payment happens via `paystack-webhook`, not
// here — this only *initializes* the transaction and records a `pending` row
// so the app can show "processing" state immediately.
//
// Secrets:
//   supabase secrets set PAYSTACK_SECRET_KEY=sk_test_... (or sk_live_... once ready)
// Deploy:
//   supabase functions deploy create-donation-transaction

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

const MIN_AMOUNT_CENTS = 10_000; // ₦100 — a sane floor for a NGN donation.
const MAX_AMOUNT_CENTS = 500_000_000; // ₦5,000,000 — sanity cap against fat-finger input.

interface RequestBody {
  opportunityId?: string;
  opportunityTitle?: string;
  treeId?: string;
  amountCents?: number;
  currency?: string;
  donorName?: string;
  donorEmail?: string;
  message?: string;
  donorId?: string;
}

async function initializeTransaction(params: {
  reference: string;
  email: string;
  amountCents: number;
  currency: string;
  callbackUrl: string;
  metadata: Record<string, unknown>;
}): Promise<{ authorizationUrl: string; reference: string }> {
  const apiKey = Deno.env.get("PAYSTACK_SECRET_KEY");
  if (!apiKey) throw new Error("unconfigured");

  const res = await fetch("https://api.paystack.co/transaction/initialize", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      reference: params.reference,
      email: params.email,
      amount: params.amountCents, // Paystack's "amount" is already the smallest unit (kobo for NGN).
      currency: params.currency.toUpperCase(),
      callback_url: params.callbackUrl,
      metadata: params.metadata,
    }),
  });

  const data = await res.json();
  if (!res.ok || data.status !== true) {
    throw new Error(data.message ?? `Paystack returned ${res.status}`);
  }
  return {
    authorizationUrl: data.data.authorization_url as string,
    reference: data.data.reference as string,
  };
}

async function insertPendingDonation(row: Record<string, unknown>): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return;

  const res = await fetch(`${url}/rest/v1/donations`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(row),
  });
  if (!res.ok) {
    const detail = await res.text();
    throw new Error(`Could not record donation: ${detail.slice(0, 300)}`);
  }
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

  // Both blank together means a general "support Rootsphere" donation, not
  // tied to any specific research opportunity — e.g. someone donating from
  // the sign-in screen without an account. Exactly one being blank would be
  // a malformed request, so that's still rejected.
  const opportunityId = body.opportunityId?.trim() || null;
  const opportunityTitle = body.opportunityTitle?.trim() || "Rootsphere";
  const treeId = body.treeId?.trim() || null;
  const amountCents = Math.round(body.amountCents ?? 0);
  const currency = (body.currency?.trim() || "ngn").toLowerCase();
  const donorName = body.donorName?.trim() || "Anonymous";
  const donorEmail = body.donorEmail?.trim() ?? "";
  const message = body.message?.trim() ?? "";
  const donorId = body.donorId?.trim() ?? "";

  if (Boolean(opportunityId) !== Boolean(treeId)) {
    return json({ available: false, message: "Missing opportunity." }, 200);
  }
  if (!donorEmail || !donorEmail.includes("@")) {
    return json({ available: false, message: "An email address is required to donate." });
  }
  if (!Number.isFinite(amountCents) || amountCents < MIN_AMOUNT_CENTS) {
    return json({
      available: false,
      message: `Minimum donation is ${(MIN_AMOUNT_CENTS / 100).toFixed(2)} ${currency.toUpperCase()}.`,
    });
  }
  if (amountCents > MAX_AMOUNT_CENTS) {
    return json({ available: false, message: "That amount looks too large — please try a smaller one." });
  }

  const redirectBase = Deno.env.get("SUPABASE_URL");
  if (!redirectBase) {
    return json({ available: false, message: "Donations are not configured yet." });
  }

  const reference = `don_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

  try {
    const tx = await initializeTransaction({
      reference,
      email: donorEmail,
      amountCents,
      currency,
      callbackUrl: `${redirectBase}/functions/v1/donation-redirect`,
      metadata: {
        opportunity_id: opportunityId,
        tree_id: treeId,
        donor_name: donorName,
      },
    });

    await insertPendingDonation({
      id: tx.reference,
      opportunity_id: opportunityId,
      tree_id: treeId,
      donor_id: donorId || null,
      donor_name: donorName,
      donor_email: donorEmail,
      message: message || null,
      amount_cents: amountCents,
      currency,
      status: "pending",
    });

    return json({ available: true, authorizationUrl: tx.authorizationUrl });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Could not start checkout";
    if (message === "unconfigured") {
      return json({
        available: false,
        message: "Donations are not configured yet (PAYSTACK_SECRET_KEY unset).",
      });
    }
    return json({ available: false, message }, 200);
  }
});
