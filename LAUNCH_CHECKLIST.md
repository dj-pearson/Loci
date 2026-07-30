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

## 4. Known gaps / hardening items

Open items from the 2026-07 production-readiness audit. Each maps to a
story in `prd.json` (US-185 onward) with the full finding in its `notes`.

This section is generated — run `python3 scripts/sync-launch-checklist.py` after
changing a story's status.

### Resolved (25)

- [x] **US-185** — iOS: restore Xcode project source membership for all 104 Swift files
- [x] **US-186** — iOS: add SPM package dependencies (supabase-swift, RevenueCat, TelemetryDeck)
- [x] **US-187** — iOS: add the widget extension target so the Premium widget actually ships
- [x] **US-188** — iOS: add unit-test target and shared xcscheme so tests and CI can run
- [x] **US-189** — Android: commit the Gradle wrapper so `./gradlew` exists
- [x] **US-190** — Android: define the MAPS_API_KEY manifest placeholder
- [x] **US-191** — Android: generate launcher icon resources
- [x] **US-192** — Android: add androidTest source set and the missing HiltTestRunner
- [x] **US-193** — CI: fix workflow triggers so pipelines actually run on this repository
- [x] **US-194** — Android: implement real sync upload in SyncWorker (currently silent data loss)
- [x] **US-195** — iOS: register for remote notifications and persist the APNs token
- [x] **US-196** — Edge functions: implement real APNs HTTP/2 delivery
- [x] **US-198** — iOS: activate TelemetryDeck instead of the commented-out no-op
- [x] **US-200** — iOS: add PrivacyInfo.xcprivacy privacy manifest
- [x] **US-201** — iOS: ship a real App Store icon set
- [x] **US-202** — iOS: use production aps-environment for Release builds
- [x] **US-203** — Fix deep-link association files for both platforms
- [x] **US-205** — iOS: unit tests for the critical services
- [x] **US-206** — Edge functions: create the vitest suite the test script already assumes
- [x] **US-207** — Backend: automated RLS cross-tenant isolation test
- [x] **US-210** — Remove the stale Loci/ directory and harden secret hygiene
- [x] **US-214** — Backend: idempotent migration runner with applied-version tracking
- [x] **US-215** — Operability: deep health checks, container healthcheck, and structured logs
- [x] **US-217** — Reconcile launch documentation with the audited state of the repository
- [x] **US-218** — Fix RLS infinite recursion that broke every authenticated read of loci

### Still open (9) — resolve or explicitly defer before launch

- [ ] **US-197** — Android: add FCM push so Android has parity with iOS notifications
- [ ] **US-199** — Add crash and error reporting across clients and edge functions
- [ ] **US-204** — Complete App Store and Play Store listing metadata
- [ ] **US-208** — Android: unit tests for sync, geofencing, billing, and persistence
- [ ] **US-209** — Android: instrumented smoke test for the core record-to-list flow
- [ ] **US-211** — iOS: localization catalog and migration of hardcoded strings
- [ ] **US-212** — Android: biometric app lock for parity with iOS
- [ ] **US-213** — Android: Glance widget for parity with the iOS Premium widget
- [ ] **US-216** — Android: AI categorization and security audit log parity

> **What this audit found.** The previous version of this section listed two open
> gaps and implied everything else was shippable. In fact neither app could build
> and the backend's core read path did not work:
>
> - **iOS could not compile.** 72 of 104 Swift files had no target membership, and
>   the project declared zero SPM packages while sources imported `Supabase` and
>   `RevenueCat`. There was no widget target, no test target, and no shared scheme —
>   so every `xcodebuild -scheme Lociate` call in CI and Fastlane had nothing to
>   resolve. (US-185–188)
> - **Android could not configure.** `settings.gradle.kts` used `dependencyResolution`
>   instead of `dependencyResolutionManagement`, so Gradle could not evaluate the
>   settings file at all. There was no Gradle wrapper, no launcher icons, and the
>   `MAPS_API_KEY` manifest placeholder was undefined. (US-189–192)
> - **Every authenticated read of `loci` failed.** The `household_members` SELECT
>   policy filtered that table by a subquery over itself, and `loci_select_shared`
>   depends on it — PostgreSQL aborted with "infinite recursion detected in policy".
>   (US-218)
> - **CI had never run.** Every workflow triggered on `develop`/`main`; this
>   repository's default branch is `master`. (US-193)
> - **Android sync discarded data.** `SyncWorker` marked every pending locus SYNCED
>   without uploading anything. (US-194)
> - **Push was unwired end to end.** Nothing on iOS ever called
>   `registerForRemoteNotifications()`, and the server-side sender was a
>   `console.log`. (US-195, US-196)
>
> Treat "the checklist says done" as a claim to verify, not evidence.

---

## 5. Backend — Supabase + edge functions (**ℹ️ Manual** on Coolify)

See LAUNCH_RUNBOOK.md §8–9 for the full Coolify walkthrough. Checklist summary:

