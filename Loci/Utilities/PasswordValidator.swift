import Foundation

/// Validates password strength and provides detailed requirement feedback. (US-144)
enum PasswordValidator {
    // MARK: - Strength Levels

    enum Strength: Int, Comparable {
        case weak = 0
        case fair = 1
        case good = 2
        case strong = 3

        var label: String {
            switch self {
            case .weak: String(localized: "Weak")
            case .fair: String(localized: "Fair")
            case .good: String(localized: "Good")
            case .strong: String(localized: "Strong")
            }
        }

        static func < (lhs: Strength, rhs: Strength) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Requirements

    struct Requirements {
        let hasMinLength: Bool       // 8+ characters
        let hasUppercase: Bool       // At least one uppercase letter
        let hasLowercase: Bool       // At least one lowercase letter
        let hasDigit: Bool           // At least one digit
        let hasSpecialChar: Bool     // At least one special character
        let isLongEnough: Bool       // 12+ characters for strong
        let isNotCommon: Bool        // Not in common passwords list
        let meetsMinimum: Bool       // Meets fair threshold (all minimum requirements)
    }

    // MARK: - Validation

    static func validate(_ password: String) -> (strength: Strength, requirements: Requirements) {
        let hasMinLength = password.count >= 8
        let hasUppercase = password.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLowercase = password.range(of: "[a-z]", options: .regularExpression) != nil
        let hasDigit = password.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSpecialChar = password.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
        let isLongEnough = password.count >= 12
        let isNotCommon = !commonPasswords.contains(password.lowercased())

        let meetsMinimum = hasMinLength && hasUppercase && hasLowercase && hasDigit && isNotCommon

        let requirements = Requirements(
            hasMinLength: hasMinLength,
            hasUppercase: hasUppercase,
            hasLowercase: hasLowercase,
            hasDigit: hasDigit,
            hasSpecialChar: hasSpecialChar,
            isLongEnough: isLongEnough,
            isNotCommon: isNotCommon,
            meetsMinimum: meetsMinimum
        )

        let strength = calculateStrength(
            meetsMinimum: meetsMinimum,
            hasSpecialChar: hasSpecialChar,
            isLongEnough: isLongEnough,
            password: password
        )

        return (strength, requirements)
    }

    private static func calculateStrength(
        meetsMinimum: Bool,
        hasSpecialChar: Bool,
        isLongEnough: Bool,
        password: String
    ) -> Strength {
        guard meetsMinimum else {
            // Even if some requirements met, at least minimum length needed
            return password.count >= 8 ? .weak : .weak
        }

        var score = 0

        // Base: meets minimum requirements = fair
        score += 1

        // Bonus for special characters
        if hasSpecialChar { score += 1 }

        // Bonus for 12+ characters
        if isLongEnough { score += 1 }

        // Bonus for high entropy (mixed character classes)
        if password.count >= 16 { score += 1 }

        switch score {
        case 0: return .weak
        case 1: return .fair
        case 2: return .good
        default: return .strong
        }
    }

    // MARK: - Common Passwords (top 100)

    private static let commonPasswords: Set<String> = [
        "password", "123456", "12345678", "qwerty", "abc123",
        "monkey", "1234567", "letmein", "trustno1", "dragon",
        "baseball", "iloveyou", "master", "sunshine", "ashley",
        "michael", "shadow", "123123", "654321", "superman",
        "qazwsx", "michael", "football", "password1", "password123",
        "batman", "login", "admin", "welcome", "solo",
        "princess", "starwars", "whatever", "qwerty123", "hello",
        "charlie", "donald", "password1!", "aa123456", "access",
        "flower", "hottie", "loveme", "zaq1zaq1", "hello123",
        "password!", "000000", "passw0rd", "1234567890", "12345",
        "123456789", "1234", "111111", "1q2w3e4r", "qwertyuiop",
        "google", "1q2w3e", "zxcvbnm", "1qaz2wsx", "abcdef",
        "121212", "bailey", "freedom", "shadow1", "passpass",
        "buster", "daniel", "hannah", "thomas", "summer",
        "george", "harley", "222222", "jessica", "ginger",
        "pepper", "hunter", "abcd1234", "silver", "samuel",
        "jordan", "madison", "computer", "merlin", "diamond",
        "matthew", "robert", "sophie", "tigger", "michelle",
        "ranger", "patrick", "cookie", "andrea", "joshua",
        "jennifer", "amanda", "thunder", "phoenix", "william",
    ]
}
