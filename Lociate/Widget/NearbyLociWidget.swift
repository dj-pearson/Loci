import SwiftUI
import WidgetKit

struct NearbyLociWidget: Widget {
    let kind = "NearbyLociWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NearbyLociTimelineProvider()) { entry in
            NearbyLociWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName(String(localized: "Nearby Loci"))
        .description(String(localized: "See your nearest voice notes at a glance."))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Entry View

struct NearbyLociWidgetEntryView: View {
    let entry: NearbyLociEntry

    @Environment(\.widgetFamily) var widgetFamily

    var body: some View {
        if entry.isLocked {
            lockedState
        } else if entry.loci.isEmpty {
            emptyState
        } else {
            switch widgetFamily {
            case .systemSmall:
                smallWidget
            case .systemMedium:
                mediumWidget
            default:
                smallWidget
            }
        }
    }

    // MARK: - Small Widget

    private var smallWidget: some View {
        let locus = entry.loci[0]
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: locus.category.systemImageName)
                    .font(.title3)
                    .foregroundStyle(locus.category.color)
                Spacer()
                Text(locus.formattedDistance)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let locationName = locus.locationName {
                Text(locationName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Text(locus.transcription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .widgetURL(URL(string: "lociate://locus/\(locus.id.uuidString)"))
    }

    // MARK: - Medium Widget

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption)
                    .foregroundStyle(.blue)
                Text(String(localized: "Nearby Loci"))
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.bottom, 2)

            ForEach(entry.loci.prefix(3)) { locus in
                Link(destination: URL(string: "lociate://locus/\(locus.id.uuidString)")!) {
                    HStack(spacing: 8) {
                        Image(systemName: locus.category.systemImageName)
                            .font(.caption)
                            .foregroundStyle(locus.category.color)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(locus.locationName ?? locus.category.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Text(locus.transcription)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(locus.formattedDistance)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Locked State

    private var lockedState: some View {
        VStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(String(localized: "Upgrade to Premium"))
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
            Text(String(localized: "See nearby loci on your home screen"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "lociate://paywall"))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "mappin.slash")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(localized: "No nearby loci"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    NearbyLociWidget()
} timeline: {
    NearbyLociEntry(date: .now, loci: NearbyLociTimelineProvider.sampleData)
}

#Preview("Medium", as: .systemMedium) {
    NearbyLociWidget()
} timeline: {
    NearbyLociEntry(date: .now, loci: NearbyLociTimelineProvider.sampleData)
}

#Preview("Empty", as: .systemSmall) {
    NearbyLociWidget()
} timeline: {
    NearbyLociEntry(date: .now, loci: [])
}
