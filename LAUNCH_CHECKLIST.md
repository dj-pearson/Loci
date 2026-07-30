# Lociate — Launch Checklist

A tickable operational checklist for every portal, console, and secret that must be configured before iOS + Android can ship. Each item maps to a specific env var, GitHub secret, or dashboard setting.

**Companion docs** (read first if you haven't):
- `LAUNCH_RUNBOOK.md` — narrative walkthrough, App Store copy, Coolify deploy
- `DEPLOYMENT.md` — Fastlane Match, cert pinning, PowerShell secret loaders

This file is the **skimmable summary**. If an item is in `LAUNCH_RUNBOOK.md`, the link is here but the body is there.

---

## Legend

- [ ] Not done
- [x] Done
- **⚠️ Blocker** — app cannot build or run without this
- **🔶 Feature-gated** — app runs but a feature is disabled
- **ℹ️ Manual** — happens outside the repo (portal/console/dashboard)

---

## 1. Shared secrets (both platforms + backend)

| Secret | Where it lives | Source | Used by |
|---|---|---|---|
| `SUPABASE_URL` | GH Actions secret, `BuildSecrets.swift`, `android/local.properties`, `backend/.env` | Supabase self-host (Coolify) | iOS, Android, edge fns |
| `SUPABASE_ANON_KEY` | same | Supabase dashboard | iOS, Android |
| `SUPABASE_SERVICE_ROLE_KEY` | `backend/.env` + edge fn env only — **never** in a client | Supabase dashboard | edge fns only |
| `JWT_SECRET` | `backend/.env` | Generated (`openssl rand -hex 32`) during Supabase init | Supabase, edge fns |
| `REQUEST_SIGNING_KEY` | iOS `BuildSecrets.swift`, Android `local.properties` (**TODO, see §4**), `backend/.env` | Generate: `openssl rand -hex 32` | iOS, Android, edge fns |
| `CERT_PIN_HASH` | iOS `BuildSecrets.swift`, Android `CertificatePinning.kt` (**TODO, see §4**) | Extract from prod TLS cert (see §9) | iOS, Android |
| `CERT_BACKUP_PIN_HASH` | same (optional; defaults to Let's Encrypt ISRG Root X1 intermediate) | Intermediate CA cert | iOS, Android |

- [ ] **⚠️** All values above generated and stored in a password manager / secrets vault
- [ ] All values written into GitHub Actions secrets (Repository → Settings → Secrets → Actions)

---

## 2. iOS — Apple ecosystem (**ℹ️ Manual**, see LAUNCH_RUNBOOK.md §2–4)

- [ ] **⚠️** Apple Developer Program membership active ($99/yr)
- [ ] **⚠️** App ID `app.lociate.ios` registered with capabilities: Sign In With Apple, Push, App Groups, Associated Domains
- [ ] **⚠️** Services ID created for Sign In With Apple (needed for backend `APPLE_SECRET`)
- [ ] **⚠️** APNs Auth Key (`.p8`) generated and downloaded (used for push via edge fns)
- [ ] **⚠️** Fastlane Match private repo created; `MATCH_GIT_URL`, `MATCH_PASSWORD` set as GH secrets
- [ ] **⚠️** App Store Connect API Key (`.p8` + key ID + issuer ID) → GH secrets `APP_STORE_CONNECT_API_KEY_*`
- [ ] App record created in App Store Connect with Bundle ID `app.lociate.ios`
- [ ] Subscription group + two products created: Premium (`app.lociate.premium.monthly`), Family (`app.lociate.family.monthly`)
- [ ] 🔶 TestFlight internal testing group configured
- [ ] App privacy questionnaire answered (see LAUNCH_RUNBOOK.md Appendix C)

---

## 3. Android — Google ecosystem (**ℹ️ Manual**)

- [ ] **⚠️** Google Play Developer account created ($25 one-time)
- [ ] **⚠️** App created in Play Console with package name `app.lociate.android`
- [ ] **⚠️** Upload keystore generated locally:
      ```
      keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA \
        -keysize 2048 -validity 10000 -alias upload
      ```
      then base64-encode and store as GH secret `ANDROID_KEYSTORE_BASE64`; also set
      `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- [ ] **⚠️** Google Play service account JSON created (for API uploads from CI) → GH secret `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
- [ ] **⚠️** Google Maps SDK for Android API key created in Google Cloud Console, restricted to package name + SHA-1 fingerprint → GH secret `MAPS_API_KEY`
- [ ] **⚠️** Google Play Billing products configured matching iOS SKUs (`app.lociate.premium.monthly`, `app.lociate.family.monthly`)
- [ ] App signing by Google Play enabled (Play App Signing)
- [ ] 🔶 Internal testing track populated with tester emails

---

## 4. Known gaps / hardening items still to resolve

These are open items discovered in the codebase audit — resolved items are checked, open items remain.

- [x] **android-release.yml env-var flow** — workflow now runs `scripts/generate-secrets.sh --android` before `./gradlew bundleRelease` so `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `MAPS_API_KEY`, `CERT_PIN_HASH`, `CERT_BACKUP_PIN_HASH`, `REQUEST_SIGNING_KEY` are written to `local.properties` and read via `project.findProperty()`.
- [x] **Android cert pins wired through BuildConfig** — `CertificatePinning.kt` reads `BuildConfig.CERT_PIN_HASH` / `CERT_BACKUP_PIN_HASH`; empty values produce a no-op pinner (matches iOS behaviour). Pinner is attached to the Supabase Ktor-OkHttp engine (see below) so every outbound Supabase request is pinned.
- [x] **Android `REQUEST_SIGNING_KEY` plumbed** — `BuildConfig.REQUEST_SIGNING_KEY` is populated from `local.properties`; `RequestSigningInterceptor.kt` mirrors iOS's `HMAC-SHA256(METHOD\nPATH\nTIMESTAMP\nBODY_SHA256)` algorithm and is installed on the Supabase Ktor-OkHttp engine.
- [x] **`backend/docker-compose.prod.yml`** — committed. Differs from dev: no port publishing for internal services, required vars fail loudly (`${VAR:?required}` syntax), `restart: always`, Traefik labels on Kong + edge-functions keyed off `KONG_DOMAIN` / `EDGE_DOMAIN`, migrations no longer bind-mounted (apply manually on first deploy — see the header of the compose file).
- [x] **Ktor engine switch to OkHttp** — `ktor-client-android` swapped for `ktor-client-okhttp:3.0.3`, explicit `okhttp:4.12.0` added, `SupabaseClientProvider` now configures the engine via `httpEngine = OkHttp.create { preconfigured = OkHttpClient.Builder().certificatePinner(...).addInterceptor(RequestSigningInterceptor()).build() }`. This activates the pinner and signer above.
- [ ] **Test coverage** — critical services (`SyncService`, `GeofenceManager`, `AuthService`, tier enforcement) need at minimum unit tests before external beta. Edge functions need smoke tests for `sync-subscription` webhook signature + `account-delete` idempotency.
- [ ] **RLS cross-tenant isolation test** — no automated proof that a user in household A cannot read loci from household B. Add a pgTAP or integration test before any external users.

---

## 5. Backend — Supabase + edge functions (**ℹ️ Manual** on Coolify)

See LAUNCH_RUNBOOK.md §8–9 for the full Coolify walkthrough. Checklist summary:

- [ ] **⚠️** Coolify VPS provisioned (Contabo or equivalent), DNS pointed at it
- [ ] **⚠️** Supabase stack deployed (Postgres + GoTrue + PostgREST + Storage + Kong)
- [ ] **⚠️** All migrations applied (`backend/migrations/001_*` through `009_*`)
- [ ] **⚠️** PostGIS extension enabled (`CREATE EXTENSION postgis;`)
- [ ] **⚠️** Audio storage bucket created (`005_storage_bucket.sql` handles this on fresh DB)
- [ ] **⚠️** Edge functions sidecar deployed with `backend/.env` populated:
  - `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`
  - `ANTHROPIC_API_KEY` (for `analyze-loci`)
  - `REVENUECAT_WEBHOOK_SECRET`
  - `APPLE_SECRET` (Sign In With Apple client secret JWT)
  - `REQUEST_SIGNING_KEY` (shared with mobile)
- [ ] **⚠️** TLS cert issued (Let's Encrypt via Coolify) — needed before extracting pins in §9
- [ ] 🔶 Redis container healthy (used by `auth-rate-limit` middleware persistence)
- [ ] RevenueCat webhook endpoint registered in RevenueCat dashboard → `https://<edge-fns>/webhooks/revenuecat`

---

## 6. Third-party dashboards (**ℹ️ Manual**)

- [ ] **RevenueCat** — project created, Apple + Google entitlements + offerings configured; **Apple API key** copied into GH secret `REVENUECAT_API_KEY`. (LAUNCH_RUNBOOK.md §5)
- [ ] **TelemetryDeck** — app created; App ID → GH secret `TELEMETRYDECK_APP_ID`. (LAUNCH_RUNBOOK.md §6)
- [ ] **Anthropic** — API key for `analyze-loci` edge function → `backend/.env` `ANTHROPIC_API_KEY`
- [ ] **Cloudflare Pages** — `web/` project connected to repo for marketing site auto-deploy

---

## 7. GitHub Actions secrets — full reference

Confirm all of the following are set under Repo → Settings → Secrets and variables → Actions.

**iOS (release.yml, testflight.yml)**
- [ ] `MATCH_GIT_URL`, `MATCH_PASSWORD`, `MATCH_GIT_BASIC_AUTHORIZATION`
- [ ] `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_CONTENT`
- [ ] `APPLE_TEAM_ID`
- [ ] `SUPABASE_URL`, `SUPABASE_ANON_KEY`
- [ ] `REVENUECAT_API_KEY`
- [ ] `TELEMETRYDECK_APP_ID`
- [ ] `CERT_PIN_HASH` (optionally `CERT_BACKUP_PIN_HASH`)
- [ ] `REQUEST_SIGNING_KEY`

**Android (android-release.yml)**
- [ ] `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
- [ ] `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`
- [ ] `SUPABASE_URL`, `SUPABASE_ANON_KEY` (shared with iOS)
- [ ] `MAPS_API_KEY`
- [ ] `CERT_PIN_HASH`, `CERT_BACKUP_PIN_HASH` (shared with iOS; optional — empty disables pinning)
- [ ] `REQUEST_SIGNING_KEY` (shared with iOS + edge fns; optional — empty disables signing)

**Backend / infra**
- [ ] `ANTHROPIC_API_KEY`
- [ ] `REVENUECAT_WEBHOOK_SECRET`
- [ ] `APPLE_SECRET`
- [ ] Any Coolify deploy tokens used by `deploy.yml`

---

---

## 7b. Branch protection — required checks (**ℹ️ Manual**)

Until this is configured, CI runs but nothing enforces it. Repo → Settings →
Branches → add a rule for `master`:

- [ ] Require a pull request before merging
- [ ] Require status checks to pass, with these checks selected (all from `ci.yml`
      and `android-ci.yml`, which trigger on `pull_request` into `master`):
  - [ ] `Xcode Project Up To Date` — fails if `project.pbxproj` drifts from the
        source tree (this drift is what made the app uncompilable; see US-185)
  - [ ] `SwiftLint`
  - [ ] `Build (iOS Simulator)`
  - [ ] `Unit Tests`
  - [ ] `Edge Functions — Typecheck & Test`
  - [ ] `Backend — Migrations & RLS Isolation` — the cross-tenant isolation proof
  - [ ] `Secret Scan`
  - [ ] `Build Marketing Site`
  - [ ] `Lint & Static Analysis` (Android)
  - [ ] `Build & Test` (Android)
- [ ] Require branches to be up to date before merging
- [ ] Do not allow bypassing the above settings

> Workflow triggers previously referenced `develop` and `main`, neither of which
> exists in this repository — its default branch is `master` — so no workflow had
> ever gated a change. Fixed in US-193.

## 8. Local dev quickstart (for new contributors)

```bash
# iOS
cp Lociate/Configuration/BuildSecrets.swift.example Lociate/Configuration/BuildSecrets.swift
# then edit BuildSecrets.swift with local Supabase URL + anon key

# Android
cp android/local.properties.example android/local.properties
# then edit local.properties with SUPABASE_URL, SUPABASE_ANON_KEY, MAPS_API_KEY

# Backend
cp backend/.env.example backend/.env
# populate, then:
cd backend && docker compose up -d
```

To regenerate secret files from env vars (mirrors what CI does):

```bash
export SUPABASE_URL=... SUPABASE_ANON_KEY=... REVENUECAT_API_KEY=... \
       TELEMETRYDECK_APP_ID=... CERT_PIN_HASH=... MAPS_API_KEY=...
bash scripts/generate-secrets.sh --all
```

---

## 9. Extracting certificate pin hashes (reference)

Run against your **production** Supabase host after TLS is issued:

```bash
HOST="your-project.supabase.co"   # or your self-hosted domain
openssl s_client -connect "$HOST:443" -servername "$HOST" </dev/null 2>/dev/null \
  | openssl x509 -pubkey -noout \
  | openssl pkey -pubin -outform DER \
  | openssl dgst -sha256 -binary \
  | base64
```

Use that value for `CERT_PIN_HASH`. For the backup pin, re-run against the intermediate CA cert (export the chain with `openssl s_client -showcerts`).

---

## 10. Go/no-go gate

Before flipping the App Store / Play Store listings to **Ready for Review**, every box in §1, §2, §3, §5, §6, §7 must be ticked, and all items in §4 must be either resolved or explicitly deferred with a tracked issue.
