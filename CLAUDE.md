# Lociate — Your Spatial Memory

## What Is This?
Lociate is a voice-first iOS app that pins voice notes to GPS coordinates. When users return to a location, their notes find them via proximity-triggered push notifications. Family members share notes through invite-only household groups.

The app's internal domain language still uses "locus" (singular) and "loci" (plural) as the nouns for a saved pin — do not rename `Locus`/`loci` in code, variables, or acceptance criteria. Only the product name is "Lociate".

## Tech Stack

### iOS App
- **Language**: Swift 5.9+, SwiftUI (declarative UI)
- **Target**: iOS 17.0+ (required for SwiftData + CLMonitor)
- **Architecture**: MVVM with `@Observable` classes (Observation framework — **NOT** Combine `ObservableObject`)
- **Persistence**: SwiftData (`@Model`, `@Query` — **NOT** Core Data)
- **Location**: CoreLocation with `CLMonitor` for geofencing (**NOT** legacy `CLLocationManager` region monitoring)
- **Audio**: AVFoundation (AVAudioRecorder/AVAudioPlayer), M4A/AAC 64kbps mono
- **Transcription**: Apple Speech framework (SFSpeechRecognizer) — on-device, free, private. **NO Whisper API in V1.**
- **Maps**: MapKit with custom Annotation views
- **Widgets**: WidgetKit + AppIntents
- **Subscriptions**: RevenueCat SDK
- **Auth**: supabase-swift SDK + Apple Sign In
- **Analytics**: TelemetryDeck (privacy-focused)

### Backend (Self-Hosted Supabase)
- **Hosting**: Contabo VPS via Coolify (Docker)
- **Database**: PostgreSQL 15+ with PostGIS extension
- **Auth**: Supabase Auth (Apple Sign In + Email)
- **Storage**: Supabase Storage for M4A audio files
- **API**: PostgREST auto-generated REST
- **Edge Functions**: Node.js 20 LTS + Hono framework in Docker sidecar (**NOT** Supabase/Deno Edge Functions)

### Marketing Website
- **Framework**: Astro (static export)
- **Hosting**: Cloudflare Pages
- **Styling**: Tailwind CSS

### CI/CD
- **Repo**: GitHub (pearsonmedia/lociate-ios)
- **CI**: GitHub Actions (SwiftLint, xcodebuild, TestFlight)
- **Signing**: Fastlane match

## Project Structure

```
Lociate/
├── CLAUDE.md                    # This file
├── prd.json                     # Ralph user stories (source of truth)
├── progress.txt                 # Ralph progress tracking
├── ralph-prompt.md              # Prompt fed to each Ralph iteration
├── ralph.sh                     # Ralph loop orchestrator
├── Lociate/                     # Xcode project
│   ├── LociateApp.swift         # @main entry point
│   ├── Models/                  # SwiftData @Model classes
│   ├── ViewModels/              # @Observable view models
│   ├── Views/
│   │   ├── MapView/
│   │   ├── Record/
│   │   ├── Detail/
│   │   ├── Onboarding/
│   │   ├── Settings/
│   │   └── Components/          # Reusable UI components
│   ├── Services/                # Business logic services
│   ├── Widget/                  # WidgetKit extension
│   └── Utilities/               # Helpers, extensions, constants
├── backend/
│   ├── migrations/              # PostgreSQL schema migrations
│   └── docker-compose.yml       # Supabase + edge functions
├── edge-functions/              # Node.js + Hono Docker sidecar
│   ├── src/
│   ├── Dockerfile
│   └── package.json
├── web/                         # Astro marketing site
└── .github/workflows/           # CI/CD pipelines
```

## Critical Architecture Rules

1. **Offline-first**: Every feature MUST work without network. Sync is additive, not required.
2. **20 geofence limit**: iOS enforces max 20 CLCircularRegion per app. Use nearest-rotation strategy.
3. **Voice-first**: Recording is the primary input. The UI should make recording effortless.
4. **Private by default**: No public data, no social features. Sharing is opt-in within households only.
5. **SwiftData, not Core Data**: Use `@Model`, `@Query`, `ModelContainer`, `ModelContext`.
6. **@Observable, not ObservableObject**: Use the Observation framework. No `@Published`, no `Combine`.
7. **CLMonitor, not legacy regions**: iOS 17+ geofencing API. Do not use `startMonitoring(for:)`.
8. **M4A/AAC audio**: 64kbps mono, ~100KB per 30 seconds. Not WAV.

## Coding Standards

### Swift/SwiftUI
- Use `@Observable` macro on view model classes
- Use `@Environment(\.modelContext)` for SwiftData access in views
- Prefer `async/await` over completion handlers
- Use SF Symbols for all icons (no custom icon assets unless necessary)
- Haptic feedback via `UIImpactFeedbackGenerator` / `UINotificationFeedbackGenerator`
- All user-facing strings should support localization (use String(localized:))
- Minimum tap target: 44x44 points
- Support Dynamic Type and VoiceOver

