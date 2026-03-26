import RevenueCat
import SwiftData
import SwiftUI

@main
struct LociApp: App {
    let modelContainer: ModelContainer

    @State private var navigationRouter = NavigationRouter()
    @State private var notificationService = NotificationService()
    @State private var locationService = LocationService()
    @State private var biometricService = BiometricLockService()

    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            modelContainer = try ModelContainerConfiguration.production()
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error.localizedDescription)")
        }

        RevenueCatConfiguration.configure()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environment(navigationRouter)
                    .environment(notificationService)
                    .environment(locationService)
                    .environment(biometricService)
                    .onOpenURL { url in
                        navigationRouter.handleURL(url)
                    }

                if biometricService.isLocked {
                    BiometricLockView(biometricService: biometricService)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: biometricService.isLocked)
            .onChange(of: scenePhase) { _, newPhase in
                switch newPhase {
                case .active:
                    biometricService.lockIfNeeded()
                case .background:
                    biometricService.recordBackgroundTransition()
                default:
                    break
                }
            }
        }
        .modelContainer(modelContainer)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var navigationRouter
    @Environment(LocationService.self) private var locationService
    @Environment(BiometricLockService.self) private var biometricService
    @Query(filter: #Predicate<Locus> { !$0.isArchived }) private var loci: [Locus]
    @Query private var householdMembers: [HouseholdMember]

    @State private var selectedTab: AppTab = .map
    @State private var mapViewModel: HomeMapViewModel?
    @State private var settingsViewModel = SettingsViewModel()
    @State private var householdViewModel = HouseholdViewModel()
    @State private var audioCacheManager = AudioCacheManager()

    var body: some View {
        @Bindable var router = navigationRouter

        TabView(selection: $selectedTab) {
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

/// Temporary detail view for deep-linked locus navigation.
/// Will be replaced by the full LocusDetailView in US-038.
struct LocusDeepLinkView: View {
    let locusId: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var allLoci: [Locus]

    private var locus: Locus? {
        allLoci.first { $0.id == locusId }
    }

    var body: some View {
        if let locus {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: locus.category.systemImageName)
                    .font(.system(size: 48))
                    .foregroundStyle(locus.category.color)

                Text(locus.locationName ?? String(localized: "Unknown Location"))
                    .font(Theme.Typography.title)

                Text(locus.transcription)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal)

                Text(locus.createdAt, style: .relative)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .navigationTitle(locus.category.displayName)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(
                String(localized: "Locus Not Found"),
                systemImage: "mappin.slash",
                description: Text("This note may have been deleted.")
            )
        }
    }
}
