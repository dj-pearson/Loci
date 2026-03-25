import StoreKit
import SwiftUI

struct AboutView: View {
    @Environment(\.requestReview) private var requestReview

    var body: some View {
        Form {
            Section {
                HStack {
                    Label(String(localized: "Version"), systemImage: "info.circle")
                    Spacer()
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label(String(localized: "Build"), systemImage: "hammer")
                    Spacer()
                    Text(buildNumber)
                        .foregroundStyle(.secondary)
                }
            }

            Section(String(localized: "Legal")) {
                Link(destination: URL(string: "https://useloci.com/privacy")!) {
                    Label(String(localized: "Privacy Policy"), systemImage: "hand.raised")
                }

                Link(destination: URL(string: "https://useloci.com/terms")!) {
                    Label(String(localized: "Terms of Service"), systemImage: "doc.text")
                }
            }

            Section(String(localized: "Support")) {
                Link(destination: URL(string: "https://useloci.com/support")!) {
                    Label(String(localized: "Support & Feedback"), systemImage: "envelope")
                }

                Button {
                    requestReview()
                } label: {
                    Label(String(localized: "Rate on App Store"), systemImage: "star")
                }
            }

            Section {
                HStack {
                    Spacer()
                    VStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.title)
                            .foregroundStyle(Theme.primary)
                        Text(String(localized: "Made by Pearson Media LLC"))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }
        }
        .navigationTitle(String(localized: "About"))
    }

    // MARK: - Helpers

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
