import SwiftUI

struct CategoryFilterBar: View {
    @Binding var selectedCategories: Set<LocusCategory>
    var lociCounts: [LocusCategory: Int] = [:]

    private var allSelected: Bool {
        selectedCategories.count == LocusCategory.allCases.count
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
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
                    .font(.system(size: 12, weight: .semibold))

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
