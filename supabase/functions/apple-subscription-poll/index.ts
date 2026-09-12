// Rootsphere — Daily poll for Apple subscription renewals.
//
// Apple never calls us back on renewal the way Paystack's webhook does, so
// this is the only mechanism that notices a renewal happened: for every
// active Apple subscription, ask the App Store Server API for its current
// status and most recent transaction. If that transaction is one we
// haven't recorded yet, it's a new renewal charge — insert it as its own
// `donations` row, same as `apple-subscription-verify` does for the first
// charge.
//
// Triggered by pg_cron (see 20260910000200_apple_subscription_poll_cron.sql)
// once a day, not by any user action — protected by a shared secret rather
// than requiring a signed-in user, since cron has no Supabase session of
// its own.
//
// Deploy (no user ever calls this directly, so no JWT-required client call
// exists — still deployed with the default JWT check; the cron job's
// Authorization header carries the project's anon key, which satisfies it,
// and the x-cron-secret header is this function's own, separate guard):
//   supabase functions deploy apple-subscription-poll

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { fetchAppleSubscriptionStatus } from "../_shared/apple_store.ts";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

interface SubscriptionRow {
  id: string;
  apple_original_transaction_id: string;
  apple_last_transaction_id: string | null;
  donor_id: string | null;
  donor_name: string;
  donor_email: string | null;
  message: string | null;
  purpose: string | null;
  currency: string;
}

async function fetchActiveAppleSubscriptions(): Promise<SubscriptionRow[]> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return [];

  const res = await fetch(
    `${url}/rest/v1/donation_subscriptions?provider=eq.apple_iap&status=eq.active&select=id,apple_original_transaction_id,apple_last_transaction_id,donor_id,donor_name,donor_email,message,purpose,currency`,
    { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } },
  );
  if (!res.ok) return [];
  const rows = await res.json();
  return Array.isArray(rows) ? rows : [];
}

async function patchSubscription(
  id: string,
  patch: Record<string, unknown>,
): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return;

  await fetch(`${url}/rest/v1/donation_subscriptions?id=eq.${encodeURIComponent(id)}`, {
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

async function insertRenewalDonation(
  transactionId: string,
  subscription: SubscriptionRow,
  amountCents: number,
): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return;

  await fetch(`${url}/rest/v1/donations`, {
    method: "POST",
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      "Content-Type": "application/json",
      Prefer: "resolution=ignore-duplicates,return=minimal",
    },
    body: JSON.stringify({
      id: `apple_${transactionId}`,
      donor_id: subscription.donor_id,
      donor_name: subscription.donor_name,
      donor_email: subscription.donor_email,
      message: subscription.message,
      purpose: subscription.purpose,
      amount_cents: amountCents,
      currency: subscription.currency,
      status: "completed",
      provider: "apple_iap",
      provider_reference: transactionId,
      completed_at: new Date().toISOString(),
      subscription_id: subscription.id,
    }),
  });
}

/** Apple's subscription status codes: 1=active, 2=expired, 3=billing retry, 4=billing grace period, 5=revoked. */
function mapStatus(code: number): "active" | "cancelled" {
  return code === 1 || code === 3 || code === 4 ? "active" : "cancelled";
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  const secret = Deno.env.get("CRON_POLL_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "Forbidden" }, 403);
  }

  const subscriptions = await fetchActiveAppleSubscriptions();
  let renewalsRecorded = 0;
  let errors = 0;

  for (const sub of subscriptions) {
    try {
      const { status, transaction } = await fetchAppleSubscriptionStatus(
        sub.apple_original_transaction_id,
      );
      const latestTransactionId = transaction.transactionId as string | undefined;
      const mappedStatus = mapStatus(status);

      if (
        latestTransactionId &&
        latestTransactionId !== sub.apple_last_transaction_id
      ) {
        const amountCents = Math.round(Number(transaction.price ?? 0));
        await insertRenewalDonation(latestTransactionId, sub, amountCents);
        renewalsRecorded++;
      }

      const patch: Record<string, unknown> = { status: mappedStatus };
      if (latestTransactionId) patch.apple_last_transaction_id = latestTransactionId;
      if (mappedStatus === "cancelled") patch.cancelled_at = new Date().toISOString();
      await patchSubscription(sub.id, patch);
    } catch (_) {
      errors++;
    }
  }

  return json({ checked: subscriptions.length, renewalsRecorded, errors });
});
