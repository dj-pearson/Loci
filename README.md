# Lociate — Your Spatial Memory

Voice-first iOS app that pins voice notes to GPS coordinates. When you return to a location, your notes find you via proximity-triggered push notifications. Family members share notes through invite-only household groups.

**Built by Pearson Media LLC** | [lociate.app](https://lociate.app)

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| iOS App | Swift 5.9+, SwiftUI, SwiftData, CoreLocation (CLMonitor), Apple Speech, MapKit, WidgetKit |
| Auth | Supabase Auth (Apple Sign In + Email) |
| Backend | Self-hosted Supabase, PostgreSQL 15+ with PostGIS, on Contabo/Coolify |
| Edge Functions | Node.js 20 + Hono framework (Docker sidecar) |
| Subscriptions | RevenueCat |
| Analytics | TelemetryDeck |
| Marketing Site | Astro + Tailwind on Cloudflare Pages |
| CI/CD | GitHub Actions, Fastlane, SwiftLint |

## Project Structure

```
Lociate/
├── CLAUDE.md                 # Project context for Claude Code
├── prd.json                  # Ralph user stories (120 stories, 21 phases)
├── progress.txt              # Ralph progress tracker
├── ralph-prompt.md           # Prompt fed to each Ralph iteration
├── ralph.ps1                 # Ralph loop script (PowerShell/Windows)
├── ralph.sh                  # Ralph loop script (Bash/macOS/Linux)
├── Lociate/                  # Xcode project
│   ├── Models/               # SwiftData @Model classes
│   ├── ViewModels/           # @Observable view models
│   ├── Views/                # SwiftUI views (MapView, Record, Detail, etc.)
│   ├── Services/             # Business logic (Location, Audio, Sync, etc.)
│   ├── Widget/               # WidgetKit extension
│   └── Utilities/            # Helpers, extensions, constants
├── backend/
│   ├── migrations/           # PostgreSQL schema migrations
│   └── docker-compose.yml    # Supabase + edge functions
├── edge-functions/           # Node.js + Hono Docker sidecar
├── web/                      # Astro marketing site
└── .github/workflows/        # CI/CD pipelines
```

---

## Building and Verifying

### iOS

The Xcode project is **generated**, not hand-edited — it had previously drifted to
the point where 72 of 104 Swift files belonged to no target and the app could not
compile (US-185). After adding or removing a Swift file:

```bash
python3 scripts/generate-xcodeproj.py           # regenerate project.pbxproj + scheme
python3 scripts/generate-xcodeproj.py --check    # what CI enforces
```

Before the first build you need `BuildSecrets.swift`, which is gitignored:

```bash
cp Lociate/Configuration/BuildSecrets.swift.example \
   Lociate/Configuration/BuildSecrets.swift
# or generate it from environment variables, as CI does:
SUPABASE_URL=... SUPABASE_ANON_KEY=... REVENUECAT_API_KEY=... \
  TELEMETRYDECK_APP_ID=... CERT_PIN_HASH=... bash scripts/generate-secrets.sh --ios
```

SPM dependencies (supabase-swift, RevenueCat, TelemetryDeck) resolve on first
build; `xcodebuild -resolvePackageDependencies` does it explicitly.

```bash
xcodebuild -project Lociate/Lociate.xcodeproj -scheme Lociate \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' build
xcodebuild -project Lociate/Lociate.xcodeproj -scheme Lociate \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 15' test
```

App icons are generated from `design/*.svg` (requires `pip install cairosvg pillow`):

```bash
python3 scripts/generate-app-icons.py
```

### Android

```bash
cp android/local.properties.example android/local.properties   # then fill in
cd android && ./gradlew assembleDebug
./gradlew testDebugUnitTest
```

A release build fails deliberately when `MAPS_API_KEY` is unset — a blank map
screen in a shipped app is worse than a failed build. Pass
`-PallowMissingMapsKey` only for a throwaway build.

### Edge functions

```bash
cd edge-functions
npm ci
npm run typecheck
npm test
npm run build
```

### Backend

Migrations are applied by a tracked runner that records each file's checksum, so a
partial or double apply is detectable:

```bash
PGHOST=... PGUSER=... PGDATABASE=... scripts/apply-migrations.sh --dry-run
PGHOST=... PGUSER=... PGDATABASE=... scripts/apply-migrations.sh
PGHOST=... PGUSER=... PGDATABASE=... scripts/apply-migrations.sh --status
```

The RLS isolation suite applies every migration to a scratch database and asserts
that one household cannot reach another's data. It needs PostgreSQL with PostGIS:

```bash
PGHOST=... PGUSER=postgres bash scripts/run-backend-tests.sh
```

### Marketing site

```bash
cd web && npm ci && npm run build
```

The build generates `.well-known/apple-app-site-association` and `assetlinks.json`
from `APPLE_TEAM_ID` and `ANDROID_SHA256_CERT_FP`, and fails in production if
either is unset — the previously committed file contained a literal `TEAM_ID`
placeholder, which silently broke every universal link.

---

## Ralph Autonomous Build System

This project uses [Ralph](https://ghuntley.com/ralph/) by Snarktank for autonomous iterative development. Ralph runs Claude Code CLI in a loop, completing one user story per iteration. The `prd.json` and `progress.txt` files serve as memory between iterations.

### Prerequisites

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- Python 3.x (for JSON parsing)
- Git

### Running Ralph

#### PowerShell (Windows)

```powershell
# Run all 120 stories
.\ralph.ps1

# Run a specific number of stories
.\ralph.ps1 -MaxIterations 10

# Allow more Claude turns per story (for complex stories)
.\ralph.ps1 -MaxTurns 100

# Longer pause between iterations (seconds)
.\ralph.ps1 -Delay 30

# Stop the loop if a story fails
.\ralph.ps1 -StopOnFail

# Combine options
.\ralph.ps1 -MaxIterations 20 -MaxTurns 100 -Delay 15 -StopOnFail
```

#### Bash (macOS / Linux / Git Bash)

```bash
# Run all stories
bash ralph.sh

# Run a specific number of stories
bash ralph.sh --max-iterations 10

# Allow more Claude turns per story
bash ralph.sh --max-turns 100

# Longer pause between iterations
bash ralph.sh --delay 30

# Stop on failure
bash ralph.sh --stop-on-fail

# Show help
bash ralph.sh --help
```

### How It Works

1. Script reads `prd.json` and finds the first story where `passes: false`
2. Sends `ralph-prompt.md` to `claude -p` (non-interactive CLI mode)
3. Claude reads `CLAUDE.md` for project context, implements the story, verifies acceptance criteria
4. Claude updates `prd.json` (marks `passes: true`) and `progress.txt` (checks off the story)
5. Claude commits the work with a conventional commit message
6. Script checks if the story was completed, logs output to `.ralph-logs/`
7. Moves to the next story. Repeats until done or max iterations reached.

Each iteration is a **fresh Claude context** — `prd.json`, `progress.txt`, and git history are the memory between iterations.

### Monitoring Progress

```powershell
# Check how many stories are done
python -c "import json; d=json.load(open('prd.json','r',encoding='utf-8')); done=sum(1 for s in d['userStories'] if s['passes']); print(f'{done}/{len(d[\"userStories\"])} stories complete')"

# View iteration logs
ls .ralph-logs/

# Check git log for completed stories
git log --oneline
```

### Key Files

| File | Purpose |
|------|---------|
| `prd.json` | All 120 user stories with acceptance criteria. Source of truth for what to build. |
| `progress.txt` | Human-readable progress tracker with phase groupings and context notes for Ralph. |
| `ralph-prompt.md` | The exact prompt sent to Claude each iteration. Instructs it to find, implement, verify, and commit one story. |
| `CLAUDE.md` | Project architecture, coding standards, and build commands. Auto-loaded by Claude Code every iteration. |
| `.claude/settings.local.json` | Pre-approved tool permissions so Claude can work autonomously (git, file ops, build). |
| `.ralph-logs/` | Per-iteration log files for debugging. |

---

## Monetization

| | Free | Premium ($3.99/mo) | Family ($5.99/mo) |
|---|------|--------------------|--------------------|
| Loci limit | 10 | Unlimited | Unlimited |
| AI categorization | — | Yes | Yes |
| Cloud sync | — | Yes | Yes |
| Widget | — | Yes | Yes |
| Search | — | Yes | Yes |
| Family sharing | — | — | Yes (up to 6) |
| Yearly | — | $29.99/yr | $44.99/yr |
| Lifetime | — | $59.99 | $89.99 |

---

## License

Proprietary — Pearson Media LLC. All rights reserved.
