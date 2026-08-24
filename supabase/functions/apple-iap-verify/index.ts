// Rootsphere — Apple In-App Purchase verification for iOS donations.
//
// Apple rejected the app (Guideline 3.1.1) for routing donations through
// Paystack on iOS — donations "associated with receiving digital content or
// services" (Apple's own words for this class of transaction) must go
// through In-App Purchase there. Android and the web keep the existing
// Paystack flow (`create-donation-transaction` / `paystack-webhook`)
// unchanged; this function is the iOS-only equivalent.
//
// The client completes a StoreKit purchase for one of the fixed consumable
// donation tiers, then calls this function with the transaction ID. This
// function calls Apple's own App Store Server API to fetch the
// authoritative transaction record (never trusts client-supplied amounts),
// and only then inserts a `completed` donation row — same "the client can
// never fake a completed donation" guarantee `paystack-webhook` gives, just
// via a direct server-to-server call instead of an inbound webhook.
//
// Secrets (Apple Developer → Users and Access → Integrations → In-App
// Purchase key):
//   supabase secrets set APPLE_IAP_KEY_ID=...
//   supabase secrets set APPLE_IAP_ISSUER_ID=...
//   supabase secrets set APPLE_IAP_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"
// Deploy:
//   supabase functions deploy apple-iap-verify

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

const BUNDLE_ID = "com.rootsphere.rootsphere";

// Fixed consumable donation tiers — must match the Product IDs created in
// App Store Connect exactly. Apple's transaction record is the source of
// truth for the actual price/currency charged; this set is only used to
// reject anything that isn't one of ours.
const KNOWN_PRODUCT_IDS = new Set<string>([
  "com.rootsphere.rootsphere.donation.tier1",
  "com.rootsphere.rootsphere.donation.tier2",
  "com.rootsphere.rootsphere.donation.tier3",
  "com.rootsphere.rootsphere.donation.tier4",
  "com.rootsphere.rootsphere.donation.tier5",
]);

interface RequestBody {
  transactionId?: string;
  productId?: string;
  opportunityId?: string;
  treeId?: string;
  donorId?: string;
  donorName?: string;
  donorEmail?: string;
  message?: string;
}

function base64UrlEncode(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToPkcs8(pem: string): Uint8Array {
  const stripped = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(stripped);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

/** Signs a short-lived ES256 JWT to authenticate against Apple's App Store Server API. */
async function appStoreServerApiToken(): Promise<string> {
  const keyId = Deno.env.get("APPLE_IAP_KEY_ID");
  const issuerId = Deno.env.get("APPLE_IAP_ISSUER_ID");
  const privateKeyPem = Deno.env.get("APPLE_IAP_PRIVATE_KEY");
  if (!keyId || !issuerId || !privateKeyPem) throw new Error("unconfigured");

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(privateKeyPem),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const nowSeconds = Math.floor(Date.now() / 1000);
  const header = { alg: "ES256", kid: keyId, typ: "JWT" };
  const payload = {
    iss: issuerId,
    iat: nowSeconds,
    exp: nowSeconds + 600, // Apple caps this at 60 minutes; a short lifetime is plenty since we mint one per call.
    aud: "appstoreconnect-v1",
    bid: BUNDLE_ID,
  };

  const encoder = new TextEncoder();
  const signingInput =
    `${base64UrlEncode(encoder.encode(JSON.stringify(header)))}.` +
    base64UrlEncode(encoder.encode(JSON.stringify(payload)));

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncode(new Uint8Array(signature))}`;
}

function decodeJwsPayload(jws: string): Record<string, unknown> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("Malformed transaction JWS");
  const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded.padEnd(padded.length + ((4 - (padded.length % 4)) % 4), "="));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return JSON.parse(new TextDecoder().decode(bytes));
}

/** Fetches the authoritative transaction record from Apple — tries production first, then sandbox (TestFlight/review builds only ever exist in sandbox). */
async function fetchAppleTransaction(
  transactionId: string,
): Promise<Record<string, unknown>> {
  const token = await appStoreServerApiToken();
  const hosts = [
    "https://api.storekit.itunes.apple.com",
    "https://api.storekit-sandbox.itunes.apple.com",
  ];

  let lastStatus = 0;
  for (const host of hosts) {
    const res = await fetch(`${host}/inApps/v1/transactions/${transactionId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.ok) {
      const data = await res.json();
      const signedTransactionInfo = data.signedTransactionInfo as string;
      return decodeJwsPayload(signedTransactionInfo);
    }
    lastStatus = res.status;
  }
  throw new Error(`Apple returned ${lastStatus} for transaction ${transactionId}`);
}

async function insertCompletedDonation(row: Record<string, unknown>): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return;

  const res = await fetch(`${url}/rest/v1/donations`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      Prefer: "resolution=ignore-duplicates,return=minimal",
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

  const transactionId = body.transactionId?.trim();
  const claimedProductId = body.productId?.trim();
  const opportunityId = body.opportunityId?.trim() || null;
  const treeId = body.treeId?.trim() || null;
  const donorId = body.donorId?.trim() || null;
  const donorName = body.donorName?.trim() || "Anonymous";
  const donorEmail = body.donorEmail?.trim() || null;
  const message = body.message?.trim() || null;

  if (!transactionId) {
    return json({ available: false, message: "Missing transaction ID." });
  }
  if (Boolean(opportunityId) !== Boolean(treeId)) {
    return json({ available: false, message: "Missing opportunity." });
  }

  try {
    const transaction = await fetchAppleTransaction(transactionId);
    const productId = transaction.productId as string | undefined;
    if (!productId || !KNOWN_PRODUCT_IDS.has(productId)) {
      return json({ available: false, message: "Unrecognized product." });
    }
    if (claimedProductId && claimedProductId !== productId) {
      return json({ available: false, message: "Product mismatch." });
    }
    if (transaction.bundleId !== BUNDLE_ID) {
      return json({ available: false, message: "Bundle ID mismatch." });
    }

    // Apple's own record is the only source of truth for amount/currency —
    // `price` is in the transaction's currency's smallest unit (matches
    // `amount_cents`'s existing "smallest unit" convention).
    const amountCents = Math.round(Number(transaction.price ?? 0));
    const currency = String(transaction.currency ?? "usd").toLowerCase();

    await insertCompletedDonation({
      id: `apple_${transactionId}`,
      opportunity_id: opportunityId,
      tree_id: treeId,
      donor_id: donorId,
      donor_name: donorName,
      donor_email: donorEmail,
      message,
      amount_cents: amountCents,
      currency,
      status: "completed",
      provider: "apple_iap",
      provider_reference: transactionId,
      completed_at: new Date().toISOString(),
    });

    return json({ available: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Could not verify purchase";
    if (message === "unconfigured") {
      return json({
        available: false,
        message: "Apple IAP is not configured yet (APPLE_IAP_* secrets unset).",
      });
    }
    return json({ available: false, message });
  }
});
