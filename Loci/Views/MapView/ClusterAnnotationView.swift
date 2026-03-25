import MapKit
import SwiftUI

struct ClusterAnnotationView: View {
    let count: Int
    let dominantCategory: LocusCategory
    var onTap: (() -> Void)?

    private let size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(dominantCategory.color.opacity(0.85))
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)

            Text("\(count)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .onTapGesture {
            onTap?()
        }
    }
}

// MARK: - Clustering Logic

struct LocusCluster: Identifiable {
    let id = UUID()
    let loci: [Locus]

    var coordinate: CLLocationCoordinate2D {
        let avgLat = loci.map(\.latitude).reduce(0, +) / Double(loci.count)
        let avgLon = loci.map(\.longitude).reduce(0, +) / Double(loci.count)
        return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
    }

    var dominantCategory: LocusCategory {
        var counts: [LocusCategory: Int] = [:]
        for locus in loci {
            counts[locus.category, default: 0] += 1
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? .general
    }

    var boundingRegion: MKCoordinateRegion {
        guard !loci.isEmpty else {
            return MKCoordinateRegion()
        }
        let lats = loci.map(\.latitude)
        let lons = loci.map(\.longitude)
        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLon = lons.min()!
        let maxLon = lons.max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.5 + 0.005,
            longitudeDelta: (maxLon - minLon) * 1.5 + 0.005
        )
        return MKCoordinateRegion(center: center, span: span)
    }
}

enum LocusClusterEngine {
    /// Clusters loci that are within `thresholdPoints` screen distance of each other.
    /// Returns a mix of single-locus entries and multi-locus clusters.
    static func cluster(
        loci: [Locus],
        region: MKCoordinateRegion,
        screenWidth: CGFloat,
        thresholdPoints: CGFloat = 60
    ) -> (singles: [Locus], clusters: [LocusCluster]) {
        guard !loci.isEmpty else { return ([], []) }

        // Convert threshold from screen points to degrees (approximate)
        let degreesPerPointLat = region.span.latitudeDelta / Double(screenWidth)
        let degreesPerPointLon = region.span.longitudeDelta / Double(screenWidth)
        let thresholdLat = Double(thresholdPoints) * degreesPerPointLat
        let thresholdLon = Double(thresholdPoints) * degreesPerPointLon

        var assigned = [Bool](repeating: false, count: loci.count)
        var clusters: [LocusCluster] = []
        var singles: [Locus] = []

        for i in 0..<loci.count {
            guard !assigned[i] else { continue }

            var group = [loci[i]]
            assigned[i] = true

            for j in (i + 1)..<loci.count {
                guard !assigned[j] else { continue }

                let dLat = abs(loci[i].latitude - loci[j].latitude)
                let dLon = abs(loci[i].longitude - loci[j].longitude)

                if dLat < thresholdLat && dLon < thresholdLon {
                    group.append(loci[j])
                    assigned[j] = true
                }
            }

            if group.count == 1 {
                singles.append(group[0])
            } else {
                clusters.append(LocusCluster(loci: group))
            }
        }

        return (singles, clusters)
    }
}

#Preview {
    HStack(spacing: 20) {
        ClusterAnnotationView(count: 3, dominantCategory: .food)
        ClusterAnnotationView(count: 12, dominantCategory: .travel)
        ClusterAnnotationView(count: 99, dominantCategory: .warning)
    }
    .padding()
}
