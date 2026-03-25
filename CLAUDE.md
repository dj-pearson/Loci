# Loci — Your Spatial Memory

## What Is This?
Loci is a voice-first iOS app that pins voice notes to GPS coordinates. When users return to a location, their notes find them via proximity-triggered push notifications. Family members share notes through invite-only household groups.

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
- **Repo**: GitHub (pearsonmedia/loci-ios)
- **CI**: GitHub Actions (SwiftLint, xcodebuild, TestFlight)
- **Signing**: Fastlane match

## Project Structure

```
Loci/
├── CLAUDE.md                    # This file
├── prd.json                     # Ralph user stories (source of truth)
├── progress.txt                 # Ralph progress tracking
├── ralph-prompt.md              # Prompt fed to each Ralph iteration
├── ralph.sh                     # Ralph loop orchestrator
├── Loci/                        # Xcode project
│   ├── LociApp.swift            # @main entry point
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
xcodebuild -project Loci/Loci.xcodeproj -scheme Loci \
  -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build 2>&1 | tail -5

# Swift lint
swiftlint --config Loci/.swiftlint.yml

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
