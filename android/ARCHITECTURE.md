# Lociate Android -- Architecture Document

## 1. Architecture Decision: Native Kotlin/Jetpack Compose

**Decision**: Build the Android app as a fully native Kotlin application using Jetpack Compose, rather than adopting Kotlin Multiplatform (KMP) with shared business logic.

**Rationale**:

- **Platform-specific APIs dominate the codebase.** Lociate's core functionality relies heavily on APIs that have no cross-platform abstraction: `FusedLocationProviderClient` and `GeofencingClient` for location/geofencing, `MediaRecorder` for audio capture, `SpeechRecognizer` for on-device transcription, and `WorkManager` for Doze-compatible background sync. A KMP shared module would need `expect`/`actual` declarations for nearly every service, negating the code-sharing benefit.

- **No shared UI benefit.** iOS uses SwiftUI and Android uses Jetpack Compose. These are fundamentally different UI toolkits. KMP does not share UI code between them (Compose Multiplatform for iOS is experimental and not production-ready for this use case). The UI layer -- which constitutes the majority of app code -- would remain platform-specific regardless.

- **Material 3 Dynamic Color.** Android 12+ supports system-level dynamic theming that adapts the app's color palette to the user's wallpaper. This is a native Android capability with no iOS equivalent, and leveraging it fully requires native Material 3 integration.

- **Simpler dependency graph.** Native Android avoids the Gradle complexity of KMP modules, version alignment issues between Kotlin/Native and JVM targets, and the overhead of maintaining `commonMain`/`androidMain`/`iosMain` source sets for minimal shared code.

- **Same Supabase backend.** Both platforms consume the identical PostgREST API and Storage endpoints. The `supabase-kt` SDK provides idiomatic Kotlin access that mirrors what `supabase-swift` provides on iOS. There is no shared networking layer to extract.

- **Team velocity.** A single-platform native codebase is easier to onboard contributors to, debug, and maintain than a multiplatform project with platform bridging layers.

---

## 2. iOS to Android Service Mapping

| iOS | Android | Notes |
|-----|---------|-------|
| CoreLocation + CLMonitor | FusedLocationProviderClient + GeofencingClient | Android supports up to 100 geofences vs iOS 20. No nearest-rotation strategy needed. |
| SwiftData (`@Model`, `@Query`) | Room (`@Entity`, `@Dao`) | Flow-based reactive queries replace SwiftData's `@Query` macro. |
| Keychain Services | EncryptedSharedPreferences (AES-256-GCM) | AndroidX Security library. Graceful fallback to standard SharedPreferences on failure. |
| AVFoundation (AVAudioRecorder/AVAudioPlayer) | MediaRecorder + MediaPlayer | Same M4A/AAC 64kbps mono format. Foreground service required for background recording. |
| Apple Speech (SFSpeechRecognizer) | Android SpeechRecognizer | On-device recognition where available. Falls back to server-based on older devices. |
| MapKit + custom Annotations | Google Maps SDK (Compose) | `GoogleMap` composable with `Marker` for annotations, `CameraPositionState` for viewport. |
| WidgetKit + AppIntents | Glance (Jetpack Compose widgets) | Future implementation. Glance uses Compose-like API for RemoteViews. |
| RevenueCat SDK | Google Play Billing Library | RevenueCat optional for cross-platform receipt unification. |
| supabase-swift | supabase-kt | Same Supabase backend, same API. Ktor engine for HTTP transport. |
| Observation framework (`@Observable`) | StateFlow / SharedFlow | Kotlin coroutines and Flow replace Apple's Observation/Combine. ViewModels expose `StateFlow`. |
| Combine publishers | Kotlin Flow | `stateIn(WhileSubscribed(5000))` for lifecycle-aware collection. |
| BackgroundTasks framework | WorkManager | Doze-compatible deferred work. `CoroutineWorker` for suspend function support. |
| APNS (Push Notifications) | FCM (Firebase Cloud Messaging) | Same Supabase triggers, different push delivery channel. |
| `@main` App struct | `@HiltAndroidApp` Application | Hilt for dependency injection vs SwiftUI environment/manual DI. |
| SwiftUI `NavigationStack` | Compose Navigation (`NavHost`) | Type-safe routes with deep-link support for `loci://locus/{id}`. |
| Swift Concurrency (`async`/`await`) | Kotlin Coroutines (`suspend`, `launch`) | Structured concurrency in both. `viewModelScope` for ViewModel-scoped work. |

---

## 3. Story Count and Progress

