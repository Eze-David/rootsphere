# Rootsphere

Cross-platform (**iOS · Android · Web**) genealogy & family-history platform built
with Flutter and Supabase. Build interactive family trees, attach historical
records, get AI-powered record hints, and collaborate on community record
gathering.

> Status: **Phase 1 — Foundation** (scaffold, design system, auth, routing, CI).
> See the Developer Brief for the full 6-phase roadmap.

## Tech stack

| Layer | Choice |
| --- | --- |
| UI | Flutter 3.x (Material 3) |
| State | Riverpod 3 |
| Navigation | go_router (with auth redirect guards) |
| Backend | Supabase (Auth, Postgres, Storage, Realtime) |
| Models | Freezed |
| Config | envied (compile-time env constants) |
| Fonts | Playfair Display (display) + DM Sans (body) |

## Architecture

Clean Architecture, feature-first:

```
lib/
  core/      theme, routing, config, error handling
  features/  auth, profile, (tree, persons, records, hints, collab — later phases)
             each split into data / domain / presentation
  shared/    reusable widgets & utils
```

## Getting started

1. Install Flutter 3.22+ and Dart 3.4+.
2. Copy env and add your Supabase credentials:
   ```bash
   cp .env.example .env
   # edit .env -> SUPABASE_URL, SUPABASE_ANON_KEY
   ```
3. Install deps and generate code:
   ```bash
   flutter pub get
   dart run build_runner build
   ```
4. Run:
   ```bash
   flutter run -d chrome   # web
   flutter run             # connected device
   ```

> The app boots even without Supabase credentials so the UI/design system can be
> reviewed; auth/network calls will fail until real credentials are supplied.

## Quality

```bash
flutter analyze
flutter test
```

CI (`.github/workflows/ci.yaml`) runs format check, analyze, tests, and a web
build on every push/PR. Set `SUPABASE_URL` and `SUPABASE_ANON_KEY` as repo
secrets.
