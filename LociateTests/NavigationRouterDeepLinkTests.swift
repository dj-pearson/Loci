import XCTest

@testable import Lociate

/// US-203: the widget emitted `loci://detail/...` URLs and NavigationRouter parsed
/// them, but no URL scheme was registered in Info.plist — so every widget tap and
/// paywall link was a silent no-op. These pin the scheme, host, and path contract
/// that Info.plist, the widget, the AASA file, and the Android validator all share.
final class NavigationRouterDeepLinkTests: XCTestCase {

    private let locusId = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    private func route(_ string: String) -> NavigationRouter {
        let router = NavigationRouter()
        router.handleURL(URL(string: string)!)
        return router
    }

    // MARK: - Custom scheme

    func testCanonicalSchemeOpensLocus() {
        XCTAssertEqual(route("lociate://locus/\(locusId.uuidString)").selectedLocusId, locusId)
    }

    func testLegacySchemeAndHostStillResolve() {
        // URLs are already baked into installed widgets and delivered notification
        // payloads, so dropping these would break links in the field.
        XCTAssertEqual(route("loci://detail/\(locusId.uuidString)").selectedLocusId, locusId)
        XCTAssertEqual(route("loci://locus/\(locusId.uuidString)").selectedLocusId, locusId)
    }

    func testPaywallHostSetsTheFlag() {
        XCTAssertTrue(route("lociate://paywall").showPaywall)
        XCTAssertTrue(route("loci://paywall").showPaywall)
    }

    // MARK: - Universal links

    func testUniversalLinkPathsMatchTheAssociationFile() {
        // These two prefixes are exactly what the AASA file declares. A path
        // accepted here but absent there would never reach the app.
        for path in ["locus", "open"] {
            XCTAssertEqual(
                route("https://lociate.app/\(path)/\(locusId.uuidString)").selectedLocusId,
                locusId,
                "https /\(path)/ should resolve"
            )
        }
    }

    // MARK: - Rejections

    func testUnknownSchemeIsIgnored() {
        let router = route("evil://locus/\(locusId.uuidString)")
        XCTAssertNil(router.selectedLocusId)
        XCTAssertFalse(router.showPaywall)
    }

    func testUnknownHostIsIgnored() {
        XCTAssertNil(route("lociate://admin/\(locusId.uuidString)").selectedLocusId)
    }

    func testUndeclaredUniversalLinkPathIsIgnored() {
        XCTAssertNil(route("https://lociate.app/admin/\(locusId.uuidString)").selectedLocusId)
    }

    func testMalformedIdentifierIsIgnored() {
        for url in [
            "lociate://locus/not-a-uuid",
            "lociate://locus/../../etc/passwd",
            "https://lociate.app/locus/not-a-uuid",
        ] {
            XCTAssertNil(route(url).selectedLocusId, "\(url) should not resolve")
        }
    }

    func testUniversalLinkWithNoIdentifierIsIgnored() {
        XCTAssertNil(route("https://lociate.app/locus").selectedLocusId)
    }

    // MARK: - Info.plist contract

    func testRegisteredURLSchemesCoverEveryEmittedScheme() {
        // The registration is what was missing entirely; without it the parsing
        // above is unreachable at runtime.
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]]
        let schemes = Set(
            (types ?? []).flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        )
        XCTAssertTrue(schemes.contains("lociate"), "canonical scheme must be registered")
        XCTAssertTrue(schemes.contains("loci"), "legacy scheme must stay registered")
    }
}
