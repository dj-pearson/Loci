import SwiftData
import SwiftUI

@main
struct LociApp: App {
    let modelContainer: ModelContainer

    @State private var navigationRouter = NavigationRouter()
    @State private var notificationService = NotificationService()

    init() {
        do {
            modelContainer = try ModelContainerConfiguration.production()
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(navigationRouter)
                .environment(notificationService)
        }
        .modelContainer(modelContainer)
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(NavigationRouter.self) private var navigationRouter
    @Query(filter: #Predicate<Locus> { !$0.isArchived }) private var loci: [Locus]

    var body: some View {
        @Bindable var router = navigationRouter

        NavigationStack {
            VStack {
                Text("Loci")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Placeholder list of loci for deep-link navigation testing
                ForEach(loci) { locus in
                    NavigationLink(value: locus.id) {
                        Text(locus.locationName ?? locus.category.displayName)
                    }
                }
            }
            .navigationDestination(for: UUID.self) { locusId in
                LocusDeepLinkView(locusId: locusId)
            }
            .navigationDestination(item: $router.selectedLocusId) { locusId in
                LocusDeepLinkView(locusId: locusId)
            }
        }
        .onAppear {
            navigationRouter.consumePendingDeepLink()
        }
    }
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
