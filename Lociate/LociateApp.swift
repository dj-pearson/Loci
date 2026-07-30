import SwiftData
import SwiftUI

@main
struct LociateApp: App {
    let modelContainer: ModelContainer

    // US-195: required for the APNs device-token callbacks — SwiftUI exposes no
    // equivalent hook, so without this adaptor no push token is ever received.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @State private var navigationRouter = NavigationRouter()
    @State private var notificationService = NotificationService()
    @State private var locationService = LocationService()
    @State private var biometricService = BiometricLockService()
    @State private var networkMonitor = NetworkMonitor()
    // US-176: AuthService is required by SignInView / ReAuthView. Previously it
    // was never injected, which meant the (stubbed) Sign In link would have
    // crashed at runtime.
    @State private var authService = AuthService()
    @State private var subscriptionService = SubscriptionService()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        // US-177: Only the minimum required to stand up the main actor + first
        // frame belongs here. Anything that can wait is deferred to `.task` on
        // ContentView so launch-to-interactive is not blocked by SDK network I/O.
        do {
            modelContainer = try ModelContainerConfiguration.production()
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error.localizedDescription)")
        }

        BuildSecretsValidator.validate()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(navigationRouter)
                    .environment(notificationService)
                    .environment(locationService)
                    .environment(biometricService)
                    .environment(networkMonitor)
                    .environment(authService)
                    .environment(subscriptionService)
                    .onOpenURL { url in
                        navigationRouter.handleURL(url)
                    }

                if biometricService.isLocked {
                    BiometricLockView(biometricService: biometricService)
                        .transition(.opacity)
                }

                // US-175: Cover sensitive content (maps, transcripts, location names)
                // whenever the app is not .active so the iOS app switcher snapshot
                // and brief .inactive states (Control Center, Notification Center) do
                // not leak user data.
                if scenePhase != .active {
                    PrivacyScreenOverlay()
                        .transition(.opacity)
                        .ignoresSafeArea()
                }
            }
            .animation(.easeInOut(duration: 0.15), value: biometricService.isLocked)
            .animation(.easeInOut(duration: 0.15), value: scenePhase)
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    biometricService.lockIfNeeded()
                    Task {
                        await notificationService.checkAuthorizationStatus()
                        // US-195: register once permission exists, and flush any
                        // token that could not be persisted earlier (offline, or
                        // obtained before the user signed in).
                        PushRegistrationService.shared
                            .registerIfAuthorized(isAuthorized: notificationService.isAuthorized)
                        await PushRegistrationService.shared.syncPendingToken()
                    }
                    notificationService.deliverQueuedNotifications()
                case .background:
                    biometricService.recordBackgroundTransition()
                    // US-178: Purge any plaintext decrypted audio left in /tmp.
                    AudioEncryptionService.cleanupTempFiles()
                default:
                    break
                }
            }
        }
        .modelContainer(modelContainer)
    }
}

