# Google & Apple sign-in — production setup

The app code is done (native Google Sign-In on iOS/Android via
`google_sign_in`, native Apple Sign-In on iOS via `sign_in_with_apple`, with a
browser-redirect fallback everywhere else). What's left is entirely
credentials: accounts, IDs, and keys that only you can create, then paste into
`.env`, the Supabase dashboard, and Xcode. Nothing here needs another code
change — follow it top to bottom.

Rootsphere's ids, for reference while you fill in the consoles below:

- **Bundle ID / Android applicationId:** `com.rootsphere.rootsphere`
- **Supabase callback URL:** `https://<your-project-ref>.supabase.co/auth/v1/callback`
  (find `<your-project-ref>` in `SUPABASE_URL` in your `.env`)

---

## 1. Google Cloud Console

### 1.1 Create the project + consent screen (skip if you already have one)

1. Go to <https://console.cloud.google.com/> and create (or select) a project.
2. **APIs & Services → OAuth consent screen.** Choose **External**, fill in
   app name ("Rootsphere"), support email, and your logo if you have one.
   Add the scopes `email`, `profile`, `openid` (these are pre-selected
   defaults). Save.

### 1.2 Create three OAuth Client IDs

Go to **APIs & Services → Credentials → Create Credentials → OAuth client ID**,
and create all three of these:

**a) Web application** (this is the important one — Supabase and both mobile
platforms all authenticate against it):
- Application type: **Web application**
- Name: "Rootsphere - Web (Supabase)"
- Authorized redirect URIs: add your Supabase callback URL from above
- Create → copy the **Client ID** → this is `GOOGLE_WEB_CLIENT_ID`
- Also copy the **Client Secret** — you'll paste it into Supabase, not `.env`

**b) iOS**
- Application type: **iOS**
- Bundle ID: `com.rootsphere.rootsphere`
- Create → copy the **Client ID** → this is `GOOGLE_IOS_CLIENT_ID`
- You do **not** get a secret for this one (iOS clients are public)

**c) Android**
- Application type: **Android**
- Package name: `com.rootsphere.rootsphere`
- SHA-1 certificate fingerprint: run one of these and paste the `SHA1:` line
  it prints:
  ```bash
  # Debug builds (the keystore Flutter auto-creates for local dev):
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android

  # Release builds — use the keystore referenced by android/key.properties:
  keytool -list -v -keystore /path/to/your/release.jks -alias <keyAlias from key.properties>
  ```
  Add **both** fingerprints as separate Android OAuth clients (repeat this
  step once per fingerprint) so Google Sign-In works in both debug and release
  builds.
- This client has no ID/secret you need to copy anywhere — its only purpose is
  telling Google "this package name + signature is allowed to use the Web
  client's `serverClientId`."

### 1.3 Fill in `.env`

```
GOOGLE_WEB_CLIENT_ID=<the Web application client id, ends in .apps.googleusercontent.com>
GOOGLE_IOS_CLIENT_ID=<the iOS client id, ends in .apps.googleusercontent.com>
```

### 1.4 Fill in `ios/Runner/Info.plist`

Find the placeholder already added there:

```xml
<string>com.googleusercontent.apps.YOUR_IOS_CLIENT_ID</string>
```

Replace `YOUR_IOS_CLIENT_ID` with just the numeric/alphanumeric id portion of
your iOS client id (i.e. take `1234-abcd.apps.googleusercontent.com` and use
`com.googleusercontent.apps.1234-abcd`).

---

## 2. Apple Developer Portal

Requires an active Apple Developer Program membership ($99/yr) on
<https://developer.apple.com/account>.

### 2.1 Enable the capability on your App ID

**Certificates, IDs & Profiles → Identifiers →** select your app's identifier
(`com.rootsphere.rootsphere`; create it here if it doesn't exist yet) **→**
check **Sign In with Apple → Save**.

### 2.2 Create a Services ID (needed for Supabase + the Android/web fallback)

1. **Identifiers → + → Services IDs → Continue.**
2. Description: "Rootsphere Sign In", Identifier: e.g.
   `com.rootsphere.rootsphere.signin` (must be **different** from the app's
   own bundle ID) → this is `APPLE_SERVICE_ID`.
3. After creating it, open it again, check **Sign In with Apple → Configure**:
   - Primary App ID: your app's App ID from 2.1
   - Domains: your Supabase project's domain, e.g. `<project-ref>.supabase.co`
   - Return URLs: your Supabase callback URL from the top of this doc
   - Save → Continue → Save.

### 2.3 Create a Sign In with Apple private key

1. **Keys → + →** name it "Rootsphere Sign In Key", check **Sign In with
   Apple → Configure →** select your App ID → Save → Continue → Register.
2. **Download the `.p8` file immediately — Apple only lets you download it
   once.** Store it somewhere safe (not in this git repo).
3. Note the **Key ID** shown on the key's page, and your **Team ID** (top
   right of the Apple Developer site, or **Membership** page).

### 2.4 Fill in `.env`

```
APPLE_SERVICE_ID=com.rootsphere.rootsphere.signin
```

(The private key, Key ID, and Team ID go into Supabase, not `.env` — they're
server-side secrets, same principle as the Anthropic key already documented
in `.env.example`.)

### 2.5 Add the capability in Xcode

Native Sign In with Apple needs an entitlement, which is safest added through
Xcode rather than hand-edited:

1. Open `ios/Runner.xcworkspace` in Xcode (run `flutter pub get` first if you
   haven't already, so CocoaPods has installed `sign_in_with_apple`).
2. Select the **Runner** target → **Signing & Capabilities** tab.
3. **+ Capability → Sign In with Apple.** Xcode creates/updates
   `Runner.entitlements` and wires it into the project automatically.

---

## 3. Supabase Dashboard

**Authentication → Providers.**

### Google
- Toggle it on.
- Client ID: the **Web application** client ID from step 1.2a.
- Client Secret: the **Web application** client secret from step 1.2a.
- Save.

### Apple
- Toggle it on.
- Client ID (Services ID): `com.rootsphere.rootsphere.signin` from step 2.2.
- Team ID: from step 2.3.
- Key ID: from step 2.3.
- Private Key: paste the full contents of the `.p8` file from step 2.3.
- Save.

---

## 4. Verify

1. `flutter pub get`, then rebuild the app from scratch (a hot reload won't
   pick up the new native SDK registration).
2. On a real iOS device or simulator, tap **Apple** on the sign-up screen —
   you should get the native Face ID/Touch ID sheet, not a browser tab.
3. On iOS/Android, tap **Google** — you should get the native account picker
   (One Tap-style on Android, native sheet on iOS), not a browser tab.
4. Check **Profile** afterwards: the name shown should be the one from your
   Google/Apple account, not your email (see the "use name instead of email"
   work already done — `full_name` in Supabase user metadata is what both of
   these flows populate).

If a platform isn't configured yet (e.g. you've only done Google so far),
that platform's button still works via the browser-redirect fallback — you
won't break anything by doing this section-by-section.
