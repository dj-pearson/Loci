import Combine
import CoreLocation
import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(filter: #Predicate<Locus> { !$0.isArchived })
    private var allLoci: [Locus]

    let searchService: SearchService
    let locationService: LocationService
    let navigationRouter: NavigationRouter

    @State private var searchText = ""
    @State private var debouncedText = ""
    @State private var selectedCategories: Set<LocusCategory> = []
    @State private var recentSearches: [String] = UserDefaults.standard.recentSearches

    private var results: [Locus] {
        if debouncedText.isEmpty && selectedCategories.isEmpty {
            return []
        }

        var loci: [Locus]

        if !debouncedText.isEmpty {
            loci = searchService.searchByKeyword(debouncedText, in: modelContext)
        } else {
            loci = allLoci
        }

        if !selectedCategories.isEmpty {
            loci = loci.filter { selectedCategories.contains($0.category) }
        }

        return loci
    }

    private var isSearchActive: Bool {
        !debouncedText.isEmpty || !selectedCategories.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            CategoryFilterBar(
                selectedCategories: $selectedCategories,
                lociCounts: categoryCounts
            )

            if isSearchActive {
                SearchResultsView(
                    results: results,
                    query: debouncedText,
                    userLocation: locationService.currentLocation,
                    navigationRouter: navigationRouter
                )
            } else {
                recentSearchesList
            }
        }
        .searchable(
            text: $searchText,
            prompt: String(localized: "Search loci...")
        )
        .onChange(of: searchText) { _, newValue in
            debounceSearch(newValue)
        }
        .onSubmit(of: .search) {
            commitSearch(searchText)
        }
    }

    // MARK: - Recent Searches

    private var recentSearchesList: some View {
        Group {
            if recentSearches.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: String(localized: "Search Your Loci"),
                    subtitle: String(localized: "Find voice notes by keyword, category, or location name.")
                )
            } else {
                List {
                    Section {
                        ForEach(recentSearches, id: \.self) { query in
                            Button {
                                searchText = query
                                commitSearch(query)
                            } label: {
                                HStack {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(.secondary)
                                    Text(query)
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text(String(localized: "Recent Searches"))
                            Spacer()
                            Button(String(localized: "Clear")) {
                                clearRecentSearches()
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.primary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    // MARK: - Helpers

    private var categoryCounts: [LocusCategory: Int] {
        var counts: [LocusCategory: Int] = [:]
        for locus in allLoci {
            counts[locus.category, default: 0] += 1
        }
        return counts
    }

    private var debounceTask: Task<Void, Never>? {
        nil
    }

    @State private var pendingDebounce: Task<Void, Never>?

    private func debounceSearch(_ query: String) {
        pendingDebounce?.cancel()
        pendingDebounce = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            debouncedText = query
        }
    }

    private func commitSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        debouncedText = trimmed

        var searches = recentSearches
        searches.removeAll { $0 == trimmed }
        searches.insert(trimmed, at: 0)
        if searches.count > 10 {
            searches = Array(searches.prefix(10))
        }
        recentSearches = searches
        UserDefaults.standard.recentSearches = searches
    }

    private func clearRecentSearches() {
        recentSearches = []
        UserDefaults.standard.recentSearches = []
    }
}

// MARK: - UserDefaults Recent Searches

private extension UserDefaults {
    private static let recentSearchesKey = "loci_recent_searches"

    var recentSearches: [String] {
        get { stringArray(forKey: Self.recentSearchesKey) ?? [] }
        set { set(newValue, forKey: Self.recentSearchesKey) }
    }
}
