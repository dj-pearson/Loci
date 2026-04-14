import SwiftUI

struct WelcomeOnboardingView: View {
    let onFinish: () -> Void
    let onSkip: () -> Void

    @State private var currentPage = 0

    private let pages: [(systemImage: String, headline: String, body: String)] = [
        (
            "mappin.and.ellipse",
            String(localized: "Your Spatial Memory"),
            String(localized: "Record voice notes and pin them to your current location. Your memories live where they happened.")
        ),
        (
            "bell.badge",
            String(localized: "Notes Find You"),
            String(localized: "When you return to a saved location, Loci notifies you automatically. Never forget what you wanted to remember.")
        ),
        (
            "person.2.fill",
            String(localized: "Share with Family"),
            String(localized: "Create a household and share voice notes with your family. Leave tips, reminders, and memories for each other.")
        ),
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(
                        systemImage: page.systemImage,
                        headline: page.headline,
                        bodyText: page.body,
                        ctaTitle: index < pages.count - 1
                            ? String(localized: "Next")
                            : String(localized: "Get Started")
                    ) {
                        if index < pages.count - 1 {
                            withAnimation {
                                currentPage = index + 1
                            }
                        } else {
                            onFinish()
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(String(localized: "Skip")) {
                onSkip()
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)
        }
    }
}

#Preview {
    WelcomeOnboardingView(onFinish: { }, onSkip: { })
}
