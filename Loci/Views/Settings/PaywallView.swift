import RevenueCat
import SwiftUI

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptionService: SubscriptionService
    @State private var packages: [Package] = []
    @State private var isYearly = false
    @State private var isLoadingPackages = true
    @State private var purchaseError: String?

    init(subscriptionService: SubscriptionService) {
        _subscriptionService = State(initialValue: subscriptionService)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    headerSection
                    billingToggle
                    tierCards
                    lifetimeSection
                    featureComparisonGrid
                    restoreAndLegalSection
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.background)
            .navigationTitle(String(localized: "Choose Your Plan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Close")) {
                        dismiss()
                    }
                }
            }
            .alert(String(localized: "Error"), isPresented: .init(
                get: { purchaseError != nil },
                set: { if !$0 { purchaseError = nil } }
            )) {
                Button(String(localized: "OK"), role: .cancel) {}
            } message: {
                Text(purchaseError ?? "")
            }
            .task {
                await loadPackages()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 48))
                .foregroundStyle(Theme.primary)
                .padding(.top, Theme.Spacing.md)

            Text(String(localized: "Unlock the Full Loci Experience"))
                .font(Theme.Typography.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(String(localized: "Pin more memories, sync everywhere, and share with family."))
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Billing Toggle

    private var billingToggle: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(String(localized: "Monthly"))
                .font(Theme.Typography.body)
                .foregroundStyle(isYearly ? Theme.textSecondary : Theme.textPrimary)
                .fontWeight(isYearly ? .regular : .semibold)

            Toggle("", isOn: $isYearly)
                .labelsHidden()
                .tint(Theme.primary)

            HStack(spacing: Theme.Spacing.xs) {
                Text(String(localized: "Yearly"))
                    .font(Theme.Typography.body)
                    .foregroundStyle(isYearly ? Theme.textPrimary : Theme.textSecondary)
                    .fontWeight(isYearly ? .semibold : .regular)

                Text(String(localized: "Save 37%"))
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.success, in: Capsule())
            }
        }
        .padding(.vertical, Theme.Spacing.sm)
    }

    // MARK: - Tier Cards

    private var tierCards: some View {
        VStack(spacing: Theme.Spacing.md) {
            // Premium Card
            tierCard(
                title: String(localized: "Premium"),
                icon: "star.fill",
                color: Theme.primary,
                monthlyPrice: "$3.99",
                yearlyPrice: "$29.99",
                yearlyMonthly: "$2.49",
                features: [
                    String(localized: "Unlimited loci"),
                    String(localized: "AI categorization"),
                    String(localized: "Cloud sync & backup"),
                    String(localized: "Home screen widget"),
                    String(localized: "Full-text search"),
                ],
                trialBadge: true,
                package: packageFor(monthly: RevenueCatConfiguration.OfferingID.premiumMonthly,
                                    yearly: RevenueCatConfiguration.OfferingID.premiumYearly)
            )

            // Family Card
            tierCard(
                title: String(localized: "Family"),
                icon: "person.3.fill",
                color: Theme.secondary,
                monthlyPrice: "$5.99",
                yearlyPrice: "$44.99",
                yearlyMonthly: "$3.74",
                features: [
                    String(localized: "Everything in Premium"),
                    String(localized: "Family sharing (up to 6)"),
                    String(localized: "Shared household loci"),
                    String(localized: "Family member management"),
                ],
                trialBadge: true,
                package: packageFor(monthly: RevenueCatConfiguration.OfferingID.familyMonthly,
                                    yearly: RevenueCatConfiguration.OfferingID.familyYearly)
            )
        }
    }

    private func tierCard(
        title: String,
        icon: String,
        color: Color,
        monthlyPrice: String,
        yearlyPrice: String,
        yearlyMonthly: String,
        features: [String],
        trialBadge: Bool,
        package: Package?
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(Theme.Typography.headline)
                    .fontWeight(.bold)
                Spacer()
                if trialBadge {
                    Text(String(localized: "7-day free trial"))
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(color, in: Capsule())
                }
            }

            // Pricing
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                if isYearly {
                    Text(yearlyMonthly)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(color)
                    Text(String(localized: "/mo"))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text("(\(yearlyPrice)" + String(localized: "/yr") + ")")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    Text(monthlyPrice)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(color)
                    Text(String(localized: "/mo"))
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Divider()

            ForEach(features, id: \.self) { feature in
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(color)
                        .font(.caption)
                    Text(feature)
                        .font(Theme.Typography.body)
                }
            }

            Button {
                Task { await purchasePackage(package) }
            } label: {
                Group {
                    if subscriptionService.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(String(localized: "Start Free Trial"))
                    }
                }
                .font(Theme.Typography.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
                .background(color, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            }
            .disabled(subscriptionService.isLoading || package == nil)
            .padding(.top, Theme.Spacing.xs)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.large))
    }

    // MARK: - Lifetime Section

    private var lifetimeSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(String(localized: "Prefer a one-time purchase?"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: Theme.Spacing.md) {
                lifetimeButton(
                    title: String(localized: "Lifetime Individual"),
                    price: "$59.99",
                    promoPrice: "$39.99",
                    package: packageForId(RevenueCatConfiguration.OfferingID.lifetimeIndividual)
                )

                lifetimeButton(
                    title: String(localized: "Lifetime Family"),
                    price: "$89.99",
                    promoPrice: "$59.99",
                    package: packageForId(RevenueCatConfiguration.OfferingID.lifetimeFamily)
                )
            }

            Text(String(localized: "Launch promo pricing — limited time!"))
                .font(.caption2)
                .foregroundStyle(Theme.warning)
                .fontWeight(.medium)
        }
    }

    private func lifetimeButton(
        title: String,
        price: String,
        promoPrice: String,
        package: Package?
    ) -> some View {
        Button {
            Task { await purchasePackage(package) }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text(price)
                        .font(Theme.Typography.caption)
                        .strikethrough()
                        .foregroundStyle(Theme.textSecondary)
                    Text(promoPrice)
                        .font(Theme.Typography.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.sm)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.CornerRadius.small))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.CornerRadius.small)
                    .stroke(Theme.primary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(subscriptionService.isLoading || package == nil)
    }

    // MARK: - Feature Comparison Grid

    private var featureComparisonGrid: some View {
        VStack(spacing: 0) {
            Text(String(localized: "Feature Comparison"))
                .font(Theme.Typography.headline)
                .fontWeight(.bold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, Theme.Spacing.sm)

            // Header row
            HStack {
                Text(String(localized: "Feature"))
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(String(localized: "Free"))
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .frame(width: 55)
                Text(String(localized: "Premium"))
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .frame(width: 65)
                Text(String(localized: "Family"))
                    .font(Theme.Typography.caption)
                    .fontWeight(.semibold)
                    .frame(width: 55)
            }
            .padding(.vertical, Theme.Spacing.sm)
            .padding(.horizontal, Theme.Spacing.sm)
            .background(Theme.surface)

            comparisonRow(String(localized: "Loci limit"), free: "10", premium: "\u{221E}", family: "\u{221E}")
            comparisonRow(String(localized: "AI categorization"), free: false, premium: true, family: true)
            comparisonRow(String(localized: "Cloud sync"), free: false, premium: true, family: true)
            comparisonRow(String(localized: "Widget"), free: false, premium: true, family: true)
            comparisonRow(String(localized: "Search"), free: false, premium: true, family: true)
            comparisonRow(String(localized: "Family sharing"), free: false, premium: false, family: true)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }

    private func comparisonRow(_ feature: String, free: String, premium: String, family: String) -> some View {
        HStack {
            Text(feature)
                .font(Theme.Typography.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(free)
                .font(Theme.Typography.caption)
                .frame(width: 55)
            Text(premium)
                .font(Theme.Typography.caption)
                .frame(width: 65)
            Text(family)
                .font(Theme.Typography.caption)
                .frame(width: 55)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Theme.Spacing.sm)
    }

    private func comparisonRow(_ feature: String, free: Bool, premium: Bool, family: Bool) -> some View {
        HStack {
            Text(feature)
                .font(Theme.Typography.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
            comparisonIcon(free)
                .frame(width: 55)
            comparisonIcon(premium)
                .frame(width: 65)
            comparisonIcon(family)
                .frame(width: 55)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, Theme.Spacing.sm)
    }

    private func comparisonIcon(_ available: Bool) -> some View {
        Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
            .foregroundStyle(available ? Theme.success : Theme.textSecondary.opacity(0.5))
            .font(.caption)
    }

    // MARK: - Restore & Legal

    private var restoreAndLegalSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                Task { await restorePurchases() }
            } label: {
                if subscriptionService.isLoading {
                    ProgressView()
                } else {
                    Text(String(localized: "Restore Purchases"))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.primary)
                }
            }
            .disabled(subscriptionService.isLoading)

            HStack(spacing: Theme.Spacing.md) {
                Link(String(localized: "Terms of Service"),
                     destination: URL(string: "https://useloci.com/terms")!)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)

                Link(String(localized: "Privacy Policy"),
                     destination: URL(string: "https://useloci.com/privacy")!)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    // MARK: - Actions

    private func loadPackages() async {
        isLoadingPackages = true
        defer { isLoadingPackages = false }
        do {
            packages = try await subscriptionService.fetchOfferings()
        } catch {
            // Packages unavailable — buttons stay disabled (offline-first)
        }
    }

    private func purchasePackage(_ package: Package?) async {
        guard let package else { return }
        do {
            let success = try await subscriptionService.purchase(package)
            if success {
                dismiss()
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    private func restorePurchases() async {
        do {
            try await subscriptionService.restorePurchases()
            if subscriptionService.currentTier != .free {
                dismiss()
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Package Helpers

    private func packageFor(monthly: String, yearly: String) -> Package? {
        let id = isYearly ? yearly : monthly
        return packages.first { $0.identifier == id }
    }

    private func packageForId(_ id: String) -> Package? {
        packages.first { $0.identifier == id }
    }
}
