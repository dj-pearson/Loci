import SwiftUI

struct CategoryPinView: View {
    let category: LocusCategory
    var isShared: Bool = false
    var isSelected: Bool = false
    var onTap: (() -> Void)?

    private let baseSize: CGFloat = 36
    private let borderWidth: CGFloat = 2

    private var pinSize: CGFloat {
        isSelected ? baseSize * 1.2 : baseSize
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(category.color)
                .frame(width: pinSize, height: pinSize)
                .overlay(
                    Circle()
                        .strokeBorder(.white, lineWidth: borderWidth)
                )
                .shadow(
                    color: isSelected ? .black.opacity(0.3) : .black.opacity(0.15),
                    radius: isSelected ? 6 : 3,
                    y: isSelected ? 4 : 2
                )

            Image(systemName: category.systemImageName)
                .font(.system(size: pinSize * 0.4, weight: .semibold))
                .foregroundStyle(.white)

            if isShared {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(2)
                    .background(Circle().fill(.black.opacity(0.6)))
                    .offset(x: pinSize / 2 - 4, y: -pinSize / 2 + 4)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        .onTapGesture {
            onTap?()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
    }

    func accessibilityConfigured(locationName: String?) -> some View {
        let location = locationName ?? String(localized: "Unknown location")
        return self
            .accessibilityLabel(String(localized: "\(category.displayName) note at \(location)"))
            .accessibilityHint(String(localized: "Double tap for details"))
    }
}

#Preview("All Categories") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 20) {
            ForEach(LocusCategory.allCases) { category in
                VStack(spacing: 8) {
                    CategoryPinView(category: category)
                    Text(category.displayName)
                        .font(.caption)
                }
            }
        }
        .padding()
    }
}

#Preview("Selected & Shared") {
    HStack(spacing: 24) {
        CategoryPinView(category: .food, isShared: false, isSelected: false)
        CategoryPinView(category: .food, isShared: true, isSelected: false)
        CategoryPinView(category: .food, isShared: false, isSelected: true)
        CategoryPinView(category: .food, isShared: true, isSelected: true)
    }
    .padding()
}
