# Password reset & signup confirmation — custom emails and app links

Two things were wrong before this: the "Reset your password" / "Confirm your
email" messages were Supabase's generic default template, and their links
pointed at `http://localhost:3000` — a leftover dev default — which is why
tapping them on a phone showed "This site can't be reached."

The app code is done: a custom `rootsphere://` URL scheme is registered on
iOS and Android, the reset/signup calls now ask Supabase to redirect there
instead, and a new "Set a new password" screen
(`lib/features/auth/presentation/screens/reset_password_screen.dart`) is
wired into the router to open automatically when that link is tapped. What's
left is entirely Supabase Dashboard configuration — follow this top to
bottom.

## 1. Allow the app's redirect URLs

**Authentication → URL Configuration → Redirect URLs.** Add:

```
rootsphere://reset-password
rootsphere://confirm-email
```

This step isn't optional — even though the app explicitly asks for these via
`redirectTo`/`emailRedirectTo`, Supabase silently ignores any `redirectTo`
that isn't on this allow-list and falls back to the **Site URL** below
instead (this is exactly why the link went to `localhost:3000`: the app
wasn't asking for anything special before, so it always used that default).

While you're on this page, also check **Site URL** — it's a sensible
fallback for any auth flow that doesn't pass an explicit `redirectTo` (e.g.
the web build). If it's still `http://localhost:3000`, that's fine to leave
for now if you don't have a deployed web URL yet, but update it once you do.

## 2. Paste in the branded templates

**Authentication → Emails → Templates.** Two files are already written for
you at `supabase/email-templates/`:

- **Reset Password** → paste the contents of `reset-password.html`
- **Confirm signup** → paste the contents of `confirm-signup.html`

Both match Rootsphere's palette (espresso brown / cream) and personalize the
greeting with `{{ .Data.full_name }}` when available — that's the same
`full_name` metadata key the app already writes on sign-up, so most users
will see "Hi Adaeze," instead of "Hi there,". Don't change the
`{{ .ConfirmationURL }}` variable — that's what Supabase substitutes with
the actual working link.

## 3. Verify

1. `flutter pub get`, then a **full rebuild** — this registers the new
   `rootsphere://` URL scheme with the OS, which (unlike most Dart-only
   changes) requires a fresh install, not a hot reload/restart, to take
   effect. Uninstall the app from the simulator/device first if you're
   testing on one you already had it on.
2. From the sign-in screen, tap **Forgot password?**, enter your email, and
   check the inbox — it should show the new branded template.
3. Tap **Reset password** in the email. On a device with the app installed,
   this should open Rootsphere directly to **"Set a new password"** — not a
   browser, and not `localhost:3000`.
4. Enter a new password and submit — you should land back in the normal
   signed-in app afterward.
5. Repeat for sign-up: create an account with a new email, check for the
   branded "Confirm your email" message, and tap **Confirm email** to verify
   it opens the app rather than a browser.

If the link still opens a browser instead of the app, double check step 1
(fresh install, not a running debug session) — an already-installed build
won't have the new URL scheme registered with iOS/Android until reinstalled.
