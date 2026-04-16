# Loci — Launch Runbook

End-to-end walkthrough to take Loci from an empty Apple Developer account + fresh Coolify VPS all the way to "submitted for review" on the App Store. This document is the operational companion to `DEPLOYMENT.md` — where that doc covers the *mechanics* of Fastlane Match, code signing, and the CI workflows, this one covers the *content* (App Store metadata, subscription products, descriptions) and the *deployment targets* (Coolify service env vars).

Read them in order:

1. **This doc** — overall sequence, App Store Connect content, Coolify deploy, env var reference
2. **`DEPLOYMENT.md`** — detailed Fastlane Match setup, cert pinning hash extraction, PowerShell secret-loading scripts

---

## Table of Contents

1. [Prerequisites & Accounts to Create](#1-prerequisites--accounts-to-create)
2. [Apple Developer Portal](#2-apple-developer-portal)
3. [App Store Connect — App Record & Metadata](#3-app-store-connect--app-record--metadata)
4. [App Store Connect — Subscriptions (In-App Purchases)](#4-app-store-connect--subscriptions-in-app-purchases)
5. [RevenueCat Dashboard](#5-revenuecat-dashboard)
6. [TelemetryDeck](#6-telemetrydeck)
7. [Sign in with Apple — Backend Credentials](#7-sign-in-with-apple--backend-credentials)
8. [Self-Hosted Supabase on Coolify](#8-self-hosted-supabase-on-coolify)
9. [Edge Functions Sidecar on Coolify](#9-edge-functions-sidecar-on-coolify)
10. [GitHub Actions — Secrets Reference](#10-github-actions--secrets-reference)
11. [Final Pre-Submission Checklist](#11-final-pre-submission-checklist)
12. [Appendix A — App Store Copy Templates](#appendix-a--app-store-copy-templates)
13. [Appendix B — Subscription Localized Metadata](#appendix-b--subscription-localized-metadata)
14. [Appendix C — Privacy Questionnaire Answers](#appendix-c--privacy-questionnaire-answers)

---

## 1. Prerequisites & Accounts to Create

Create these accounts before touching anything else. Free tier unless noted.

| Service | Purpose | Cost |
|---|---|---|
| Apple Developer Program | App signing, App Store submission | $99/year |
| App Store Connect | App listing, TestFlight, subscriptions | Included |
| GitHub | Repo + Actions CI/CD | Free (public) / paid private |
| RevenueCat | Subscription management | Free up to $2.5k MTR |
| TelemetryDeck | Privacy-focused analytics | Free up to 1M signals/mo |
| Anthropic API | Nightly loci analysis (Claude) | Usage-based |
| Contabo VPS | Host Coolify + Supabase + edge functions | ~$7–15/mo |
| Coolify | Self-hosted deploy platform | Free (OSS) |
| Cloudflare | DNS, TLS, Pages for marketing site | Free |
| Domain registrar | `useloci.com` (or your chosen domain) | ~$12/year |

### Domain setup (do this first)

You need at least two subdomains pointing at your Contabo VPS:

- `api.useloci.com` → Supabase Kong gateway
- `edge.useloci.com` → edge functions sidecar

In Cloudflare, create **A records** (proxied or DNS-only — use DNS-only initially so Coolify's Let's Encrypt can validate, then toggle to proxied once TLS is stable).

---

## 2. Apple Developer Portal

### 2.1 Enroll

Go to <https://developer.apple.com/programs/enroll/>. Individual enrollment is faster (~24h); organization enrollment requires a D-U-N-S number and can take 2+ weeks. Note your **Team ID** (10-char alphanumeric, e.g. `A1B2C3D4E5`) from Membership Details — you'll need it everywhere.

### 2.2 Register the App ID

<https://developer.apple.com/account/resources/identifiers/list>

| Field | Value |
|---|---|
| Description | Loci |
| Bundle ID | `com.pearsonmedia.loci` (explicit) |
| Capabilities | Push Notifications, App Groups, Sign in with Apple, Background Modes, Associated Domains (if you add universal links later) |

### 2.3 Register the App Group

<https://developer.apple.com/account/resources/identifiers/list/applicationGroup>

| Field | Value |
|---|---|
| Description | Loci App Group |
| Identifier | `group.com.pearsonmedia.loci` |

Then edit the App ID above and enable this group under App Groups capability.

### 2.4 APNs Auth Key (for push notifications)

<https://developer.apple.com/account/resources/authkeys/list>

1. Keys → `+` → name `Loci APNs Key`, enable **Apple Push Notifications service (APNs)**
2. Download the `.p8` file (**one-time download**). Store in 1Password.
3. Record the **Key ID** (10 chars).

This key is reusable across all your apps.

### 2.5 Sign in with Apple — Services ID

Needed for Supabase Auth to validate Apple tokens server-side.

1. Identifiers → `+` → **Services IDs**
2. Description: `Loci Web Auth`; Identifier: `com.pearsonmedia.loci.signin`
3. Enable **Sign in with Apple**, configure:
   - Primary App ID: `com.pearsonmedia.loci`
   - Domain: `api.useloci.com`
   - Return URL: `https://api.useloci.com/auth/v1/callback`

### 2.6 Sign in with Apple — Private Key

1. Keys → `+` → name `Loci Sign in with Apple`, enable **Sign in with Apple**
2. Configure — primary App ID: `com.pearsonmedia.loci`
3. Download `.p8`. Record Key ID.

You'll use this to mint the `APPLE_SECRET` JWT in [Section 7](#7-sign-in-with-apple--backend-credentials).

### 2.7 App Store Connect API Key

Used by Fastlane + GitHub Actions for TestFlight uploads and releases. **Reusable across all your apps.**

1. <https://appstoreconnect.apple.com/access/integrations/api>
2. `+` → name `GitHub Actions CI`, role **App Manager**
3. Download `.p8`. Record **Key ID** and **Issuer ID** (visible at top of page, UUID format).

### 2.8 Code Signing Certificates (via Fastlane Match)

Follow `DEPLOYMENT.md` §4 — it has the full PowerShell walkthrough. Summary:

1. Create a **private** GitHub repo `loci-certificates` (empty).
2. `cd Loci && fastlane match init` → choose git, paste repo URL.
3. `fastlane match appstore` → generates distribution cert + provisioning profile, commits encrypted to the certs repo.
4. Generate a GitHub PAT with `repo` scope for CI to read the certs repo.

---

## 3. App Store Connect — App Record & Metadata

### 3.1 Create the App

<https://appstoreconnect.apple.com/apps> → `+` → New App

| Field | Value |
|---|---|
| Platform | iOS |
| Name | Loci |
| Primary Language | English (U.S.) |
| Bundle ID | `com.pearsonmedia.loci` |
| SKU | `com.pearsonmedia.loci` |
| User Access | Full Access |

### 3.2 App Information (left nav → App Information)

| Field | Value |
|---|---|
| Subtitle | See Appendix A |
| Category (Primary) | Productivity |
| Category (Secondary) | Lifestyle |
| Content Rights | Does not use third-party content |
| Age Rating | See Appendix C |
| Privacy Policy URL | `https://useloci.com/privacy` |
| Marketing URL (optional) | `https://useloci.com` |

### 3.3 Pricing and Availability

- **Price Tier**: Free (subscriptions gate premium features)
- **Availability**: All territories (or restrict if needed)
- **Pre-Order**: Off for V1

### 3.4 App Privacy

This is the data collection questionnaire. **Answer accurately** — see [Appendix C](#appendix-c--privacy-questionnaire-answers) for exact answers matching Loci's architecture.

### 3.5 Version 1.0 Submission Page

When you create the first submission, you'll fill in:

- **Screenshots**: 6.7" iPhone (1290×2796) required; 6.5" optional but recommended. 3–10 screenshots. Use Xcode Simulator → Device → Screenshot.
- **App Preview Video** (optional but high-converting): 15–30s, portrait, shot at 1080×1920 or 1290×2796.
- **Promotional Text** (170 chars, editable without resubmission) — see Appendix A
- **Description** (4000 chars) — see Appendix A
- **Keywords** (100 chars, comma-separated) — see Appendix A
- **Support URL**: `https://useloci.com/support`
- **Marketing URL**: `https://useloci.com`
- **Copyright**: `© 2026 Pearson Media`
- **Demo Account**: Create a real test account and hand Apple reviewers credentials. Location-based apps get rejected if reviewers can't trigger your core flows.
- **Notes for Reviewer**: Explain that recording requires physical location; include how to test via Simulator location injection.

---

## 4. App Store Connect — Subscriptions (In-App Purchases)

The Loci app has **6 products** across **3 subscription groups**. Create them in order.

### 4.1 Shared Secret (for RevenueCat webhooks)

Before creating products, grab the App-Specific Shared Secret:

1. App Store Connect → your app → **App Information** → scroll to **App-Specific Shared Secret**
2. Generate → copy → save as `APP_STORE_SHARED_SECRET` (you'll paste this into RevenueCat, not GitHub).

### 4.2 Create Subscription Group: **Loci Premium**

Features → Subscriptions → `+` Subscription Group → name `Loci Premium`.

Add two subscriptions in this group (users can only have one active in the group at a time — upgrades/downgrades work automatically):

#### Product: `premium_monthly`

| Field | Value |
|---|---|
| Reference Name | Loci Premium Monthly |
| Product ID | `premium_monthly` |
| Subscription Duration | 1 Month |
| Price | $3.99 USD (Tier 4) |
| Free Trial | 7 days (Introductory Offer → Free Trial) |
| Family Sharing | **Off** (keep Family for the family tier) |
| Localized Display Name | Loci Premium (Monthly) |
| Localized Description | See Appendix B |

#### Product: `premium_yearly`

| Field | Value |
|---|---|
| Reference Name | Loci Premium Yearly |
| Product ID | `premium_yearly` |
| Subscription Duration | 1 Year |
| Price | $29.99 USD (≈ 37% savings) |
| Free Trial | 7 days |
| Family Sharing | Off |
| Localized Display Name | Loci Premium (Yearly) |
| Localized Description | See Appendix B |

### 4.3 Create Subscription Group: **Loci Family**

Features → Subscriptions → `+` Subscription Group → name `Loci Family`.

#### Product: `family_monthly`

| Field | Value |
|---|---|
| Reference Name | Loci Family Monthly |
| Product ID | `family_monthly` |
| Duration | 1 Month |
| Price | $5.99 USD |
| Free Trial | 7 days |
| Family Sharing | **On** (required) |

#### Product: `family_yearly`

| Field | Value |
|---|---|
| Reference Name | Loci Family Yearly |
| Product ID | `family_yearly` |
| Duration | 1 Year |
| Price | $49.99 USD |
| Free Trial | 7 days |
| Family Sharing | On |

### 4.4 Create Non-Renewing / Lifetime Products

Loci has two lifetime SKUs per `RevenueCatConfiguration.swift`. Configure as **Non-Consumable In-App Purchases**, not subscriptions.

Features → In-App Purchases → `+` → Non-Consumable:

#### Product: `lifetime_individual`

| Field | Value |
|---|---|
| Reference Name | Loci Lifetime Individual |
| Product ID | `lifetime_individual` |
| Price | $99.99 USD |
| Family Sharing | Off |

#### Product: `lifetime_family`

| Field | Value |
|---|---|
| Reference Name | Loci Lifetime Family |
| Product ID | `lifetime_family` |
| Price | $149.99 USD |
| Family Sharing | On |

### 4.5 Subscription Review Information

Each subscription needs a screenshot showing the paywall UI and a review note. Reviewers will **reject** the first submission if this is missing. Prepare:

- A screenshot of your paywall displaying this exact product
- Review notes: *"Tap Settings → Upgrade → select plan. Free trial auto-converts after 7 days; cancel in Settings → Subscriptions."*

### 4.6 Product IDs — Source of Truth

These must match Swift code exactly:

```swift
// Loci/Services/RevenueCatConfiguration.swift
// Offering IDs:
//   premium_monthly, premium_yearly
//   family_monthly, family_yearly
//   lifetime_individual, lifetime_family
// Entitlement IDs:
//   premium (granted by: premium_*, lifetime_individual, family_*, lifetime_family)
//   family  (granted by: family_*, lifetime_family only)
```

---

## 5. RevenueCat Dashboard

<https://app.revenuecat.com>

### 5.1 Create Project

- Project Name: `Loci`
- Default Platform: iOS

### 5.2 Add App Store Connect Credentials

Project Settings → Integrations → App Store Connect:

- Paste the **App-Specific Shared Secret** from §4.1
- Paste the **App Store Connect API Key** from §2.7 (upload `.p8`, enter Key ID + Issuer ID)
- Bundle ID: `com.pearsonmedia.loci`

This lets RevenueCat import your subscriptions automatically.

### 5.3 Import Products

Products → Import from App Store Connect. You should see all six product IDs. Confirm import.

### 5.4 Create Entitlements

Entitlements → `+`:

| Entitlement ID | Attached Products |
|---|---|
| `premium` | `premium_monthly`, `premium_yearly`, `lifetime_individual`, `family_monthly`, `family_yearly`, `lifetime_family` |
| `family` | `family_monthly`, `family_yearly`, `lifetime_family` |

Rule: anyone with `family` also has `premium` (family products are attached to both entitlements).

### 5.5 Create Offerings

Offerings → default offering → add packages:

| Package | Duration | Product |
|---|---|---|
| `$rc_monthly` | Monthly | `premium_monthly` |
| `$rc_annual` | Annual | `premium_yearly` |
| `$rc_lifetime` | Lifetime | `lifetime_individual` |
| Custom: `family_monthly` | Monthly | `family_monthly` |
| Custom: `family_yearly` | Annual | `family_yearly` |
| Custom: `family_lifetime` | Lifetime | `lifetime_family` |

### 5.6 Get the iOS API Key

Project Settings → API Keys → copy the **Public iOS SDK Key** (starts `appl_...`). This is `REVENUECAT_API_KEY` for GitHub Actions.

### 5.7 Configure Webhook → Your Edge Functions

Project Settings → Integrations → Webhooks → `+`:

- URL: `https://edge.useloci.com/api/webhook/revenuecat`
- Authorization Header: `Authorization: Bearer <random-long-string-you-generate>`

Generate the shared secret with:

```bash
openssl rand -hex 32
```

Save that value as:
- `REVENUECAT_WEBHOOK_SECRET` in your Coolify edge-functions env
- Paste into the RevenueCat webhook's Authorization header (without the `Bearer ` prefix if your edge function expects just the token — check `edge-functions/src/routes/sync-subscription.ts`)

---

## 6. TelemetryDeck

<https://dashboard.telemetrydeck.com>

1. Sign up with Apple or email
2. Create Organization → App: `Loci iOS`
3. Copy the **App ID** (UUID format, e.g. `550E8400-E29B-41D4-A716-446655440000`)
4. Save as `TELEMETRYDECK_APP_ID` for GitHub Actions

No further config needed in the dashboard — the Swift client sends signals directly.

---

## 7. Sign in with Apple — Backend Credentials

Supabase GoTrue validates Apple tokens by minting a client-secret JWT. You need:

- `APPLE_CLIENT_ID` = `com.pearsonmedia.loci` (the native app bundle ID — NOT the Services ID)
- `APPLE_SECRET` = a JWT you generate and rotate every ~6 months

### Generate APPLE_SECRET

Use the `.p8` from §2.6 and this Node.js snippet (run locally, one-time):

```javascript
// gen-apple-secret.mjs — run: node gen-apple-secret.mjs
import jwt from 'jsonwebtoken';
import fs from 'fs';

const teamId = 'YOUR_TEAM_ID';           // from §2.1
const keyId  = 'YOUR_APPLE_KEY_ID';      // from §2.6
const clientId = 'com.pearsonmedia.loci';
const privateKey = fs.readFileSync('./AuthKey_YOUR_APPLE_KEY_ID.p8');

const token = jwt.sign({}, privateKey, {
  algorithm: 'ES256',
  expiresIn: '180d',  // Apple max is 6 months
  audience: 'https://appleid.apple.com',
  issuer: teamId,
  subject: clientId,
  keyid: keyId,
});
console.log(token);
```

`npm i jsonwebtoken` first. The output is a long JWT — this is `APPLE_SECRET`.

**Set a calendar reminder to rotate every 5 months.**

---

## 8. Self-Hosted Supabase on Coolify

Loci's backend is defined in `backend/docker-compose.yml` — Postgres+PostGIS, GoTrue, PostgREST, Realtime, Storage, Kong gateway, plus the edge-functions sidecar.

### 8.1 Coolify Project Setup

1. SSH into Contabo VPS, install Coolify if not done: <https://coolify.io/docs/installation>
2. In Coolify UI → **New Project** → `Loci Production`
3. Add server (localhost if Coolify is on the VPS itself)

### 8.2 Deploy the Stack

**Option A — via Docker Compose (recommended):**

1. In Coolify → New Resource → **Docker Compose**
2. Source: Public Repository → `https://github.com/pearsonmedia/loci-ios`
3. Base directory: `/backend`
4. Compose file: `docker-compose.yml`
5. Domains:
   - Map `kong` service port 8000 → `https://api.useloci.com`
   - Map `edge-functions` service port 3000 → `https://edge.useloci.com` *(or deploy edge functions as a separate resource — see §9)*

**Option B — Coolify-native Supabase template:**

Coolify ships a Supabase one-click. If you use it, you'll miss the Loci-specific edge-functions service and the PostGIS extension. Stick with Option A.

### 8.3 Environment Variables (Coolify → Environment Variables tab)

Generate the secrets locally first:

```bash
# POSTGRES_PASSWORD
openssl rand -base64 32

# JWT_SECRET (used by GoTrue + PostgREST to sign/verify user JWTs)
openssl rand -base64 64

# REALTIME_ENC_KEY (16 bytes base64)
openssl rand -base64 16

# REALTIME_SECRET_KEY_BASE (64+ chars)
openssl rand -base64 64
```

For `ANON_KEY` and `SERVICE_ROLE_KEY`, generate JWTs signed with `JWT_SECRET`. Supabase provides a generator: <https://supabase.com/docs/guides/self-hosting#api-keys> — paste your `JWT_SECRET`, it spits out both keys (expires 10 years out by default).

#### Full env var table for `backend` Coolify resource

| Variable | Example / Source | Notes |
|---|---|---|
| `POSTGRES_USER` | `postgres` | Keep default |
| `POSTGRES_PASSWORD` | `openssl rand -base64 32` | **Secret** — min 20 chars |
| `POSTGRES_DB` | `loci` | |
| `POSTGRES_PORT` | `5432` | Leave internal; not exposed publicly |
| `JWT_SECRET` | `openssl rand -base64 64` | **Secret** — min 32 chars. Same value used by Auth, REST, Realtime, Storage |
| `ANON_KEY` | JWT signed with `JWT_SECRET`, role `anon` | Public-safe; also goes into GitHub Actions `SUPABASE_ANON_KEY` |
| `SERVICE_ROLE_KEY` | JWT signed with `JWT_SECRET`, role `service_role` | **Never expose to client** — used server-side only |
| `API_EXTERNAL_URL` | `https://api.useloci.com` | Full public URL including https |
| `SITE_URL` | `https://useloci.com` | Redirect after auth |
| `ADDITIONAL_REDIRECT_URLS` | `com.pearsonmedia.loci://auth-callback` | The native app's URL scheme |
| `APPLE_CLIENT_ID` | `com.pearsonmedia.loci` | Bundle ID, not Services ID |
| `APPLE_SECRET` | JWT from §7 | **Secret** — rotate every 5 months |
| `REALTIME_ENC_KEY` | `openssl rand -base64 16` | **Secret** |
| `REALTIME_SECRET_KEY_BASE` | `openssl rand -base64 64` | **Secret** — min 64 chars |
| `AUTH_PORT` | `9999` | Internal |
| `REST_PORT` | `3001` | Internal |
| `STORAGE_PORT` | `5000` | Internal |
| `REALTIME_PORT` | `4000` | Internal |
| `KONG_HTTP_PORT` | `8000` | Public — map to domain |
| `KONG_HTTPS_PORT` | `8443` | Let Coolify handle TLS instead |
| `EDGE_FUNCTIONS_PORT` | `3100` | Internal (or public if edge is in same compose) |
| `ANTHROPIC_API_KEY` | `sk-ant-...` | **Secret** — only if edge-functions share this compose |
| `REVENUECAT_WEBHOOK_SECRET` | from §5.7 | **Secret** |

In Coolify: mark every "Secret" variable with the **Is Secret** toggle so it's masked in logs.

### 8.4 Run Database Migrations

Migrations live in `backend/migrations/` and run automatically on first Postgres boot (mounted at `/docker-entrypoint-initdb.d`). For subsequent migrations (e.g. `009_login_attempts.sql` added later), run them manually:

```bash
# In Coolify, open a shell into the postgres container:
psql -U postgres -d loci -f /docker-entrypoint-initdb.d/009_login_attempts.sql
```

Or use Coolify's DB Terminal → paste migration SQL.

### 8.5 Create the Audio Storage Bucket

Migration `005_storage_bucket.sql` should handle this, but verify:

```sql
-- In Supabase Studio SQL editor or psql:
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('loci-audio', 'loci-audio', false, 10485760, ARRAY['audio/mp4', 'audio/m4a', 'audio/aac'])
ON CONFLICT (id) DO NOTHING;
```

RLS policies for the bucket are in the migration; confirm they're applied.

### 8.6 Configure Apple Auth in GoTrue

If the env vars above are set correctly, GoTrue auto-enables Apple provider. Verify by hitting:

```
GET https://api.useloci.com/auth/v1/settings
```

Should return JSON listing `apple` in `external` providers.

---

## 9. Edge Functions Sidecar on Coolify

The edge-functions service (Node 20 + Hono) can deploy two ways:

- **Bundled**: included in the `backend/docker-compose.yml` as a service. Simpler; everything in one Coolify resource.
- **Separate**: deploy as its own Coolify resource pointed at `/edge-functions`. Better if you iterate on edge code faster than the DB.

Pick one. If separate, create a new Coolify Resource → **Dockerfile** → source repo → base directory `/edge-functions`.

### 9.1 Env Vars for `edge-functions`

| Variable | Example / Source | Notes |
|---|---|---|
| `NODE_ENV` | `production` | Set in Dockerfile; override if needed |
| `PORT` | `3000` | Internal port the container listens on |
| `SUPABASE_URL` | `http://kong:8000` (internal) **or** `https://api.useloci.com` (if on different network) | If bundled: use internal DNS `http://kong:8000` for zero latency |
| `SUPABASE_SERVICE_KEY` | Same value as `SERVICE_ROLE_KEY` from §8.3 | **Secret** |
| `ANTHROPIC_API_KEY` | `sk-ant-...` from <https://console.anthropic.com> | **Secret** — used by `/api/loci/analyze` |
| `REVENUECAT_WEBHOOK_SECRET` | from §5.7 | **Secret** — validates RevenueCat callbacks |
| `EDGE_FUNCTION_VERSION` | `1.0.0` | Surfaced by `/api/health` — bump on deploy |

### 9.2 Public Routes (set up Coolify domain mapping)

All served under `https://edge.useloci.com`:

| Route | Purpose |
|---|---|
| `GET  /api/health` | Liveness probe (use for Coolify health check) |
| `POST /api/auth/verify` | Custom auth validation |
| `POST /api/household/invite` | Create household invite |
| `POST /api/loci/contextual-select` | Pick best loci for current context |
| `POST /api/loci/analyze` | Nightly AI categorization (Anthropic) |
| `POST /api/webhook/revenuecat` | Sync subscription state from RevenueCat |
| `POST /api/digest` | Generate weekly push digest |
| `POST /api/account/delete` | GDPR/App Store account deletion |

### 9.3 Internal Cron Jobs

`node-cron` fires these inside the container — no external scheduler needed:

- `0 2 * * *` — nightly loci analysis (`processUserClusters`)
- `0 10 * * 0` — Sunday 10 AM push digest (`generateDigests`)
- `0 3 * * *` — daily login-attempt cleanup (30-day retention)

Verify by tailing logs in Coolify after 2 AM VPS time.

### 9.4 Health Check

Coolify → edge-functions resource → Health Check:

- Path: `/api/health`
- Expected status: `200`
- Interval: `30s`

---

## 10. GitHub Actions — Secrets Reference

Repo → Settings → Secrets and variables → Actions → New repository secret. Add each of these exactly.

| Secret | Value | Source |
|---|---|---|
| `APPLE_TEAM_ID` | `A1B2C3D4E5` | §2.1 |
| `ASC_KEY_ID` | 10-char key ID | §2.7 |
| `ASC_ISSUER_ID` | UUID | §2.7 |
| `ASC_API_KEY` | Contents of `.p8` file (**whole thing, including BEGIN/END lines**) | §2.7 |
| `MATCH_GIT_URL` | `https://github.com/pearsonmedia/loci-certificates.git` | §2.8 |
| `MATCH_PASSWORD` | Strong passphrase | §2.8 |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `base64(username:PAT)` — see DEPLOYMENT.md §4 | §2.8 |
| `SUPABASE_URL` | `https://api.useloci.com` | §8.3 (same value as `API_EXTERNAL_URL`) |
| `SUPABASE_ANON_KEY` | anon JWT | §8.3 (same value as `ANON_KEY`) |
| `REVENUECAT_API_KEY` | `appl_xxx...` | §5.6 |
| `TELEMETRYDECK_APP_ID` | UUID | §6 |
| `CERT_PIN_HASH` | SPKI SHA-256 base64 for `api.useloci.com` | DEPLOYMENT.md §5.3 |
| `CERT_BACKUP_PIN_HASH` | ISRG Root X1 (pre-filled in DEPLOYMENT.md) | DEPLOYMENT.md §5.3 |
| `SLACK_WEBHOOK_URL` | Optional — incoming webhook URL | Slack app config |

### What each workflow needs

- `ci.yml` (PR builds) — no secrets; just runs `xcodebuild` and SwiftLint
- `deploy.yml` (push to main → TestFlight) — **all** of the above
- `release.yml` (manual → App Store) — **all** of the above + uses `GITHUB_TOKEN` (auto-provided)

### Setting secrets via GH CLI

Instead of clicking through the UI 14 times:

```bash
gh secret set APPLE_TEAM_ID --body "A1B2C3D4E5"
gh secret set ASC_KEY_ID --body "XXXXXXXXXX"
gh secret set ASC_API_KEY < AuthKey_XXXXXXXXXX.p8
# ...etc
```

---

## 11. Final Pre-Submission Checklist

Work top-to-bottom. Each item must be ✅ before hitting *Submit for Review*.

### Backend
- [ ] `https://api.useloci.com/auth/v1/settings` returns 200 with `apple` provider
- [ ] `https://api.useloci.com/rest/v1/` returns 200 with Swagger JSON
- [ ] `https://edge.useloci.com/api/health` returns 200
- [ ] All 10 migrations applied (`\dt` shows users, loci, households, login_attempts, etc.)
- [ ] Storage bucket `loci-audio` exists and is **private**
- [ ] RLS enabled on every table (`SELECT tablename FROM pg_tables WHERE schemaname='public' AND rowsecurity=false;` returns empty)

### iOS build
- [ ] `fastlane match appstore --readonly` succeeds locally
- [ ] `deploy.yml` green on main — build appears in TestFlight within ~20 min
- [ ] Install TestFlight build on physical device; confirm:
  - [ ] Sign in with Apple works → user row appears in Supabase `auth.users`
  - [ ] Record voice note → audio uploads to `loci-audio` bucket
  - [ ] Background geofence triggers while walking past a pinned location
  - [ ] Paywall shows all 6 products with correct localized pricing
  - [ ] Purchase flow (use StoreKit Config sandbox account) completes; RevenueCat dashboard shows the event; webhook fires edge function; user's `premium` entitlement updates in backend

### App Store Connect
- [ ] All 6 subscription/IAP products: **Ready to Submit**
- [ ] Subscription review screenshots uploaded
- [ ] App Privacy questionnaire complete ([Appendix C](#appendix-c--privacy-questionnaire-answers))
- [ ] Age rating set
- [ ] 3+ screenshots per required device size
- [ ] Description, keywords, promo text filled ([Appendix A](#appendix-a--app-store-copy-templates))
- [ ] Privacy policy + support URLs live and reachable
- [ ] Demo account credentials entered in Review Information
- [ ] Reviewer notes explain geofence testing ("Use Simulator → Features → Location → Custom to trigger geofences")
- [ ] Build selected
- [ ] Export compliance answered (ITSAppUsesNonExemptEncryption = false matches `Info.plist`)

### GitHub Actions
- [ ] `release.yml` dry-run: trigger via `workflow_dispatch` with `version=1.0.0`, `whats_new="Initial release"` — should upload a build marked for App Store (not TestFlight) and call `pilot.app_store_build_submit`

---

## Appendix A — App Store Copy Templates

*Drafts — tighten before submission. All lengths verified against App Store limits.*

### Subtitle (30 chars max)

```
Voice notes for the places you love
```

*(35 chars — trim to):*

```
Voice notes tied to places
```

### Promotional Text (170 chars max, editable without resubmission)

```
Capture fleeting thoughts at the places that matter. Loci plays your voice notes back when you return — no folders, no searching, just memory where you left it.
```

### Description (4000 chars max)

```
Loci is the voice-first memory app for the places in your life.

Some thoughts only make sense where you had them. The hardware store where you noticed the cracked step. The trail where a song finally clicked. The parking spot you'll absolutely forget in four hours. Loci pins a voice note to that exact spot — and when you come back, it plays itself.

No folders. No typing. No scrolling through a photo roll hoping the right memory surfaces. Just hold the button, talk, let it go. Your notes come back to you at the door.

• VOICE-FIRST CAPTURE — Record in one tap. Transcription happens on-device via Apple Speech. Your voice never leaves your phone unless you choose to sync.

• PROXIMITY PLAYBACK — Loci watches for the pins you've made. Walk within range of one, get a gentle notification — or open the map and see them all.

• PRIVATE BY DEFAULT — No social feed. No public profiles. No "who else was here." Loci is your memory, for you.

• HOUSEHOLDS — Share a grocery list at the store with your spouse. Leave a note at the cabin for whoever arrives next. Families can opt into a shared space with up to 6 people.

• OFFLINE — Every feature works without a signal. Notes sync when you reconnect.

• APPLE WATCH — Quick-record from your wrist. (Coming soon.)

• WIDGETS — Your most-recent note, one tap from the home screen.

FREE includes 10 saved places, unlimited recordings at those places, on-device transcription, and the full map experience.

PREMIUM ($3.99/month or $29.99/year) unlocks unlimited places, AI-powered auto-categorization, cloud sync across devices, widget support, and full-text search.

FAMILY ($5.99/month or $49.99/year) adds shared households for up to 6 members with Apple Family Sharing.

Privacy matters. Loci stores audio encrypted at rest, transcribes on-device by default, and has no ads or trackers — ever.

---

Terms of Use: https://useloci.com/terms
Privacy Policy: https://useloci.com/privacy
```

### Keywords (100 chars max, comma-separated, no spaces after commas)

```
voice,notes,memory,location,gps,geofence,reminder,journal,household,family,widget,audio,recording
```

*(97 chars — verify character count before submitting.)*

### What's New — Version 1.0

```
Welcome to Loci.

Pin voice notes to places. Let them find you when you come back.

This is the first release. We'd love your feedback — email support@useloci.com.
```

---

## Appendix B — Subscription Localized Metadata

Each subscription in App Store Connect needs a **Display Name** (30 chars) and **Description** (45 chars — *yes, only 45*) per locale. English (U.S.) examples:

| Product | Display Name | Description |
|---|---|---|
| `premium_monthly` | Loci Premium Monthly | Unlimited places, sync, search, widget |
| `premium_yearly` | Loci Premium Yearly | Unlimited places plus 37% off monthly |
| `family_monthly` | Loci Family Monthly | Premium for up to 6 family members |
| `family_yearly` | Loci Family Yearly | Family plan, 30% off monthly price |
| `lifetime_individual` | Loci Lifetime | Premium forever — no subscription |
| `lifetime_family` | Loci Family Lifetime | Family plan forever — no subscription |

---

## Appendix C — Privacy Questionnaire Answers

Based on the current architecture (Apple Speech on-device, self-hosted Supabase, TelemetryDeck, RevenueCat). **Verify each answer against the shipping build** — Apple rejects apps whose privacy labels don't match observed behavior.

### Data Types Collected

| Category | Type | Collected? | Linked to User? | Tracking? | Purpose |
|---|---|---|---|---|---|
| Contact Info | Email | Yes (Apple Sign In) | Yes | No | App Functionality, Account Management |
| Contact Info | Name | Yes (Apple Sign In, optional) | Yes | No | Personalization |
| Location | Precise Location | Yes | Yes | No | App Functionality (core feature) |
| User Content | Audio Data | Yes | Yes | No | App Functionality |
| User Content | Other (transcripts) | Yes | Yes | No | App Functionality |
| Identifiers | User ID | Yes | Yes | No | App Functionality |
| Usage Data | Product Interaction | Yes (TelemetryDeck, anonymous) | No | No | Analytics |
| Diagnostics | Crash Data | Yes (TelemetryDeck) | No | No | App Functionality |
| Purchases | Purchase History | Yes (RevenueCat) | Yes | No | App Functionality |

### Tracking

**Does your app track users?** → **No**. Loci uses no cross-app tracking, no IDFA, no ad networks.

### Data Security

- Encryption in transit: Yes (TLS 1.2+ with cert pinning)
- Encryption at rest: Yes (Supabase Storage + Postgres)
- Privacy policy URL: `https://useloci.com/privacy`

### Age Rating

- **4+** (no objectionable content). If user-generated content (voice notes in shared households) is surfaced to Apple, bump to **12+** due to "Infrequent/Mild Mature/Suggestive Themes" — pick the conservative answer on your first submission.

---

## Where to go when things break

- **TestFlight build "missing compliance"** — `ITSAppUsesNonExemptEncryption=false` in `Info.plist` is already set; re-verify before panicking.
- **Apple Sign In returns error in production** — 95% of the time it's `APPLE_SECRET` expired (6-month max). Regenerate per §7.
- **RevenueCat webhook 401s** — `REVENUECAT_WEBHOOK_SECRET` mismatch between Coolify and RevenueCat Authorization header. Check both.
- **Cert pinning fails in CI but works locally** — `CERT_PIN_HASH` was captured against a different cert than the one Coolify is currently serving. Re-run the extraction in `DEPLOYMENT.md` §5.3.
- **Reviewer rejects IAP** — 90% of the time it's missing subscription review screenshots per product. See §4.5.

For everything else, `DEPLOYMENT.md` has the operational detail and troubleshooting sections.