The Android implementation spans **12 user stories** (US-153 through US-164):

| Story | Title | Status |
|-------|-------|--------|
| US-153 | Project scaffold (Kotlin, Compose, Hilt, Room) | Completed |
| US-154 | Core services (location, audio, speech, geofencing) | Completed |
| US-155 | UI foundation (Material 3, navigation, components) | Completed |
| US-156 | Main screens (Map, List, Recording, Detail, Search, Settings, Auth, Onboarding) | Completed |
| US-157 | Utility classes (constants, network, security, sanitizer, Haversine) | Completed |
| US-158 | Security hardening (encrypted storage, cert pinning, biometric, input validation) | Completed |
| US-159 | Performance optimization (lazy loading, caching, WorkManager sync) | Completed |
| US-160 | UX polish (animations, haptics, accessibility, error handling) | Completed |
| US-161 | Supabase integration (auth, sync, storage) | Completed |
| US-162 | CI/CD (GitHub Actions build, lint, test pipeline) | Remaining |
| US-163 | Family sharing (household creation, join, member management) | Remaining |
| US-164 | Monetization (Google Play Billing, tier enforcement) | Remaining |

**Summary**: 9 of 12 stories completed. 3 remaining (CI/CD, family sharing, monetization).

---

## 4. Android-Specific Considerations

### Background Location and Doze Mode

Android enforces strict background execution limits starting with Android 8.0 (Oreo) and further tightened by Doze mode:

- **Foreground service required** for continuous location updates during active recording (`RecordingForegroundService`) and geofence monitoring (`LocationForegroundService`).
- **WorkManager** is the only reliable mechanism for deferred background work under Doze. `SyncWorker` uses `CoroutineWorker` with network constraints and exponential backoff (3 retries, 15-minute periodic interval).
- **Boot receiver** (`BootReceiver`) re-registers geofences after device reboot, since Android clears all geofences on restart.
- `ACCESS_BACKGROUND_LOCATION` permission requires a separate runtime prompt (Android 11+) with justification.

### Notification Channels

Android 8.0+ requires notification channels. Lociate defines three:

1. **Geofence** (`geofence_channel`): Proximity alerts when entering a locus radius. High importance.
2. **Sync** (`sync_channel`): Background sync status updates. Low importance.
3. **Recording** (`recording_channel`): Foreground service notification during active recording. Default importance.

### Geofence Limit

