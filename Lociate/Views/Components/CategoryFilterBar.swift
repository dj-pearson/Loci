import SwiftUI

struct CategoryFilterBar: View {
    @Binding var selectedCategories: Set<LocusCategory>
    var lociCounts: [LocusCategory: Int] = [:]
    var showFamilyLoci: Binding<Bool>?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var allSelected: Bool {
        selectedCategories.count == LocusCategory.allCases.count
    }

    /// At accessibility sizes, category pills need more room — use wrapping layout.
    private var usesWrappingLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        if usesWrappingLayout {
            ScrollView(.vertical, showsIndicators: false) {
                wrappingContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .frame(maxHeight: 200)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                horizontalContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
        }
    }

    private var horizontalContent: some View {
        HStack(spacing: 8) {
            chipContents
        }
    }

    private var wrappingContent: some View {
        FlowLayout(spacing: 8) {
            chipContents
        }
    }

    @ViewBuilder
    private var chipContents: some View {
        // "All" chip
        FilterChip(
            label: String(localized: "All"),
            systemImage: "line.3.horizontal.decrease.circle",
            count: nil,
            isSelected: allSelected,
            selectedColor: Theme.primary
        ) {
            if allSelected {
                selectedCategories.removeAll()
            } else {
                selectedCategories = Set(LocusCategory.allCases)
            }
        }

        // Family filter chip (only shown when binding is provided)
        if let showFamily = showFamilyLoci {
            FilterChip(
                label: String(localized: "Family"),
                systemImage: "person.2.fill",
                count: nil,
                isSelected: showFamily.wrappedValue,
                selectedColor: Theme.secondary
            ) {
                showFamily.wrappedValue.toggle()
            }
        }

        ForEach(LocusCategory.allCases) { category in
            let isSelected = selectedCategories.contains(category)
            let count = lociCounts[category] ?? 0

            FilterChip(
                label: category.displayName,
                systemImage: category.systemImageName,
                count: count > 0 ? count : nil,
                isSelected: isSelected,
                selectedColor: category.color
            ) {
                if isSelected {
                    selectedCategories.remove(category)
                } else {
                    selectedCategories.insert(category)
                }
            }
        }
    }
}

// MARK: - Flow Layout

/// A wrapping layout that arranges children horizontally, flowing to the next line when needed.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalWidth = max(totalWidth, currentX - spacing)
        }

        return (
            size: CGSize(width: totalWidth, height: currentY + lineHeight),
            positions: positions
        )
    }
}

// MARK: - Filter Chip

private struct FilterChip: View {
    let label: String
    let systemImage: String
    let count: Int?
    let isSelected: Bool
    let selectedColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .imageScale(.small)

                Text(label)
                    .font(.caption.weight(.medium))

                if let count {
                    Text("\(count)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? .white.opacity(0.3) : Theme.textSecondary.opacity(0.15))
                        )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isSelected ? selectedColor : Theme.surface)
            )
            .foregroundStyle(isSelected ? .white : Theme.textPrimary)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) filter")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    CategoryFilterBar(
        selectedCategories: .constant(Set([.food, .travel, .home])),
        lociCounts: [.food: 5, .travel: 2, .home: 8, .parking: 1]
    )
}
