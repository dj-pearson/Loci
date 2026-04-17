import SwiftUI
import UIKit

/// US-176: Real subscription management screen replacing the previous
/// `Text("Manage Subscription")` placeholder in Settings.
struct ManageSubscriptionView: View {
    @Environment(SubscriptionService.self) private var subscriptionService

    @State private var isRestoring = false
    @State private var restoreError: String?
    @State private var showPaywall = false

    private static let appStoreSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        Form {
            currentPlanSection
            manageSection
            actionsSection
        }
        .navigationTitle(String(localized: "Subscription"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            String(localized: "Restore Failed"),
            isPresented: Binding(
                get: { restoreError != nil },
                set: { if !$0 { restoreError = nil } }
            )
        ) {
            Button(String(localized: "OK"), role: .cancel) { restoreError = nil }
        } message: {
            Text(restoreError ?? "")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(subscriptionService: subscriptionService)
        }
    }

    // MARK: - Current Plan

    private var currentPlanSection: some View {
        Section(String(localized: "Current Plan")) {
            HStack(spacing: DesignSystem.Space.md) {
                RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
                    .fill(tierGradient)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: tierIcon)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                    )
                    .elevation(.level1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tierDisplayName)
                        .font(.headline)
                    Text(tierDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, DesignSystem.Space.xxs)
        }
    }

    // MARK: - Manage

    private var manageSection: some View {
        Section(String(localized: "Manage")) {
            if subscriptionService.currentTier == .free {
                Button {
                    showPaywall = true
                } label: {
                    Label(String(localized: "Upgrade"), systemImage: "crown.fill")
                }
            } else {
                Link(destination: Self.appStoreSubscriptionsURL) {
                    Label(String(localized: "Change or Cancel Plan"), systemImage: "arrow.up.forward.app")
                }
                .accessibilityHint(String(localized: "Opens your Apple ID subscriptions in the App Store"))
            }

            Button {
                Task { await restorePurchases() }
            } label: {
                if isRestoring {
                    HStack {
                        Label(String(localized: "Restoring..."), systemImage: "arrow.clockwise")
                        Spacer()
                        ProgressView()
                    }
                } else {
                    Label(String(localized: "Restore Purchases"), systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRestoring)
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section(String(localized: "Help")) {
            Link(destination: URL(string: "https://useloci.com/support")!) {
                Label(String(localized: "Subscription Support"), systemImage: "questionmark.circle")
            }
        }
    }

    // MARK: - Helpers

    private var tierDisplayName: String {
        switch subscriptionService.currentTier {
        case .free: String(localized: "Free")
        case .premium: String(localized: "Premium")
        case .family: String(localized: "Family")
        }
    }

    private var tierDescription: String {
        switch subscriptionService.currentTier {
        case .free:
            String(localized: "Up to 10 loci. Upgrade for sync, AI, and sharing.")
        case .premium:
            String(localized: "Unlimited loci, AI categorization, cloud sync, widget.")
        case .family:
            String(localized: "Premium for up to 6 household members.")
        }
    }

    private var tierIcon: String {
        switch subscriptionService.currentTier {
        case .free: "sparkles"
        case .premium: "crown.fill"
        case .family: "person.3.fill"
        }
    }

    private var tierGradient: LinearGradient {
        switch subscriptionService.currentTier {
        case .free: DesignSystem.Gradients.primary
        case .premium: DesignSystem.Gradients.premium
        case .family: DesignSystem.Gradients.family
        }
    }

    private func restorePurchases() async {
        isRestoring = true
        defer { isRestoring = false }
        do {
            try await subscriptionService.restorePurchases()
        } catch {
            restoreError = error.localizedDescription
        }
    }
}
