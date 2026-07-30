import SwiftUI

// MARK: - Shimmer Modifier

struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    if reduceMotion {
                        Color.clear
                    } else {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                .clear,
                                .white.opacity(0.3),
                                .clear,
                            ]),
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 2)
                        .offset(x: phase * geometry.size.width)
                        .onAppear {
                            withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                                phase = 1
                            }
                        }
                    }
                }
            )
            .clipped()
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Skeleton Shape

struct SkeletonShape: View {
    var width: CGFloat?
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.textSecondary.opacity(0.12))
            .frame(width: width, height: height)
            .shimmer()
    }
}

// MARK: - Locus Row Skeleton

struct LocusRowSkeleton: View {
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.textSecondary.opacity(0.12))
                .frame(width: 36, height: 36)
                .shimmer()

            VStack(alignment: .leading, spacing: 6) {
                SkeletonShape(width: 180, height: 14)
                SkeletonShape(width: 120, height: 12)
            }

            Spacer()

            SkeletonShape(width: 40, height: 12)
        }
        .padding(.vertical, 2)
        .accessibilityLabel(String(localized: "Loading voice note"))
    }
}

// MARK: - Map Skeleton

struct MapSkeleton: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.CornerRadius.large)
                .fill(Theme.textSecondary.opacity(0.08))
                .shimmer()

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "map")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.textSecondary.opacity(0.3))

                SkeletonShape(width: 120, height: 14)
            }
        }
        .accessibilityLabel(String(localized: "Loading map"))
    }
}

// MARK: - Detail Skeleton

struct DetailSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            // Playback bar placeholder
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(Theme.textSecondary.opacity(0.12))
                    .frame(width: 40, height: 40)
                    .shimmer()

                VStack(alignment: .leading, spacing: 4) {
                    SkeletonShape(height: 6, cornerRadius: 3)
                    SkeletonShape(width: 60, height: 10)
                }
            }
            .padding(Theme.Spacing.md)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))

            // Transcription placeholder
            VStack(alignment: .leading, spacing: 8) {
                SkeletonShape(height: 14)
                SkeletonShape(height: 14)
                SkeletonShape(width: 200, height: 14)
            }
            .padding(Theme.Spacing.md)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))

            // Metadata fields
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                metadataRow
                metadataRow
                metadataRow
            }
            .padding(Theme.Spacing.md)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .accessibilityLabel(String(localized: "Loading voice note details"))
    }

    private var metadataRow: some View {
        HStack {
            SkeletonShape(width: 80, height: 12)
            Spacer()
            SkeletonShape(width: 120, height: 12)
        }
    }
}

// MARK: - Previews

#Preview("Row Skeleton") {
    List {
        LocusRowSkeleton()
        LocusRowSkeleton()
        LocusRowSkeleton()
    }
    .listStyle(.insetGrouped)
}

#Preview("Map Skeleton") {
    MapSkeleton()
        .frame(height: 300)
        .padding()
}

#Preview("Detail Skeleton") {
    DetailSkeleton()
}