### Node.js (Edge Functions)
- TypeScript with strict mode
- Hono framework for routing
- ESM modules
- Validate all inputs at API boundary
- JWT auth validation on all endpoints

### SQL
- All migrations in `backend/migrations/` numbered sequentially (001_, 002_, etc.)
- RLS policies on every table
- Use PostGIS `GEOGRAPHY(POINT, 4326)` for spatial columns
- Indexes on all foreign keys and query patterns

## Build & Verify Commands

```bash
# iOS build (simulator)
xcodebuild -project Lociate/Lociate.xcodeproj -scheme Lociate \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build 2>&1 | tail -5

# Swift lint
swiftlint --config Lociate/.swiftlint.yml

# Edge functions
cd edge-functions && npm run build && npm test

# Marketing site
cd web && npm run build

# Type check edge functions
cd edge-functions && npx tsc --noEmit
```

## Monetization Tiers (enforce in code)

| Feature | Free | Premium ($3.99/mo) | Family ($5.99/mo) |
|---------|------|--------------------|--------------------|
| Max loci | 10 | Unlimited | Unlimited |
| AI categorization | No | Yes | Yes |
| Cloud sync | No | Yes | Yes |
| Widget | No | Yes | Yes |
| Search | No | Yes | Yes |
| Family sharing | No | No | Yes (up to 6) |

## Ralph Workflow

This project uses Ralph (prd.json + progress.txt) for autonomous iterative development.
- `prd.json` contains all user stories with acceptance criteria
- `progress.txt` tracks completion status
- Each Ralph iteration should complete ONE user story
- Stories are ordered by dependency — work in priority order
- After completing a story, update both prd.json AND progress.txt
- Git commit after each completed story

<!-- SELVEDGE:START -->
## Pearson Media — shared context

*Managed from the vault. Edit `14 - Resources/Shared CLAUDE Block.md` in the vault; direct edits between these markers are overwritten once a sync exists. Everything outside them is yours and is never touched.*

