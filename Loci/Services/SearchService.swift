import CoreLocation
import Foundation
import SwiftData

@Observable
final class SearchService {

    // MARK: - Keyword Search

    /// Searches loci by keyword against transcription and locationName (case-insensitive).
    /// Results are sorted by relevance (match count) then recency.
    func searchByKeyword(_ query: String, in context: ModelContext) -> [Locus] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        let allLoci = fetchNonArchivedLoci(in: context)
        let lowercasedQuery = query.lowercased()

        var scored: [(locus: Locus, matchCount: Int)] = []

        for locus in allLoci {
            var matchCount = 0

            let transcription = locus.transcription.lowercased()
            matchCount += transcription.occurrenceCount(of: lowercasedQuery)

            if let locationName = locus.locationName?.lowercased() {
                matchCount += locationName.occurrenceCount(of: lowercasedQuery)
            }

            if matchCount > 0 {
                scored.append((locus, matchCount))
            }
        }

        // Sort by match count descending, then by recency descending
        scored.sort { lhs, rhs in
            if lhs.matchCount != rhs.matchCount {
                return lhs.matchCount > rhs.matchCount
            }
            return lhs.locus.createdAt > rhs.locus.createdAt
        }

        return scored.map(\.locus)
    }

    // MARK: - Category Search

    /// Returns all non-archived loci matching the given category, sorted by recency.
    func searchByCategory(_ category: LocusCategory, in context: ModelContext) -> [Locus] {
        let categoryRaw = category.rawValue
        let predicate = #Predicate<Locus> { locus in
            !locus.isArchived && locus.categoryRawValue == categoryRaw
        }

        let descriptor = FetchDescriptor<Locus>(
            predicate: predicate,
            sortBy: [SortDescriptor(\Locus.createdAt, order: .reverse)]
        )

        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Nearby Search

    /// Returns all non-archived loci within the given radius (meters) of the location,
    /// sorted by distance ascending.
    func searchNearby(
        location: CLLocationCoordinate2D,
        radius: Double,
        in context: ModelContext
    ) -> [Locus] {
        let allLoci = fetchNonArchivedLoci(in: context)

        let nearby = allLoci.filter { locus in
            locus.coordinate.distance(to: location) <= radius
        }

        return nearby.sortedByDistance(from: location)
    }

    // MARK: - Private Helpers

    private func fetchNonArchivedLoci(in context: ModelContext) -> [Locus] {
        let predicate = #Predicate<Locus> { !$0.isArchived }
        let descriptor = FetchDescriptor<Locus>(predicate: predicate)
        return (try? context.fetch(descriptor)) ?? []
    }
}

// MARK: - String Occurrence Counting

private extension String {
    /// Counts non-overlapping occurrences of a substring.
    func occurrenceCount(of substring: String) -> Int {
        guard !substring.isEmpty else { return 0 }
        var count = 0
        var searchRange = startIndex..<endIndex
        while let range = range(of: substring, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = range.upperBound..<endIndex
        }
        return count
    }
}