- [ ] **⚠️** Coolify VPS provisioned (Contabo or equivalent), DNS pointed at it
- [ ] **⚠️** Supabase stack deployed (Postgres + GoTrue + PostgREST + Storage + Kong)
- [ ] **⚠️** All migrations applied via `scripts/apply-migrations.sh` (US-214 — tracks each file's checksum in `public.schema_migrations`, applies only what is pending, and is safe to re-run). Use `--dry-run` first, and `--baseline` on a database provisioned before the runner existed.
- [ ] **⚠️** `010_fix_rls_recursion.sql` applied — without it every authenticated read of `loci` fails with "infinite recursion detected in policy" (US-218)
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

---

## 5b. Observability (US-215)

- [ ] **⚠️** Uptime monitor pointed at `https://<EDGE_DOMAIN>/api/health` — expects
      HTTP **200**. The endpoint returns **503** when Postgres, Storage, Auth, or
      Redis is unreachable, so a plain "is it up" check on the root domain would
      miss a degraded backend entirely.
      - Check interval: 60s, alert after 2 consecutive failures
      - Suggested free options: Better Stack, Healthchecks.io, UptimeRobot
- [ ] Alert routed somewhere a human sees out of hours (not just email)
- [ ] Coolify log drain configured, or `docker logs` retention raised — every log
      line is single-line JSON with `level`, `msg`, `time`, `service`, and a
      `requestId` that is echoed to clients in `X-Request-Id`, so a user-reported
      failure can be traced to its exact request
- [ ] `LOG_LEVEL` set (`info` in production; `debug` only while diagnosing)
- [ ] Confirm the container healthcheck passes after deploy:
      `docker compose -f docker-compose.prod.yml ps` shows edge-functions as
      `healthy`
- [ ] Confirm cron outcomes appear in logs — `{"msg":"cron completed","job":"..."}`
      for `analyze-loci` (02:00), `push-digest` (Sun 10:00), and
      `cleanup-login-attempts` (03:00)

> The compose healthcheck previously ran `curl -f http://localhost:3000/health`,
> which failed on two counts: `node:20-alpine` ships no curl, and the route is
> `/api/health`. The container was permanently unhealthy, so with `restart: always`
> it restart-looped and Traefik never routed to it. Now `node healthcheck.mjs`,
> declared in both the Dockerfile and compose.

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

---

## 9b. Deep links — verification (**ℹ️ Manual**, US-203)

The AASA file previously contained the literal placeholder `TEAM_ID`, and no
`assetlinks.json` existed at all, so universal links were broken on iOS and absent
on Android. Both files are now generated at build time by
`web/scripts/generate-association-files.mjs`.

- [ ] **⚠️** `APPLE_TEAM_ID` set in the Cloudflare Pages project (build fails
      without it in production, by design)
- [ ] **⚠️** `ANDROID_SHA256_CERT_FP` set to the **Play App Signing** SHA-256
      fingerprint — not the local upload keystore, since Play re-signs the bundle
      (Play Console → Setup → App signing)
- [ ] Verify both files are served as `application/json` with no redirect:
      ```
      curl -sI https://lociate.app/.well-known/apple-app-site-association | grep -i content-type
      curl -sI https://lociate.app/.well-known/assetlinks.json | grep -i content-type
      ```
      (`web/public/_headers` sets this; Cloudflare Pages honours it.)
- [ ] iOS: confirm Apple's CDN has picked up the file —
      `curl -s "https://app-site-association.cdn-apple.com/a/v1/lociate.app"`
- [ ] iOS: on device, tapping `https://lociate.app/locus/<uuid>` opens the app
      rather than Safari
- [ ] Android: `adb shell pm get-app-links app.lociate.android` reports
      `verified` for both hosts
- [ ] Custom scheme still works from the widget:
      `xcrun simctl openurl booted "lociate://locus/<uuid>"` and
      `adb shell am start -a android.intent.action.VIEW -d "lociate://locus/<uuid>"`
- [ ] Associated Domains capability enabled on the App ID (§2) — without it iOS
      never fetches the AASA file

## 10. Go/no-go gate

Before flipping the App Store / Play Store listings to **Ready for Review**:

1. Every box in §1, §2, §3, §5, §6, §7, §7b, §9b is ticked.
2. **CI is green on `master`** — not merely configured. Branch protection (§7b) must
   list the checks as required; until then CI runs but nothing enforces it. Prior to
   US-193 no workflow had ever executed against this repository, so a green badge is
   only meaningful after the trigger fix.
3. Every item in §4 is resolved or explicitly deferred with a tracked issue, and the
   deferral is recorded in `prd.json`.
4. `scripts/apply-migrations.sh --status` on the production database lists every
   migration through `010_fix_rls_recursion.sql`. Without 010, every authenticated
   read of `loci` fails.
5. A real device has been verified end to end on both platforms: record → save →
   leave → return → proximity notification → open from the notification.

**Tier-parity caveat.** The pricing table in `CLAUDE.md` advertises the widget, AI
categorization, and biometric lock. On Android those are US-212, US-213, and US-216,
all still open — so either ship them, or adjust the Play Store listing and the
Android paywall copy so Android users are not sold features the build does not have.