Android supports **100 simultaneous geofences** per app (vs iOS's 20). This eliminates the need for the nearest-rotation strategy used on iOS. All active loci (up to the free tier limit of 10 or unlimited for premium) can be monitored simultaneously for most users.

### Foreground Services

Android requires a persistent notification for foreground services. Two are defined:

- **RecordingForegroundService**: Active during voice recording to prevent the OS from killing the process.
- **LocationForegroundService**: Active during continuous location tracking sessions.

Both use `ServiceCompat.startForeground()` with appropriate foreground service types (`FOREGROUND_SERVICE_TYPE_MICROPHONE`, `FOREGROUND_SERVICE_TYPE_LOCATION`).

### PendingIntent Security

All `PendingIntent` instances use `FLAG_IMMUTABLE` to prevent intent mutation attacks. Deep-link intents are validated by `DeepLinkValidator` to prevent injection of malicious URIs.

---

## 5. Minimum API Level

**Minimum SDK**: 26 (Android 8.0 Oreo)

**Rationale**:

- **Notification channels**: Required for the three-channel notification strategy. No fallback on API < 26.
- **Foreground service types**: Needed for recording and location foreground services.
- **Adaptive icons**: Consistent launcher icon presentation.
- **Autofill framework**: Better auth UX for sign-in flows.
- **Wide color gamut and font APIs**: Material 3 theming support.
- **Device coverage**: Android 8.0+ covers approximately 95%+ of active devices (per Google Play distribution data), making this a practical floor with minimal user exclusion.
- **AndroidX Security (EncryptedSharedPreferences)**: Requires API 23+, but API 26 aligns with the broader feature requirements above.

**Target SDK**: 35 (latest stable at time of development).

---

## 6. Shared Backend

**No backend changes are required for Android support.**

The Android app connects to the same self-hosted Supabase instance as iOS:

- **PostgreSQL + PostGIS**: Same spatial queries, same RLS policies, same schema.
- **Supabase Auth**: Email/password auth works identically. Google Sign-In replaces Apple Sign In as the social provider on Android, but both are handled by Supabase Auth's provider abstraction.
- **Supabase Storage**: Same M4A audio file bucket and path structure. Files uploaded from Android are playable on iOS and vice versa.
- **PostgREST API**: The `supabase-kt` SDK generates the same REST calls as `supabase-swift`. No API changes needed.
- **Edge Functions**: The Node.js/Hono edge functions (auth rate limiting, etc.) are platform-agnostic and serve both clients.
- **Sync protocol**: Same conflict resolution strategy (remote-wins for unmodified local records, local-wins for locally modified records). `SyncRepository` implements this matching the iOS `SyncService`.

The only platform-specific backend consideration is push notifications: Android uses FCM instead of APNS. If server-triggered push is added, the Supabase edge functions would need to support both delivery channels.

---

## Project Structure

```
android/
├── ARCHITECTURE.md                 # This file
├── build.gradle.kts                # Root Gradle config (Kotlin DSL)
├── settings.gradle.kts             # Module and plugin management
├── gradle.properties               # Gradle and Android properties
├── gradle/                         # Gradle wrapper
└── app/
    └── src/main/java/app/lociate/android/
        ├── LociateApplication.kt   # @HiltAndroidApp entry point
        ├── data/
        │   ├── local/
        │   │   ├── LociateDatabase.kt      # Room database definition
        │   │   ├── dao/                     # LocusDao, HouseholdDao
        │   │   ├── entity/                  # LocusEntity, HouseholdEntity
        │   │   └── converter/               # EntityMapper (domain <-> entity)
        │   ├── remote/
        │   │   ├── SupabaseClient.kt        # Supabase-kt SDK configuration
        │   │   ├── api/                     # AuthRepository, SyncRepository
        │   │   └── dto/                     # LocusDto (wire format)
        │   └── repository/
        │       └── LocusRepositoryImpl.kt   # Room-backed repository
        ├── di/
        │   ├── AppModule.kt                 # Services, utilities
        │   ├── DatabaseModule.kt            # Room, DAOs
        │   └── RepositoryModule.kt          # Repository bindings
        ├── domain/
        │   ├── model/                       # Locus, LocusCategory, Household
        │   └── repository/                  # LocusRepository interface
        ├── service/
        │   ├── LocationService.kt           # FusedLocationProviderClient
        │   ├── GeofenceService.kt           # GeofencingClient (100 limit)
        │   ├── GeofenceBroadcastReceiver.kt # Geofence transition handler
        │   ├── AudioRecorderService.kt      # MediaRecorder (M4A/AAC)
        │   ├── AudioPlayerService.kt        # MediaPlayer with StateFlow
        │   ├── AudioCacheManager.kt         # LRU cache (100MB)
        │   ├── SpeechRecognitionService.kt  # On-device STT
        │   ├── SyncWorker.kt               # WorkManager background sync
        │   ├── BootReceiver.kt             # Geofence re-registration
        │   ├── LocationForegroundService.kt
        │   └── RecordingForegroundService.kt
        ├── ui/
        │   ├── MainActivity.kt             # Edge-to-edge, Hilt
        │   ├── theme/                      # Material 3, Dynamic Color
        │   ├── navigation/                 # LociateNavHost, routes
        │   ├── screen/
        │   │   ├── map/                    # MapScreen, MapViewModel
        │   │   ├── record/                 # RecordingScreen, RecordingViewModel
        │   │   ├── detail/                 # LocusDetailScreen, LocusDetailViewModel
        │   │   ├── search/                 # SearchScreen
        │   │   ├── settings/               # SettingsScreen
        │   │   ├── auth/                   # SignInScreen
        │   │   ├── onboarding/             # OnboardingScreen
        │   │   └── household/              # (Future: family sharing)
        │   └── component/
        │       ├── AudioWaveform.kt        # Canvas-based waveform
        │       ├── CategoryFilterChips.kt  # Horizontal scroll filter
        │       ├── CategorySelector.kt     # FlowRow grid
        │       ├── EmptyStateView.kt       # Empty state placeholder
        │       ├── ErrorBanner.kt          # Animated error display
        │       ├── LociateMapView.kt       # Google Maps Compose
        │       └── SkeletonView.kt         # Shimmer loading states
        └── util/
            ├── AppConstants.kt             # Tier limits, geofence config
            ├── NetworkMonitor.kt           # ConnectivityManager + StateFlow
            ├── SecurePreferences.kt        # EncryptedSharedPreferences
            ├── InputSanitizer.kt           # XSS prevention, validation
            └── HaversineDistance.kt         # Distance calculations
```
