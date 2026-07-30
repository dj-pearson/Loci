import Foundation

extension String {
    /// Resolves a pluralized entry from the string catalog (US-211).
    ///
    /// Foundation's `String(localized:)` takes a `LocalizationValue`, and building
    /// one with an interpolated count is what selects the plural variation. A
    /// hand-written `"attempt(s)"` cannot be localized at all: Polish and Arabic
    /// have more plural categories than English's two, so the suffix trick produces
    /// wrong grammar in every such language.
    ///
    /// The catalog entry keyed by `key` must declare `variations.plural` — see
    /// `scripts/generate-string-catalog.py`.
    init(localized key: StaticString, count: Int) {
        // The `%lld` in the catalog's plural variations binds to this argument.
        self.init(
            format: String(
                localized: String.LocalizationValue(stringLiteral: "\(key)")
            ),
            locale: .current,
            count
        )
    }
}
