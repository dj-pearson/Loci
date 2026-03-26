import Foundation
import SwiftData

@Observable
final class PaginatedLocusQuery {
    // MARK: - Configuration

    static let pageSize = 20

    // MARK: - State

    private(set) var loci: [Locus] = []
    private(set) var hasMore = true
    private(set) var isLoading = false

    private var currentOffset = 0
    private var currentSortOrder: SortOrder = .reverse

    // MARK: - Sort Order

    enum SortOrder {
        case forward
        case reverse
    }

    // MARK: - Loading

    /// Loads the first page, resetting any prior results. Call when sort/filter changes.
    func reset(
        sortOrder: SortOrder = .reverse,
        modelContext: ModelContext
    ) {
        currentSortOrder = sortOrder
        currentOffset = 0
        loci = []
        hasMore = true
        loadMore(modelContext: modelContext)
    }

    /// Loads the next page of results and appends to existing loci.
    func loadMore(modelContext: ModelContext) {
        guard hasMore, !isLoading else { return }
        isLoading = true

        var descriptor = FetchDescriptor<Locus>(
            predicate: #Predicate<Locus> { !$0.isArchived }
        )

        switch currentSortOrder {
        case .reverse:
            descriptor.sortBy = [SortDescriptor(\Locus.createdAt, order: .reverse)]
        case .forward:
            descriptor.sortBy = [SortDescriptor(\Locus.createdAt, order: .forward)]
        }

        descriptor.fetchLimit = Self.pageSize
        descriptor.fetchOffset = currentOffset

        do {
            let page = try modelContext.fetch(descriptor)
            loci.append(contentsOf: page)
            currentOffset += page.count
            hasMore = page.count == Self.pageSize
        } catch {
            hasMore = false
        }

        isLoading = false
    }
}
