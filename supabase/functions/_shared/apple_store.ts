// Shared Apple App Store Server API helpers — used by `apple-iap-verify`
// (one-time consumable tiers), `apple-subscription-verify` (initial
// recurring purchase), and `apple-subscription-poll` (daily renewal check).
//
// All three authenticate the same way: a short-lived ES256 JWT signed with
// the In-App Purchase key from App Store Connect → Users and Access →
// Integrations → In-App Purchase key.
//   supabase secrets set APPLE_IAP_KEY_ID=...
//   supabase secrets set APPLE_IAP_ISSUER_ID=...
//   supabase secrets set APPLE_IAP_PRIVATE_KEY="$(cat AuthKey_XXXX.p8)"

export const BUNDLE_ID = "com.rootsphere.rootsphere";

export function base64UrlEncode(bytes: Uint8Array): string {
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
export async function appStoreServerApiToken(): Promise<string> {
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

export function decodeJwsPayload(jws: string): Record<string, unknown> {
  const parts = jws.split(".");
  if (parts.length !== 3) throw new Error("Malformed JWS");
  const padded = parts[1].replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(padded.padEnd(padded.length + ((4 - (padded.length % 4)) % 4), "="));
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return JSON.parse(new TextDecoder().decode(bytes));
}

/** Fetches a single transaction record — tries production first, then sandbox (TestFlight/review builds only ever exist in sandbox). */
export async function fetchAppleTransaction(
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
      return decodeJwsPayload(data.signedTransactionInfo as string);
    }
    lastStatus = res.status;
  }
  throw new Error(`Apple returned ${lastStatus} for transaction ${transactionId}`);
}

export interface AppleSubscriptionStatus {
  /** 1=active, 2=expired, 3=billing retry, 4=billing grace period, 5=revoked. */
  status: number;
  transaction: Record<string, unknown>;
}

/** Fetches the current status + most recent transaction for a subscription, by its stable original transaction ID. Tries production first, then sandbox. */
export async function fetchAppleSubscriptionStatus(
  originalTransactionId: string,
): Promise<AppleSubscriptionStatus> {
  const token = await appStoreServerApiToken();
  const hosts = [
    "https://api.storekit.itunes.apple.com",
    "https://api.storekit-sandbox.itunes.apple.com",
  ];

  let lastStatus = 0;
  for (const host of hosts) {
    const res = await fetch(
      `${host}/inApps/v1/subscriptions/${originalTransactionId}`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    if (res.ok) {
      const data = await res.json();
      const groups = (data.data ?? []) as Array<{
        lastTransactions?: Array<{
          status: number;
          signedTransactionInfo: string;
        }>;
      }>;
      const lastTx = groups[0]?.lastTransactions?.[0];
      if (!lastTx) throw new Error("No subscription data returned");
      return {
        status: lastTx.status,
        transaction: decodeJwsPayload(lastTx.signedTransactionInfo),
      };
    }
    lastStatus = res.status;
  }
  throw new Error(
    `Apple returned ${lastStatus} for subscription ${originalTransactionId}`,
  );
}
