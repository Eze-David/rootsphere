// Rootsphere — Cancels a recurring donation (Paystack subscription).
//
// Requires sign-in (deployed WITH the default JWT check, unlike
// paystack-webhook) — only the donor who owns the subscription can cancel
// it from the app. A guest-created recurring donation (no donor_id) has no
// account to authorize this against, so those are cancelled by emailing
// RootSphere support instead — see MyDonationsScreen's copy.
//
// Deploy:
//   supabase functions deploy cancel-donation-subscription

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

interface SubscriptionRow {
  id: string;
  donor_id: string | null;
  paystack_subscription_code: string | null;
  email_token: string | null;
  status: string;
}

async function currentUserId(authHeader: string | null): Promise<string | null> {
  if (!authHeader) return null;
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !anonKey) return null;

  const res = await fetch(`${url}/auth/v1/user`, {
    headers: { Authorization: authHeader, apikey: anonKey },
  });
  if (!res.ok) return null;
  const data = await res.json();
  return typeof data.id === "string" ? data.id : null;
}

async function fetchSubscription(id: string): Promise<SubscriptionRow | null> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return null;

  const res = await fetch(
    `${url}/rest/v1/donation_subscriptions?id=eq.${encodeURIComponent(id)}&select=id,donor_id,paystack_subscription_code,email_token,status`,
    { headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` } },
  );
  if (!res.ok) return null;
  const rows = await res.json();
  return Array.isArray(rows) && rows.length > 0 ? rows[0] : null;
}

async function markCancelled(id: string): Promise<void> {
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) return;

  await fetch(
    `${url}/rest/v1/donation_subscriptions?id=eq.${encodeURIComponent(id)}`,
    {
      method: "PATCH",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
        Prefer: "return=minimal",
      },
      body: JSON.stringify({
        status: "cancelled",
        cancelled_at: new Date().toISOString(),
      }),
    },
  );
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const userId = await currentUserId(req.headers.get("Authorization"));
  if (!userId) {
    return json({ success: false, message: "Sign in required." }, 401);
  }

  let body: { subscriptionId?: string };
  try {
    body = await req.json();
  } catch (_) {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const subscriptionId = body.subscriptionId?.trim();
  if (!subscriptionId) {
    return json({ success: false, message: "Missing subscription." }, 400);
  }

  const subscription = await fetchSubscription(subscriptionId);
  if (!subscription) {
    return json({ success: false, message: "Subscription not found." }, 404);
  }
  if (subscription.donor_id !== userId) {
    return json({ success: false, message: "Not your subscription." }, 403);
  }
  if (subscription.status === "cancelled") {
    return json({ success: true });
  }
  if (!subscription.paystack_subscription_code || !subscription.email_token) {
    return json({
      success: false,
      message:
        "This subscription hasn't fully activated yet — please try again shortly.",
    });
  }

  const apiKey = Deno.env.get("PAYSTACK_SECRET_KEY");
  if (!apiKey) {
    return json({ success: false, message: "Donations are not configured yet." });
  }

  try {
    const res = await fetch("https://api.paystack.co/subscription/disable", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        code: subscription.paystack_subscription_code,
        token: subscription.email_token,
      }),
    });
    const data = await res.json();
    if (!res.ok || data.status !== true) {
      throw new Error(data.message ?? `Paystack returned ${res.status}`);
    }
    await markCancelled(subscriptionId);
    return json({ success: true });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Could not cancel subscription";
    return json({ success: false, message });
  }
});
