import CoreLocation
import SwiftUI

struct SearchResultsView: View {
    let results: [Locus]
    let query: String
    let userLocation: CLLocation?
    let navigationRouter: NavigationRouter

    var body: some View {
        if results.isEmpty {
            EmptyStateView.search()
        } else {
            List {
                Section {
                    ForEach(results) { locus in
                        Button {
                            navigationRouter.selectedLocusId = locus.id
                        } label: {
                            SearchResultRow(
                                locus: locus,
                                query: query,
                                userLocation: userLocation
                            )
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(resultCountText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var resultCountText: String {
        if query.isEmpty {
            return String(localized: "\(results.count) results")
        }
        return String(localized: "\(results.count) results for \"\(query)\"")
    }
}

// MARK: - Search Result Row

private struct SearchResultRow: View {
    let locus: Locus
    let query: String
    let userLocation: CLLocation?

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(locus.category.color)
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: locus.category.systemImageName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                if locus.transcription.isEmpty {
                    Text(String(localized: "Voice Note"))
                        .font(.subheadline)
                        .lineLimit(2)
                } else {
                    highlightedText(locus.transcription, query: query)
                        .font(.subheadline)
                        .lineLimit(2)
                }

                HStack(spacing: 6) {
                    if let name = locus.locationName {
                        if !query.isEmpty {
                            highlightedText(name, query: query)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(locus.createdAt.formatted(.relative(presentation: .named)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let userLocation {
                let distance = locus.coordinate.distance(to: userLocation.coordinate)
                Text(formatDistance(distance))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func highlightedText(_ text: String, query: String) -> Text {
        guard !query.isEmpty else { return Text(text) }

        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()

        var result = Text("")
        var currentIndex = text.startIndex

        while currentIndex < text.endIndex {
            let remaining = text[currentIndex...]
            let remainingLower = lowercasedText[currentIndex...]

            if let range = remainingLower.range(of: lowercasedQuery) {
                // Add non-matching text before the match
                if currentIndex < range.lowerBound {
                    result = result + Text(text[currentIndex..<range.lowerBound])
                }

                // Add the matched text with highlight
                result = result + Text(text[range])
                    .bold()
                    .foregroundColor(Theme.primary)

                currentIndex = range.upperBound
            } else {
                // No more matches — add the rest
                result = result + Text(remaining)
                break
            }
        }

        return result
    }

    private func formatDistance(_ meters: CLLocationDistance) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        let formatter = MeasurementFormatter()
        formatter.unitOptions = .naturalScale
        formatter.numberFormatter.maximumFractionDigits = 1
        return formatter.string(from: measurement)
    }
}
