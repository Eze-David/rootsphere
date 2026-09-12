// Rootsphere — Apple auto-renewable subscription verification (iOS
// recurring donations — Monthly/Annual "RootSphere Heritage Partner").
//
// Separate from `apple-iap-verify` (one-time consumable tiers): a
// subscription purchase needs its own `donation_subscriptions` row so it
// can be tracked/cancelled like the Paystack recurring flow, plus the
// first `donations` row for that initial charge. Every renewal after this
// one is recorded by `apple-subscription-poll` instead — Apple never calls
// us back the way Paystack's webhook does.
//
// Secrets: reuses APPLE_IAP_KEY_ID / APPLE_IAP_ISSUER_ID / APPLE_IAP_PRIVATE_KEY.
// Deploy:
//   supabase functions deploy apple-subscription-verify

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { BUNDLE_ID, fetchAppleTransaction } from "../_shared/apple_store.ts";

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

// Must match the 2 Auto-Renewable Subscription products created in App
// Store Connect, under the "RootSphere Heritage Partner" subscription
// group.
const PRODUCT_INTERVALS: Record<string, string> = {
  "com.rootsphere.rootsphere.donation.monthly": "monthly",
  "com.rootsphere.rootsphere.donation.annual": "annually",
};

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
  transactionId?: string;
  productId?: string;
  donorId?: string;
  donorName?: string;
  donorEmail?: string;
  message?: string;
  purpose?: string;
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
      Prefer: "resolution=ignore-duplicates,return=minimal",
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

  const transactionId = body.transactionId?.trim();
  const claimedProductId = body.productId?.trim();
  const donorId = body.donorId?.trim() || null;
  const donorName = body.donorName?.trim() || "Anonymous";
  const donorEmail = body.donorEmail?.trim() || null;
  const message = body.message?.trim() || null;
  const purposeRaw = body.purpose?.trim();
  const purpose = purposeRaw && KNOWN_PURPOSES.has(purposeRaw) ? purposeRaw : null;

  if (!transactionId) {
    return json({ available: false, message: "Missing transaction ID." });
  }

  try {
    const transaction = await fetchAppleTransaction(transactionId);
    const productId = transaction.productId as string | undefined;
    const interval = productId ? PRODUCT_INTERVALS[productId] : undefined;
    if (!productId || !interval) {
      return json({ available: false, message: "Unrecognized product." });
    }
    if (claimedProductId && claimedProductId !== productId) {
      return json({ available: false, message: "Product mismatch." });
    }
    if (transaction.bundleId !== BUNDLE_ID) {
      return json({ available: false, message: "Bundle ID mismatch." });
    }

    const originalTransactionId =
      (transaction.originalTransactionId as string | undefined) ?? transactionId;
    const amountCents = Math.round(Number(transaction.price ?? 0));
    const currency = String(transaction.currency ?? "usd").toLowerCase();
    // Deterministic IDs from the transaction itself — a retried client call
    // hits the same primary key, so `ignore-duplicates` makes this safe to
    // call more than once for the same purchase.
    const subscriptionId = `apple_sub_${originalTransactionId}`;

    await insertRow("donation_subscriptions", {
      id: subscriptionId,
      provider: "apple_iap",
      apple_original_transaction_id: originalTransactionId,
      apple_last_transaction_id: transactionId,
      apple_product_id: productId,
      donor_id: donorId,
      donor_name: donorName,
      donor_email: donorEmail,
      message,
      purpose,
      amount_cents: amountCents,
      currency,
      interval,
      status: "active",
    });

    await insertRow("donations", {
      id: `apple_${transactionId}`,
      donor_id: donorId,
      donor_name: donorName,
      donor_email: donorEmail,
      message,
      purpose,
      amount_cents: amountCents,
      currency,
      status: "completed",
      provider: "apple_iap",
      provider_reference: transactionId,
      completed_at: new Date().toISOString(),
      subscription_id: subscriptionId,
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
