// Rootsphere — Paystack webhook receiver for donations.
//
// This is the *only* place a donation is ever marked "completed" — the
// client-facing `create-donation-transaction` function only ever inserts
// `pending` rows. Paystack calls this endpoint directly (not through the
// app), so it must be deployed WITHOUT Supabase's default JWT check, and
// instead verifies authenticity itself via Paystack's signing scheme.
//
// Configure in the Paystack Dashboard (Settings → API Keys & Webhooks): set
// the webhook URL to this function's URL. Paystack signs webhooks with your
// secret key (no separate webhook secret, unlike Stripe).
//
// Secrets: reuses PAYSTACK_SECRET_KEY (set by create-donation-transaction).
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

async function markDonation(
  reference: string,
  patch: Record<string, unknown>,
): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return;

  await fetch(`${url}/rest/v1/donations?id=eq.${encodeURIComponent(reference)}`, {
    method: "PATCH",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify(patch),
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

  switch (event.event) {
    case "charge.success": {
      if (reference) {
        await markDonation(reference, {
          status: "completed",
          completed_at: new Date().toISOString(),
          provider_reference:
            data?.id !== undefined ? String(data.id) : null,
        });
      }
      break;
    }
    case "charge.failed": {
      if (reference) {
        await markDonation(reference, { status: "failed" });
      }
      break;
    }
    default:
      // Ignore everything else — only the two events above affect a donation's state.
      break;
  }

  return new Response("ok", { status: 200 });
});
