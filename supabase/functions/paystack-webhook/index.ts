// Rootsphere — Paystack webhook receiver for donations (one-time + recurring).
//
// This is the *only* place a donation is ever marked "completed" — the
// client-facing `create-donation-transaction`/`create-donation-subscription`
// functions only ever insert `pending` rows. Paystack calls this endpoint
// directly (not through the app), so it must be deployed WITHOUT Supabase's
// default JWT check, and instead verifies authenticity itself via Paystack's
// signing scheme.
//
// Configure in the Paystack Dashboard (Settings → API Keys & Webhooks): set
// the webhook URL to this function's URL. Paystack signs webhooks with your
// secret key (no separate webhook secret, unlike Stripe).
//
// Recurring donations add three more events on top of the original
// one-time charge.success/charge.failed:
//   - subscription.create: the first payment against a plan succeeded and
//     Paystack turned it into an active subscription — matched by
//     `plan_code` (unique per subscription, since create-donation-subscription
//     mints a fresh plan every time) rather than by reference, since this
//     event carries no reference of ours at all.
//   - subscription.disable: the subscription was cancelled/stopped
//     renewing (from Paystack's dashboard, or expired card, etc.) — also
//     matched by plan_code.
//   - charge.success for a RENEWAL charge: Paystack mints its own new
//     reference for each renewal (not one of ours), so it can't be matched
//     against an existing `donations` row the way the first charge can —
//     instead, when no existing row matches the reference, this checks
//     whether the charge carries a `plan` and if so records a brand new
//     `donations` row for it, linked via `subscription_id`.
//
// Secrets: reuses PAYSTACK_SECRET_KEY.
// Deploy (note --no-verify-jwt — Paystack can't send a Supabase auth token):
//   supabase functions deploy paystack-webhook --no-verify-jwt

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

/** Verifies Paystack's `x-paystack-signature` header (HMAC-SHA512 of the raw body, keyed by the secret key). */
async function verifyPaystackSignature(
  rawBody: string,
  signatureHeader: string,
  secretKey: string,
): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secretKey),
    { name: "HMAC", hash: "SHA-512" },
    false,
    ["sign"],
  );
  const signatureBytes = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(rawBody),
  );
  const computedHex = Array.from(new Uint8Array(signatureBytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return timingSafeEqual(computedHex, signatureHeader);
}

function restHeaders(serviceKey: string): Record<string, string> {
  return {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
  };
}

async function markDonation(
  reference: string,
  patch: Record<string, unknown>,
): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return;

  await fetch(`${url}/rest/v1/donations?id=eq.${encodeURIComponent(reference)}`, {
    method: "PATCH",
    headers: { ...restHeaders(serviceKey), Prefer: "return=minimal" },
    body: JSON.stringify(patch),
  });
}

async function donationExists(reference: string): Promise<boolean> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return false;

  const res = await fetch(
    `${url}/rest/v1/donations?id=eq.${encodeURIComponent(reference)}&select=id`,
    { headers: restHeaders(serviceKey) },
  );
  if (!res.ok) return false;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0;
}

interface SubscriptionRow {
  id: string;
  donor_id: string | null;
  donor_name: string;
  donor_email: string | null;
  message: string | null;
  purpose: string | null;
  amount_cents: number;
  currency: string;
  status: string;
}

async function fetchSubscriptionByPlanCode(
  planCode: string,
): Promise<SubscriptionRow | null> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return null;

  const res = await fetch(
    `${url}/rest/v1/donation_subscriptions?plan_code=eq.${encodeURIComponent(planCode)}&select=id,donor_id,donor_name,donor_email,message,purpose,amount_cents,currency,status`,
    { headers: restHeaders(serviceKey) },
  );
  if (!res.ok) return null;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

async function patchSubscriptionByPlanCode(
  planCode: string,
  patch: Record<string, unknown>,
): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return;

  await fetch(
    `${url}/rest/v1/donation_subscriptions?plan_code=eq.${encodeURIComponent(planCode)}`,
    {
      method: "PATCH",
      headers: { ...restHeaders(serviceKey), Prefer: "return=minimal" },
      body: JSON.stringify(patch),
    },
  );
}

async function insertRenewalDonation(
  reference: string,
  subscription: SubscriptionRow,
  amountCents: number,
  providerReference: string | null,
): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return;

  await fetch(`${url}/rest/v1/donations`, {
    method: "POST",
    headers: { ...restHeaders(serviceKey), Prefer: "return=minimal" },
    body: JSON.stringify({
      id: reference,
      donor_id: subscription.donor_id,
      donor_name: subscription.donor_name,
      donor_email: subscription.donor_email,
      message: subscription.message,
      purpose: subscription.purpose,
      amount_cents: amountCents,
      currency: subscription.currency,
      status: "completed",
      provider_reference: providerReference,
      completed_at: new Date().toISOString(),
      subscription_id: subscription.id,
    }),
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const secretKey = Deno.env.get("PAYSTACK_SECRET_KEY");
  if (!secretKey) {
    return new Response("Webhook not configured", { status: 500 });
  }

  // Signature verification needs the exact raw bytes — read as text before
  // any JSON parsing.
  const rawBody = await req.text();
  const signature = req.headers.get("x-paystack-signature");
  if (!signature || !(await verifyPaystackSignature(rawBody, signature, secretKey))) {
    return new Response("Invalid signature", { status: 400 });
  }

  let event: { event?: string; data?: Record<string, unknown> };
  try {
    event = JSON.parse(rawBody);
  } catch (_) {
    return new Response("Invalid JSON", { status: 400 });
  }

  const data = event.data;
  const reference = typeof data?.reference === "string" ? data.reference : null;
  const plan = data?.plan as Record<string, unknown> | undefined;
  const planCode = typeof plan?.plan_code === "string" ? plan.plan_code : null;

  switch (event.event) {
    case "charge.success": {
      if (reference && (await donationExists(reference))) {
        // The first charge against a plan (or an ordinary one-time
        // donation) — the row already exists as `pending`.
        await markDonation(reference, {
          status: "completed",
          completed_at: new Date().toISOString(),
          provider_reference:
            data?.id !== undefined ? String(data.id) : null,
        });
      } else if (reference && planCode) {
        // A renewal charge — Paystack minted this reference itself, so
        // there's no pending row to update; record it fresh instead.
        const subscription = await fetchSubscriptionByPlanCode(planCode);
        if (subscription) {
          const amountCents =
            typeof data?.amount === "number"
              ? data.amount
              : subscription.amount_cents;
          await insertRenewalDonation(
            reference,
            subscription,
            amountCents,
            data?.id !== undefined ? String(data.id) : null,
          );
        }
      }
      break;
    }
    case "charge.failed": {
      if (reference && (await donationExists(reference))) {
        await markDonation(reference, { status: "failed" });
      }
      break;
    }
    case "subscription.create": {
      const subscriptionCode =
        typeof data?.subscription_code === "string"
          ? data.subscription_code
          : null;
      const emailToken =
        typeof data?.email_token === "string" ? data.email_token : null;
      if (planCode && subscriptionCode && emailToken) {
        await patchSubscriptionByPlanCode(planCode, {
          paystack_subscription_code: subscriptionCode,
          email_token: emailToken,
          status: "active",
        });
      }
      break;
    }
    case "subscription.disable":
    case "subscription.not_renew": {
      if (planCode) {
        await patchSubscriptionByPlanCode(planCode, {
          status: "cancelled",
          cancelled_at: new Date().toISOString(),
        });
      }
      break;
    }
    default:
      // Ignore everything else.
      break;
  }

  return new Response("ok", { status: 200 });
});