/// US-175: Full-screen overlay that masks sensitive UI whenever the scene is not
/// .active. Renders a branded blurred surface with the app mark.
private struct PrivacyScreenOverlay: View {
    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
            VStack(spacing: 12) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.tint)
                Text("Lociate")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .accessibilityHidden(true)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var navigationRouter
    @Environment(LocationService.self) private var locationService
    @Environment(NotificationService.self) private var notificationService
    @Environment(BiometricLockService.self) private var biometricService
    @Query(filter: #Predicate<Locus> { !$0.isArchived }) private var loci: [Locus]
    @Query private var householdMembers: [HouseholdMember]

    @State private var selectedTab: AppTab = .map
    @State private var mapViewModel: HomeMapViewModel?
    @State private var settingsViewModel = SettingsViewModel()
    @State private var householdViewModel = HouseholdViewModel()
    @State private var audioCacheManager = AudioCacheManager()
    @State private var onboardingViewModel = OnboardingViewModel()

    var body: some View {
        Group {
            if !onboardingViewModel.hasCompletedOnboarding {
                OnboardingFlowView(
                    viewModel: onboardingViewModel,
                    locationService: locationService,
                    notificationService: notificationService
                )
            } else {
                VStack(spacing: 0) {
                    // US-148: Show integrity warning banner if device is compromised
                    IntegrityWarningBanner(issues: IntegrityCheckService.shared.detectedIssues)

                    mainAppView
                }
            }
        }
        // US-177: Deferred launch work — runs after the first frame so
        // RevenueCat, Analytics, and integrity checks never block startup.
        .task(priority: .utility) {
            RevenueCatConfiguration.configure()
            AnalyticsService.shared.configure()
            AnalyticsService.shared.trackAppLaunch()
            IntegrityCheckService.shared.performChecks()
        }
    }

    private var mainAppView: some View {
        @Bindable var router = navigationRouter

        return TabView(selection: $selectedTab) {
            // Map Tab
            NavigationStack {
                ZStack(alignment: .top) {
                    if let vm = mapViewModel {
                        HomeMapView(
                            viewModel: vm,
                            navigationRouter: navigationRouter
                        )
                    }

                    if let vm = mapViewModel {
                        CategoryFilterBar(
                            selectedCategories: Bindable(vm).selectedCategories,
                            lociCounts: lociCountsByCategory,
                            showFamilyLoci: hasHousehold ? Bindable(vm).showFamilyLoci : nil
                        )
                        .background(.ultraThinMaterial)
                    }
                }
                .navigationDestination(item: $router.selectedLocusId) { locusId in
                    LocusDeepLinkView(locusId: locusId)
                }
            }
            .tabItem {
                Label(String(localized: "Map"), systemImage: "map.fill")
            }
            .tag(AppTab.map)
            .accessibilityLabel(String(localized: "Map"))
            .accessibilityHint(String(localized: "View voice notes on a map"))

            // List Tab
            NavigationStack {
                if let vm = mapViewModel {
                    LocusListView(
                        viewModel: vm,
                        locationService: locationService,
                        navigationRouter: navigationRouter
                    )
                    .navigationTitle(String(localized: "Loci"))
                    .navigationDestination(item: $router.selectedLocusId) { locusId in
                        LocusDeepLinkView(locusId: locusId)
                    }
                }
            }
            .tabItem {
                Label(String(localized: "List"), systemImage: "list.bullet")
            }
            .tag(AppTab.list)
            .accessibilityLabel(String(localized: "List"))
            .accessibilityHint(String(localized: "Browse voice notes in a list"))

            // Settings Tab
            NavigationStack {
                SettingsView(
                    viewModel: settingsViewModel,
                    householdViewModel: householdViewModel,
                    biometricService: biometricService
                )
            }
            .tabItem {
                Label(String(localized: "Settings"), systemImage: "gearshape.fill")
            }
            .tag(AppTab.settings)
            .accessibilityLabel(String(localized: "Settings"))
            .accessibilityHint(String(localized: "App preferences and account"))
        }
        .symbolRenderingMode(.hierarchical)
        .onAppear {
            if mapViewModel == nil {
                mapViewModel = HomeMapViewModel(locationService: locationService)
            }
            navigationRouter.consumePendingDeepLink()
            audioCacheManager.cleanupIfNeeded(modelContext: modelContext)
        }
    }

    private var hasHousehold: Bool {
        !householdMembers.isEmpty
    }

    private var lociCountsByCategory: [LocusCategory: Int] {
        var counts: [LocusCategory: Int] = [:]
        for locus in loci {
            counts[locus.category, default: 0] += 1
        }
        return counts
    }
}

enum AppTab: Hashable {
    case map
    case list
    case settings
}

/// Resolves a locus ID from deep-link/notification into the full LocusDetailView.
struct LocusDeepLinkView: View {
    let locusId: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var allLoci: [Locus]

    private var locus: Locus? {
        allLoci.first { $0.id == locusId }
    }

    var body: some View {
        if let locus {
            LocusDetailView(
                viewModel: LocusDetailViewModel(locus: locus)
            )
        } else {
            ContentUnavailableView(
                String(localized: "Locus Not Found"),
                systemImage: "mappin.slash",
                description: Text(String(localized: "This note may have been deleted."))
            )
        }
    }
}
