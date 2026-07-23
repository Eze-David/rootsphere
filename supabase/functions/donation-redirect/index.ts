// Rootsphere — post-payment landing page for Paystack donations.
//
// Paystack redirects the browser to a single `callback_url` once the user
// finishes on the payment page, regardless of outcome — it doesn't
// distinguish success/cancel via the redirect itself. The donation is
// actually confirmed by `paystack-webhook`, not by this page; this exists
// purely so the browser tab doesn't dead-end on a blank/error page after
// checkout. Points at this project's own domain rather than inventing one.
//
// Deploy:
//   supabase functions deploy donation-redirect --no-verify-jwt

Deno.serve((_req: Request) => {
  const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Thank you!</title>
<style>
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
    background: #F7F2EC;
    color: #2E2A26;
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
    margin: 0;
    padding: 24px;
    text-align: center;
  }
  .card { max-width: 420px; }
  h1 { margin-bottom: 8px; }
  p { line-height: 1.5; color: #5C5551; }
</style>
</head>
<body>
  <div class="card">
    <h1>Thank you!</h1>
    <p>Thanks for supporting this research. You can close this tab and return to the app —
    if your payment went through, it'll be confirmed and show up shortly.</p>
  </div>
</body>
</html>`;

  return new Response(html, {
    headers: { "Content-Type": "text/html; charset=utf-8" },
  });
});
