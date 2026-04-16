import Foundation

enum InputSanitizer {
    // MARK: - Length Limits

    enum LengthLimit {
        static let transcription = 5000
        static let displayName = 50
        static let householdName = 50
        static let searchQuery = 200
    }

    // MARK: - Sanitize

    /// General-purpose sanitizer: strips HTML/script tags, trims whitespace, enforces max length.
    static func sanitize(_ text: String, maxLength: Int = LengthLimit.transcription) -> String {
        var result = text

        // Strip HTML tags (preserves Unicode content between tags)
        result = stripHTMLTags(result)

        // Remove null bytes and control characters (except newline/tab for transcriptions)
        result = result.replacingOccurrences(of: "\0", with: "")
        result = stripControlCharacters(result)
        result = stripZeroWidthCharacters(result)

        // Trim leading/trailing whitespace and newlines
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)

        // Collapse multiple whitespace runs into single spaces (preserve newlines for transcriptions)
        result = collapseWhitespace(result)

        // Truncate to max length (character-safe, respects grapheme clusters)
        if result.count > maxLength {
            result = String(result.prefix(maxLength))
        }

        return result
    }

    /// Sanitizes a transcription text.
    static func sanitizeTranscription(_ text: String) -> String {
        sanitize(text, maxLength: LengthLimit.transcription)
    }

    /// Sanitizes a display name.
    static func sanitizeDisplayName(_ text: String) -> String {
        // Display names should be single-line
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return sanitize(singleLine, maxLength: LengthLimit.displayName)
    }

    /// Sanitizes a household name.
    static func sanitizeHouseholdName(_ text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return sanitize(singleLine, maxLength: LengthLimit.householdName)
    }

    /// Sanitizes a search query.
    static func sanitizeSearchQuery(_ text: String) -> String {
        let singleLine = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        return sanitize(singleLine, maxLength: LengthLimit.searchQuery)
    }

    // MARK: - Private Helpers

    /// Strips HTML tags including script/style blocks and their content.
    private static func stripHTMLTags(_ text: String) -> String {
        var result = text

        // Remove <script>...</script> and <style>...</style> blocks entirely (case-insensitive)
        let blockPatterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
        ]

        for pattern in blockPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }

        // Remove remaining HTML tags
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            result = tagRegex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: ""
            )
        }

        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        return result
    }

    /// Strips control characters except newline (\n) and tab (\t).
    private static func stripControlCharacters(_ text: String) -> String {
        text.unicodeScalars.filter { scalar in
            !scalar.properties.isDefaultIgnorableCodePoint
                && (scalar.value >= 0x20 || scalar == "\n" || scalar == "\t")
        }.map { String($0) }.joined()
    }

    /// Strips zero-width characters (ZWJ, ZWSP, ZWNJ, soft hyphen, BOM, etc.).
    private static func stripZeroWidthCharacters(_ text: String) -> String {
        let zeroWidthScalars: Set<Unicode.Scalar> = [
            "\u{200B}", // Zero Width Space
            "\u{200C}", // Zero Width Non-Joiner
            "\u{200D}", // Zero Width Joiner
            "\u{FEFF}", // BOM / Zero Width No-Break Space
            "\u{00AD}", // Soft Hyphen
            "\u{2060}", // Word Joiner
            "\u{180E}", // Mongolian Vowel Separator
        ]
        return text.unicodeScalars.filter { !zeroWidthScalars.contains($0) }
            .map { String($0) }.joined()
    }

    /// Collapses runs of spaces/tabs into a single space, preserving single newlines.
    private static func collapseWhitespace(_ text: String) -> String {
        if let regex = try? NSRegularExpression(pattern: "[^\\S\\n]+", options: []) {
            return regex.stringByReplacingMatches(
                in: text,
                range: NSRange(text.startIndex..., in: text),
                withTemplate: " "
            )
        }
        return text
    }
}