**The memory vault.** Portfolio-wide memory lives in the **Hermes** vault at `<your-home>\Documents\Hermes` (`C:\Users\dpearson\Documents\Hermes` on this machine; remote: https://github.com/dj-pearson/Hermes). It holds the profile, the map of all ten projects, and cross-project knowledge. Read `VAULT-INDEX.md` there when a task needs context beyond this repo. This repo's own `CLAUDE.md`, `~/.claude` memory, and skills remain authoritative for work inside it — the vault supplements them, never replaces them.

**Name the project.** Pearson Media runs ten projects on a shared stack. Never say "the app," "the repo," or "production" without naming which one. A right answer about the wrong project is a wrong answer.

**The shared stack.** React + TypeScript + Vite, Tailwind, shadcn/ui, self-hosted Supabase, Cloudflare Pages, Coolify on Contabo, Stripe. A problem solved in one repo is usually already solved for this one — check the vault before solving it twice.

**Secrets are references, never values.** Never write a password, key, or token value into a note, summary, commit, or setup doc; name where it's stored instead. Loose credential files exist under your `Documents` folder (`C:\Users\dpearson\Documents` on this machine) — never read one into a document.

**Never delete what Claude Code relies on.** Repo `CLAUDE.md` files, `~/.claude/projects/*/memory/`, `.claude/skills/`, settings. Copy from them freely; removing or stubbing them is Dj's call alone.

**Evidence only.** Verify state from the actual file or command before claiming anything is done or in place. If unsure, say so and go find out.

**Write like a person.** Every model was trained on the same corpus, so the default register is recognisable within a sentence and it lands in commits, PR bodies, docs, UI copy and error strings alike. State the point first, then support it. Have an opinion; asked which of two, name one. Use real names and numbers, not categories. Never label your own significance ("important", "crucial", "worth noting", "notably"); if it matters the reader will see it. Banned outright: *delve, dive into, deep dive, unpack, shed light on, pave the way, usher in, tap into, supercharge, unlock, elevate, empower, streamline, curate, showcase, boast, groundbreaking, cutting-edge, transformative, game-changing, innovative, pivotal, invaluable, meticulous, bespoke, vibrant, multifaceted, holistic, testament, tapestry, synergy, cornerstone, treasure trove, plethora, myriad, moreover, furthermore, additionally.* Banned decoratively but fine literally: *navigate, harness, leverage, robust, comprehensive, landscape, realm, journey*; the test is whether a reader could check the claim. Banned phrases: *"In today's…", "It's important/worth noting", "When it comes to", "At its core", "At the end of the day", "This is where X comes in", "Let's break it down", "plays a crucial role", "cannot be overstated", "underscoring the importance of", "highlighting the need for"*, and the whole chat register (*"Great question!", "Absolutely!", "I'd be happy to", "Let me know if you need anything else", "I hope this helps"*). Banned structures, which imitate insight without carrying any: *"not just X, it's Y"*, *"not only X but Y"*, *"this isn't about X, it's about Y"*, *"No X. No Y. Just Z."*, the rule of three that goes abstract on the third item, the rhetorical question as a transition, and closing with a summary of what was just read. **At most one em dash** per piece of writing, never as the default connector; use commas, parentheses and semicolons. Vary sentence and paragraph length deliberately. Uniform 18-word sentences are the signature that survives every word-level edit. Use contractions. Don't restate the question, don't open with a sweeping scene-setter, don't over-format (no emoji as structure, no header on a three-paragraph answer, no table for two rows). The one allowed exception is a **bold lead-in used as a heading** in a reference document like this one; a *run* of "**Bold term:** one sentence" bullets standing in for prose is the tell.

**Plain characters only.** Generated text carries Unicode that renders as ordinary punctuation, as ordinary whitespace, or as nothing at all, and it survives review precisely because it looks correct. **Anything a machine parses is ASCII unless the content requires otherwise**: code, config, JSON, YAML, CSV, SQL, regex, env values, filenames, URLs, commit subjects. Straight quotes `'` `"`, hyphen-minus `-`, three dots for an ellipsis, one ordinary space between words. Never emit curly quotes (U+2018/2019/201C/201D), en/em dashes (U+2013/2014), U+2026 ellipsis, U+2212 minus or U+2032 primes into code; a look-alike character in a PowerShell string or a SQL literal is a runtime failure, which is how `backup-databases.ps1` and `ssl-check.ps1` sat unparseable for months. Never emit a no-break space (U+00A0, and U+202F/2007/2009/2002/2003/3000), which breaks shell word-splitting, `grep` and column parsing while looking exactly like a space, or U+2028/U+2029, which are valid JSON and a syntax error inside a JS string literal. **Never emit an invisible or bidi character anywhere:** U+200B-U+200F, U+2060-U+2064, U+FEFF, U+00AD, U+034F, U+180E, the bidi controls U+202A-U+202E and U+2066-U+2069, and above all the Unicode tag block **U+E0000-U+E007F**, which encodes arbitrary ASCII invisibly and is the usual carrier for text a reviewer cannot see. Avoid homoglyphs (Cyrillic a/e/o/p/c/x, Greek omicron, fullwidth Latin, mathematical alphanumerics for bold): an identifier holding one compares unequal to the identifier it appears to be. Prose may use real typography and real accented names; prose may not carry characters that don't render. The one exception is a deliberate, load-bearing use, which carries a comment saying why. Scan with `rg -n '[\x{00AD}\x{034F}\x{061C}\x{180E}\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{2066}-\x{2069}\x{FEFF}\x{E0000}-\x{E007F}]'`.

**Terminal output is scrollback, not a report.** Answer first — no "I'll start by", no restating the request, no narrating tool calls the transcript already shows. Don't summarise a diff the reader can see or paste back code you just wrote; one line naming what changed and where, with `file:line` because it's clickable. Length matches the question: a yes/no gets a yes/no plus the clause that makes it trustworthy, and under about six lines there are no headers, bullets or tables. Report actual output, not a paraphrase: quote the failing assertion, say what was skipped, say plainly what's verified and what isn't. No emoji and no status theatre; "246 tests, 246 passing" beats "✅ All tests passing!" and is falsifiable. Don't close with an offer of more help or unrequested next steps: ask a real question, or name the real remaining work. Commits are imperative, what and why, no launch copy. PR bodies say what changed, why, how it was verified, and what's still open.

**UI has a craft floor.** Every model trained on the same SaaS templates, so the *default* frontend output is a recognizable handful of tells — and Tailwind + shadcn/ui puts each of them one autocomplete away. Treat the following as the category's defaults rather than as bans: the brief's own words can earn any of them, but reaching for one on a free axis means you were not deciding. Refuse **purple/blue gradients and gradient text** (emphasis comes from weight and size); **Inter or a system default as the type *choice***; a colored **`border-left`/`border-right` above 1px** on cards, list items, callouts or alerts — the single most recognizable tell; grids of **same-size icon-tile + heading + text cards** as the page structure, and **cards nested in cards**; a **1px border under a wide soft shadow** (declare elevation once — border *or* shadow); **gray text on colored surfaces** (tint secondary text from the surface hue or the foreground); **bounce/elastic easing**; **monospace as a costume** for "technical" rather than for code, data or measurement; and a **tracked uppercase eyebrow over every section**. Keep body measure at 65–75ch, tracking no tighter than -0.04em, and card radii at 12–16px.

**Check UI, don't just intend it.** `npx impeccable detect <path>` runs 60 deterministic anti-pattern rules with no install, no API key and no LLM — it works from any repo, so there is no excuse for asserting a UI is clean. Use the `/impeccable` skill (`audit`, `critique`, `polish`, `colorize`, `typeset`) for the judgement calls it cannot make. Source: [Impeccable](https://github.com/pbakaus/impeccable), Apache 2.0.
<!-- SELVEDGE:END -->
