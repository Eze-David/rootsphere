// Rootsphere — Recurring Donations Edge Function (Paystack Plans + Subscriptions).
//
// Web/Android only — iOS keeps one-time donations via Apple IAP (a real
// auto-renewable-subscription IAP product needs its own separate App Store
// Connect setup and review, so recurring giving is Paystack-only for now).
//
// Creates a fresh Paystack Plan (one per subscription — never shared, so the
// plan_code itself uniquely identifies this row for later webhook
// correlation) and initializes a transaction against it. Paystack turns a
// successful first payment into an active subscription automatically; this
// function only starts that — `paystack-webhook` confirms it.
//
// The client sends
//   { amountCents, currency?, interval, donorName?, donorEmail, message?,
//     purpose?, donorId? }
// and gets back { available: true, authorizationUrl } to open in a browser,
// or { available: false, message } on failure.
//
// Secrets: reuses PAYSTACK_SECRET_KEY (see create-donation-transaction).
// Deploy:
//   supabase functions deploy create-donation-subscription

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

const MIN_AMOUNT_CENTS = 10_000; // ₦100
const MAX_AMOUNT_CENTS = 500_000_000; // ₦5,000,000

const SITE_URL = "https://www.rootsphere.ink";
const DONATION_THANK_YOU_PATH = "/donation-thank-you";

const KNOWN_PURPOSES = new Set<string>([
  "generalPrograms",
  "familyHistoryResearch",
  "oralHistory",
  "recordDigitization",
  "genealogyEducation",
  "appDevelopment",
  "aiResearchAssistant",
  "whereMostNeeded",
]);

interface RequestBody {
  amountCents?: number;
  currency?: string;
  interval?: string; // 'monthly' | 'annually'
  donorName?: string;
  donorEmail?: string;
  message?: string;
  purpose?: string;
  donorId?: string;
}

async function paystack(
  path: string,
  body: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const apiKey = Deno.env.get("PAYSTACK_SECRET_KEY");
  if (!apiKey) throw new Error("unconfigured");

  const res = await fetch(`https://api.paystack.co${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const data = await res.json();
  if (!res.ok || data.status !== true) {
    throw new Error(data.message ?? `Paystack returned ${res.status}`);
  }
  return data;
}

async function insertRow(table: string, row: Record<string, unknown>): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return;

  const res = await fetch(`${url}/rest/v1/${table}`, {
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
    throw new Error(`Could not record subscription: ${detail.slice(0, 300)}`);
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

  const amountCents = Math.round(body.amountCents ?? 0);
  const currency = (body.currency?.trim() || "ngn").toLowerCase();
  const interval = body.interval?.trim();
  const donorName = body.donorName?.trim() || "Anonymous";
  const donorEmail = body.donorEmail?.trim() ?? "";
  const message = body.message?.trim() ?? "";
  const donorId = body.donorId?.trim() ?? "";
  const purposeRaw = body.purpose?.trim();
  const purpose = purposeRaw && KNOWN_PURPOSES.has(purposeRaw) ? purposeRaw : null;

  if (interval !== "monthly" && interval !== "annually") {
    return json({ available: false, message: "Invalid donation interval." });
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

  const reference = `subdon_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;

  try {
    const planName = `RootSphere ${interval} — ${reference}`;
    const plan = await paystack("/plan", {
      name: planName,
      amount: amountCents,
      interval,
      currency: currency.toUpperCase(),
    });
    const planCode = (plan.data as Record<string, unknown>).plan_code as string;

    const tx = await paystack("/transaction/initialize", {
      reference,
      email: donorEmail,
      amount: amountCents,
      currency: currency.toUpperCase(),
      plan: planCode,
      callback_url: `${SITE_URL}/#${DONATION_THANK_YOU_PATH}`,
      metadata: { donor_name: donorName, interval },
    });
    const authorizationUrl = (tx.data as Record<string, unknown>)
      .authorization_url as string;

    await insertRow("donation_subscriptions", {
      id: reference,
      plan_code: planCode,
      donor_id: donorId || null,
      donor_name: donorName,
      donor_email: donorEmail,
      message: message || null,
      purpose,
      amount_cents: amountCents,
      currency,
      interval,
      status: "pending",
    });

    // The first charge behaves exactly like a one-time donation as far as
    // paystack-webhook's existing charge.success handling goes — it just
    // also carries subscription_id so it shows up linked in history.
    await insertRow("donations", {
      id: reference,
      donor_id: donorId || null,
      donor_name: donorName,
      donor_email: donorEmail,
      message: message || null,
      purpose,
      amount_cents: amountCents,
      currency,
      status: "pending",
      subscription_id: reference,
    });

    return json({ available: true, authorizationUrl });
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
