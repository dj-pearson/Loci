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

    // MARK: - Header (US-170 premium hero)

    @State private var heroPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var headerSection: some View {
        ZStack {
            // Animated parallax halo backdrop.
            Circle()
                .fill(DesignSystem.Gradients.primaryHalo)
                .frame(width: 340, height: 340)
                .scaleEffect(reduceMotion ? 1.0 : (heroPulse ? 1.08 : 0.92))
                .opacity(reduceMotion ? 0.55 : (heroPulse ? 0.4 : 0.75))
                .animation(
                    reduceMotion
                        ? nil
                        : DesignSystem.Motion.gentle.repeatForever(autoreverses: true),
                    value: heroPulse
                )
                .allowsHitTesting(false)

            VStack(spacing: DesignSystem.Space.sm) {
                // Hero icon tile on a gradient background.
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.lg, style: .continuous)
                        .fill(DesignSystem.Gradients.premium)
                        .frame(width: 96, height: 96)
                        .elevation(.level4)

                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                }
                .padding(.top, DesignSystem.Space.md)

                Text(String(localized: "Unlock the Full Lociate Experience"))
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .padding(.top, DesignSystem.Space.xs)

                Text(String(localized: "Pin more memories, sync everywhere, and share with family."))
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DesignSystem.Space.sm)
            }
        }
        .onAppear { heroPulse = true }
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

                Text(savingsText)
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

    private var savingsText: String {
        let monthlyPkg = packageForId(RevenueCatConfiguration.OfferingID.premiumMonthly)
        let yearlyPkg = packageForId(RevenueCatConfiguration.OfferingID.premiumYearly)
        guard let monthlyPrice = monthlyPkg?.storeProduct.price as? NSDecimalNumber,
              let yearlyPrice = yearlyPkg?.storeProduct.price as? NSDecimalNumber else {
            return String(localized: "Save 37%")
        }
        let annualMonthly = monthlyPrice.doubleValue * 12
        let savings = ((annualMonthly - yearlyPrice.doubleValue) / annualMonthly) * 100
        return String(localized: "Save \(Int(savings.rounded()))%")
    }

    // MARK: - Tier Cards

    private var tierCards: some View {
        let premiumMonthlyPkg = packageForId(RevenueCatConfiguration.OfferingID.premiumMonthly)
        let premiumYearlyPkg = packageForId(RevenueCatConfiguration.OfferingID.premiumYearly)
        let familyMonthlyPkg = packageForId(RevenueCatConfiguration.OfferingID.familyMonthly)
        let familyYearlyPkg = packageForId(RevenueCatConfiguration.OfferingID.familyYearly)

        return VStack(spacing: Theme.Spacing.md) {
            // Premium Card
            tierCard(
                title: String(localized: "Premium"),
                icon: "star.fill",
                color: Theme.primary,
                monthlyPrice: premiumMonthlyPkg?.localizedPriceString ?? "$3.99",
                yearlyPrice: premiumYearlyPkg?.localizedPriceString ?? "$29.99",
                yearlyMonthlyPrice: formattedMonthlyFromYearly(premiumYearlyPkg) ?? "$2.49",
                features: [
                    String(localized: "Unlimited loci"),
                    String(localized: "AI categorization"),
                    String(localized: "Cloud sync & backup"),
                    String(localized: "Home screen widget"),
                    String(localized: "Full-text search"),
                ],
                trialBadge: premiumMonthlyPkg?.storeProduct.introductoryDiscount != nil
                    || premiumYearlyPkg?.storeProduct.introductoryDiscount != nil,
                package: isYearly ? premiumYearlyPkg : premiumMonthlyPkg
            )

            // Family Card
            tierCard(
                title: String(localized: "Family"),
                icon: "person.3.fill",
                color: Theme.secondary,
                monthlyPrice: familyMonthlyPkg?.localizedPriceString ?? "$5.99",
                yearlyPrice: familyYearlyPkg?.localizedPriceString ?? "$44.99",
                yearlyMonthlyPrice: formattedMonthlyFromYearly(familyYearlyPkg) ?? "$3.74",
                features: [
                    String(localized: "Everything in Premium"),
                    String(localized: "Family sharing (up to 6)"),
                    String(localized: "Shared household loci"),
                    String(localized: "Family member management"),
                ],
                trialBadge: familyMonthlyPkg?.storeProduct.introductoryDiscount != nil
                    || familyYearlyPkg?.storeProduct.introductoryDiscount != nil,
                package: isYearly ? familyYearlyPkg : familyMonthlyPkg
            )
        }
    }

    private func tierCard(
        title: String,
        icon: String,
        color: Color,
        monthlyPrice: String,
        yearlyPrice: String,
        yearlyMonthlyPrice: String,
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
                    Text(trialBadgeText(for: package))
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
                    Text(yearlyMonthlyPrice)
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
                        Text(trialBadge
                             ? String(localized: "Start Free Trial")
                             : String(localized: "Subscribe"))
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
        let lifetimeIndividualPkg = packageForId(RevenueCatConfiguration.OfferingID.lifetimeIndividual)
        let lifetimeFamilyPkg = packageForId(RevenueCatConfiguration.OfferingID.lifetimeFamily)

        return VStack(spacing: Theme.Spacing.sm) {
            Text(String(localized: "Prefer a one-time purchase?"))
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: Theme.Spacing.md) {
                lifetimeButton(
                    title: String(localized: "Lifetime Individual"),
                    price: lifetimeIndividualPkg?.localizedPriceString ?? "$39.99",
                    package: lifetimeIndividualPkg
                )

                lifetimeButton(
                    title: String(localized: "Lifetime Family"),
                    price: lifetimeFamilyPkg?.localizedPriceString ?? "$59.99",
                    package: lifetimeFamilyPkg
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
        package: Package?
    ) -> some View {
        Button {
            Task { await purchasePackage(package) }
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.caption)
                    .fontWeight(.medium)

                Text(price)
                    .font(Theme.Typography.headline)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.primary)
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
                     destination: URL(string: "https://lociate.app/terms")!)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.textSecondary)

                Link(String(localized: "Privacy Policy"),
                     destination: URL(string: "https://lociate.app/privacy")!)
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

    private func packageForId(_ id: String) -> Package? {
        packages.first { $0.identifier == id }
    }

    /// Calculates monthly equivalent from a yearly package price, formatted in local currency.
    private func formattedMonthlyFromYearly(_ yearlyPackage: Package?) -> String? {
        guard let pkg = yearlyPackage else { return nil }
        let yearlyPrice = (pkg.storeProduct.price as NSDecimalNumber).doubleValue
        let monthlyEquivalent = yearlyPrice / 12.0

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = pkg.storeProduct.priceFormatter?.locale ?? .current
        return formatter.string(from: NSNumber(value: monthlyEquivalent))
    }

    /// Returns the trial badge text from RevenueCat introductory offer, or a default.
    private func trialBadgeText(for package: Package?) -> String {
        guard let intro = package?.storeProduct.introductoryDiscount else {
            return String(localized: "7-day free trial")
        }
        let days = intro.subscriptionPeriod.value
        let unit = intro.subscriptionPeriod.unit
        switch unit {
        case .day:
            return String(localized: "\(days)-day free trial")
        case .week:
            return String(localized: "\(days)-week free trial")
        case .month:
            return String(localized: "\(days)-month free trial")
        default:
            return String(localized: "Free trial")
        }
    }
}
