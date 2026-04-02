# Loci — iOS Deployment Guide

Complete guide for setting up CI/CD, code signing, and deploying Loci to the App Store via GitHub Actions.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Apple Developer Account Setup](#apple-developer-account-setup)
3. [App Store Connect API Key](#app-store-connect-api-key)
4. [Code Signing with Fastlane Match](#code-signing-with-fastlane-match)
5. [Service Configuration](#service-configuration)
6. [GitHub Secrets Reference](#github-secrets-reference)
7. [Local Development Setup](#local-development-setup)
8. [CI/CD Workflows](#cicd-workflows)
9. [First App Store Submission Checklist](#first-app-store-submission-checklist)
10. [Shared Secrets Across Apps](#shared-secrets-across-apps)

---

## Prerequisites

- Apple Developer Program membership ($99/year)
- GitHub repository with Actions enabled
- PowerShell 7+ (Windows) or Terminal (macOS)
- Ruby installed (for Fastlane): `winget install RubyInstallerTeam.Ruby.3.2` or `brew install ruby`
- Fastlane: `gem install fastlane`
- OpenSSL (for certificate pinning): comes with Git for Windows

---

## Apple Developer Account Setup

### 1. Register App ID

Go to [Apple Developer > Identifiers](https://developer.apple.com/account/resources/identifiers/list) and create:

| Field | Value |
|-------|-------|
| Description | Loci |
| Bundle ID | `com.pearsonmedia.loci` (Explicit) |
| Capabilities | Push Notifications, App Groups (`group.com.pearsonmedia.loci`) |

### 2. Create App in App Store Connect

Go to [App Store Connect > My Apps](https://appstoreconnect.apple.com/apps) > "+" > New App:

| Field | Value |
|-------|-------|
| Platform | iOS |
| Name | Loci |
| Primary Language | English (U.S.) |
| Bundle ID | `com.pearsonmedia.loci` |
| SKU | `com.pearsonmedia.loci` |

### 3. Find Your Team ID

```powershell
# Your Team ID is visible at:
# https://developer.apple.com/account -> Membership Details -> Team ID
# It's a 10-character alphanumeric string like "A1B2C3D4E5"
```

---

## App Store Connect API Key

This key is used by Fastlane and GitHub Actions to authenticate with App Store Connect. **This is reusable across all your apps.**

### Generate the Key

1. Go to [App Store Connect > Users and Access > Integrations > App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api)
2. Click "+" to create a new key
3. Name: `GitHub Actions CI` (or similar)
4. Access: **App Manager** (minimum for TestFlight + App Store submission)
5. Download the `.p8` file — **you can only download it once**

### Extract the Values

```powershell
# After downloading the .p8 file (e.g., AuthKey_ABC123DEF4.p8):

# 1. Key ID — from the filename or the API keys page
$ASC_KEY_ID = "ABC123DEF4"    # Replace with your Key ID

# 2. Issuer ID — shown at the top of the API keys page
$ASC_ISSUER_ID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"    # Replace with your Issuer ID

# 3. Base64-encode the .p8 file content for storage as a GitHub secret
$ASC_API_KEY = [Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_ABC123DEF4.p8"))
Write-Host "ASC_API_KEY=$ASC_API_KEY"
```

---

## Code Signing with Fastlane Match

Match stores encrypted signing certificates and provisioning profiles in a private Git repo.

### 1. Create the Match Repo

```powershell
# Create a PRIVATE repo for certificates (reusable across all apps)
gh repo create pearsonmedia/ios-certificates --private --clone=false

# The repo URL:
$MATCH_GIT_URL = "https://github.com/pearsonmedia/ios-certificates.git"
```

### 2. Generate a GitHub PAT for Match

Match needs to clone the certificates repo during CI. Create a Personal Access Token:

1. Go to [GitHub > Settings > Developer settings > Personal access tokens > Fine-grained tokens](https://github.com/settings/tokens?type=beta)
2. Name: `fastlane-match`
3. Repository access: Select `pearsonmedia/ios-certificates`
4. Permissions: Contents (Read and Write)
5. Generate and copy the token

```powershell
# Create the basic auth string Match expects (username:token, base64-encoded)
$GH_USERNAME = "pearsonmedia"    # Your GitHub username
$GH_PAT = "github_pat_xxxx"     # The token you just created
$MATCH_GIT_BASIC_AUTHORIZATION = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes("${GH_USERNAME}:${GH_PAT}")
)
Write-Host "MATCH_GIT_BASIC_AUTHORIZATION=$MATCH_GIT_BASIC_AUTHORIZATION"
```

### 3. Initialize Match (Run Once, from macOS)

This must be done from a Mac with Xcode installed:

```bash
# From the Loci/Loci/ directory (where Fastfile lives)
cd Loci

# Set environment variables
export MATCH_GIT_URL="https://github.com/pearsonmedia/ios-certificates.git"
export FASTLANE_TEAM_ID="YOUR_TEAM_ID"

# Generate App Store distribution certificate + provisioning profile
fastlane match appstore

# You'll be prompted to create an encryption passphrase — save it as MATCH_PASSWORD
```

### 4. Set Match Password

```powershell
# The passphrase you chose during `fastlane match init`
# Store securely — you'll need this for every CI run
$MATCH_PASSWORD = "your-match-encryption-passphrase"
```

### Adding Another App to Match

When you create a new app, just run match again with the new bundle ID:

```bash
fastlane match appstore --app_identifier "com.pearsonmedia.newapp"
```

The same certificates repo, PAT, and password work for all your apps.

---

## Service Configuration

### Supabase (Self-Hosted)

Your Supabase instance provides the URL and anon key.

```powershell
# From your Coolify/Docker deployment:
$SUPABASE_URL = "https://supabase.yourdomain.com"

# The anon key is in your Supabase .env or docker-compose.yml
# Look for ANON_KEY in your backend/.env file
$SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIs..."    # Your JWT anon key
```

### RevenueCat

1. Go to [RevenueCat Dashboard](https://app.revenuecat.com) > Your Project > API Keys
2. Copy the **Apple** public API key (starts with `appl_`)

```powershell
$REVENUECAT_API_KEY = "appl_xxxxxxxxxxxxxxxx"
```

**Reusable?** No — each app gets its own RevenueCat project and API key.

### TelemetryDeck

1. Go to [TelemetryDeck Dashboard](https://dashboard.telemetrydeck.com) > App > Settings
2. Copy the App ID (UUID format)

```powershell
$TELEMETRYDECK_APP_ID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

**Reusable?** No — each app gets its own TelemetryDeck app ID.

### Certificate Pinning Hash

Get the SPKI SHA-256 hash of your Supabase server's TLS certificate:

```powershell
# Using OpenSSL (available in Git Bash on Windows):
# Replace "supabase.yourdomain.com" with your actual domain
bash -c 'openssl s_client -connect supabase.yourdomain.com:443 -servername supabase.yourdomain.com 2>/dev/null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | base64'

# Or in pure PowerShell (requires OpenSSL in PATH):
$domain = "supabase.yourdomain.com"
$hash = echo "" | openssl s_client -connect "${domain}:443" -servername $domain 2>$null | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64
Write-Host "CERT_PIN_HASH=$hash"
```

The backup pin defaults to Let's Encrypt ISRG Root X1. Override only if your server uses a different CA.

---

## GitHub Secrets Reference

Go to your repo: **Settings > Secrets and variables > Actions > New repository secret**

### All Secrets for Loci

| Secret Name | Description | Shared? | How to Get |
|------------|-------------|---------|------------|
| `APPLE_TEAM_ID` | Apple Developer Team ID (10 chars) | Yes | [Developer Account](https://developer.apple.com/account) > Membership |
| `ASC_KEY_ID` | App Store Connect API Key ID | Yes | [ASC API Keys](https://appstoreconnect.apple.com/access/integrations/api) |
| `ASC_ISSUER_ID` | App Store Connect Issuer ID | Yes | Same page as above |
| `ASC_API_KEY` | Base64-encoded .p8 file content | Yes | See [API Key section](#app-store-connect-api-key) |
| `MATCH_GIT_URL` | Private certificates repo URL | Yes | `https://github.com/pearsonmedia/ios-certificates.git` |
| `MATCH_PASSWORD` | Match encryption passphrase | Yes | Set during `fastlane match` init |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Base64 `user:pat` for cert repo | Yes | See [Match section](#2-generate-a-github-pat-for-match) |
| `SUPABASE_URL` | Production Supabase URL | No | Your Coolify deployment |
| `SUPABASE_ANON_KEY` | Supabase anonymous JWT key | No | Your `backend/.env` |
| `REVENUECAT_API_KEY` | RevenueCat Apple API key | No | [RevenueCat Dashboard](https://app.revenuecat.com) |
| `TELEMETRYDECK_APP_ID` | TelemetryDeck app UUID | No | [TelemetryDeck Dashboard](https://dashboard.telemetrydeck.com) |
| `CERT_PIN_HASH` | SPKI SHA-256 base64 hash | No | See [Certificate Pinning](#certificate-pinning-hash) |
| `CERT_BACKUP_PIN_HASH` | Backup CA pin hash (optional) | Depends | Defaults to Let's Encrypt |
| `SLACK_WEBHOOK_URL` | Slack notification webhook (optional) | Yes | [Slack API](https://api.slack.com/messaging/webhooks) |

### Quick-Set All Secrets via PowerShell

```powershell
# Navigate to your repo directory first
cd C:\Users\pears\Documents\Loci\Loci

# ─── SHARED SECRETS (reuse across all iOS apps) ───
gh secret set APPLE_TEAM_ID --body "YOUR_TEAM_ID"
gh secret set ASC_KEY_ID --body "YOUR_KEY_ID"
gh secret set ASC_ISSUER_ID --body "YOUR_ISSUER_ID"
gh secret set ASC_API_KEY --body ([Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_XXXX.p8")))
gh secret set MATCH_GIT_URL --body "https://github.com/pearsonmedia/ios-certificates.git"
gh secret set MATCH_PASSWORD --body "your-match-passphrase"

$pat = "github_pat_xxxx"
$auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("pearsonmedia:$pat"))
gh secret set MATCH_GIT_BASIC_AUTHORIZATION --body $auth

# Optional
gh secret set SLACK_WEBHOOK_URL --body "https://hooks.slack.com/services/T.../B.../xxxx"

# ─── APP-SPECIFIC SECRETS (unique to Loci) ───
gh secret set SUPABASE_URL --body "https://supabase.yourdomain.com"
gh secret set SUPABASE_ANON_KEY --body "eyJhbGciOiJIUzI1NiIs..."
gh secret set REVENUECAT_API_KEY --body "appl_xxxx"
gh secret set TELEMETRYDECK_APP_ID --body "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
gh secret set CERT_PIN_HASH --body "your-base64-hash"
# gh secret set CERT_BACKUP_PIN_HASH --body "optional-backup-hash"
```

### For Your Next App — Copy Shared Secrets

```powershell
# In your new app's repo, you only need to set the shared secrets once.
# Then add app-specific ones. Here's a helper:

$shared = @("APPLE_TEAM_ID", "ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_API_KEY",
            "MATCH_GIT_URL", "MATCH_PASSWORD", "MATCH_GIT_BASIC_AUTHORIZATION",
            "SLACK_WEBHOOK_URL")

Write-Host "Shared secrets to set in new repo:"
$shared | ForEach-Object { Write-Host "  gh secret set $_ --body `"<value>`"" }
```

Or use [GitHub Organization Secrets](https://docs.github.com/en/actions/security-for-github-actions/security-guides/using-secrets-in-github-actions#creating-secrets-for-an-organization) if your repos are in an org — shared secrets propagate automatically.

---

## Local Development Setup

```powershell
# 1. Clone the repo
git clone https://github.com/pearsonmedia/loci-ios.git
cd loci-ios

# 2. Copy the secrets template
cp Loci/Configuration/BuildSecrets.swift.example Loci/Configuration/BuildSecrets.swift

# 3. Edit BuildSecrets.swift with your local development values
# For local Supabase, the defaults (localhost:8000) are fine.
# For RevenueCat testing, use your sandbox API key.

# 4. Open in Xcode
open Loci/Loci.xcodeproj
```

The `BuildSecrets.swift` file is in `.gitignore` and will never be committed.

---

## CI/CD Workflows

### Automatic: CI Build & Lint

**Trigger**: Push to `develop` or `feature/*`, PR to `main`
**File**: `.github/workflows/ci.yml`
**What it does**: SwiftLint + simulator build + web build
**No secrets required** (uses `CODE_SIGNING_ALLOWED=NO`)

### Automatic: TestFlight Deploy

**Trigger**: Push to `main`
**File**: `.github/workflows/deploy.yml`
**What it does**:
1. Generates `BuildSecrets.swift` from GitHub Secrets
2. Pulls signing certificates via Fastlane Match
3. Increments build number (uses `github.run_number`)
4. Archives and uploads to TestFlight
5. Sends Slack notification

### Manual: App Store Release

**Trigger**: Manual dispatch (Actions tab > "Release — App Store" > "Run workflow")
**File**: `.github/workflows/release.yml`
**Inputs**:
- `version`: Marketing version (e.g., `1.0.0`)
- `whats_new`: Release notes text

**What it does**:
1. Everything from TestFlight deploy, plus:
2. Sets the marketing version
3. Submits to App Store Review (auto-release on approval)
4. Creates a GitHub Release tag

### Workflow: From Code to App Store

```
feature branch ──PR──> main ──auto──> TestFlight
                                         │
                                    test on device
                                         │
                              manual dispatch release.yml
                                         │
                                    App Store Review
                                         │
                                    Live on App Store
```

---

## First App Store Submission Checklist

Before your first release, ensure these are done:

### In App Store Connect

- [ ] App name, subtitle, description filled in (Fastlane metadata handles this)
- [ ] App icon uploaded (1024x1024, no alpha, no rounded corners — SVG is auto-processed)
- [ ] At least 1 screenshot set per required device size:
  - iPhone 6.7" (iPhone 15 Pro Max): 1290 x 2796 px
  - iPhone 6.5" (iPhone 14 Plus): 1284 x 2778 px
  - iPad Pro 12.9" (if supporting iPad): 2048 x 2732 px
- [ ] Privacy Policy URL set (host on your marketing site)
- [ ] Support URL set
- [ ] Age rating questionnaire completed
- [ ] Pricing set (Free with in-app purchases)
- [ ] In-App Purchases created in App Store Connect (must match RevenueCat products)

### In Apple Developer Portal

- [ ] App ID registered with Push Notifications capability enabled
- [ ] Push notification certificate or key configured (APNs key is reusable)
- [ ] App Group (`group.com.pearsonmedia.loci`) added to App ID

### In RevenueCat

- [ ] Products created matching App Store Connect in-app purchases
- [ ] Entitlements (`premium`, `family`) configured
- [ ] Offerings created with the correct product IDs
- [ ] App Store Connect Shared Secret entered in RevenueCat (for server-side validation)

### In Your Codebase

- [ ] All GitHub Secrets set (see [reference table](#all-secrets-for-loci))
- [ ] `ITSAppUsesNonExemptEncryption` set to `false` in Info.plist (already done)
- [ ] Privacy manifest if using any tracked APIs (check Apple's list)

### Screenshots via Fastlane (Optional)

```bash
# If you want to automate screenshots:
cd Loci
fastlane snapshot
# Configure Snapfile first — see Fastlane docs
```

---

## Shared Secrets Across Apps

Here's what you can reuse from Loci when setting up your next iOS app:

| Secret | Reusable? | Notes |
|--------|-----------|-------|
| `APPLE_TEAM_ID` | **Yes** | Same for all apps under your account |
| `ASC_KEY_ID` | **Yes** | One API key works for all apps |
| `ASC_ISSUER_ID` | **Yes** | Tied to your account, not per-app |
| `ASC_API_KEY` | **Yes** | The .p8 file works for all apps |
| `MATCH_GIT_URL` | **Yes** | One cert repo for all apps |
| `MATCH_PASSWORD` | **Yes** | Same encryption passphrase |
| `MATCH_GIT_BASIC_AUTHORIZATION` | **Yes** | Same PAT works if repo access granted |
| `SLACK_WEBHOOK_URL` | **Yes** | Same channel for all CI notifications |
| `SUPABASE_URL` | **Maybe** | Only if apps share a backend |
| `SUPABASE_ANON_KEY` | **Maybe** | Only if apps share a backend |
| `REVENUECAT_API_KEY` | **No** | Each app gets its own project |
| `TELEMETRYDECK_APP_ID` | **No** | Each app gets its own app ID |
| `CERT_PIN_HASH` | **No** | Specific to the backend domain |

### Recommendation: GitHub Organization Secrets

If you have 2+ apps, move shared secrets to org-level:

```powershell
# Set once at org level, available to all repos
gh secret set APPLE_TEAM_ID --org pearsonmedia --body "YOUR_TEAM_ID"
gh secret set ASC_KEY_ID --org pearsonmedia --body "YOUR_KEY_ID"
gh secret set ASC_ISSUER_ID --org pearsonmedia --body "YOUR_ISSUER_ID"
# ... etc for all "Yes" items above
```

Then each new app repo only needs its app-specific secrets (4-5 values instead of 12+).

---

## Troubleshooting

### Match: "Could not create a new certificate"
Your Apple Developer account may have hit the certificate limit (2 distribution certs). Revoke an old one in the Developer portal, then run `fastlane match nuke distribution` and re-init.

### Build fails: "No signing certificate found"
Ensure `MATCH_GIT_BASIC_AUTHORIZATION` is correctly base64-encoded and the PAT has not expired.

### "Missing compliance" warning in TestFlight
The `ITSAppUsesNonExemptEncryption = false` key in Info.plist handles this. If you add encryption later, update accordingly.

### Certificate pinning fails in production
Re-generate `CERT_PIN_HASH` — TLS certificates rotate. Always include a backup pin (intermediate CA) so the app doesn't break during rotation.

### Build number conflicts
The deploy workflow uses `github.run_number` which auto-increments per workflow. If you need to reset, create a new workflow file (run numbers are per-workflow).
