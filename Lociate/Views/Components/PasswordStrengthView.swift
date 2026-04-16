import SwiftUI

/// Displays password strength indicator with colored bar and requirement checklist. (US-144)
struct PasswordStrengthView: View {
    let password: String

    private var validation: (strength: PasswordValidator.Strength, requirements: PasswordValidator.Requirements) {
        PasswordValidator.validate(password)
    }

    var body: some View {
        let (strength, requirements) = validation

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Strength bar
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index <= strength.rawValue ? strengthColor(strength) : Theme.textSecondary.opacity(0.2))
                        .frame(height: 4)
                }
                Text(strength.label)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(strengthColor(strength))
                    .frame(width: 50, alignment: .trailing)
            }

            // Requirement checklist
            VStack(alignment: .leading, spacing: 4) {
                requirementRow("8+ characters", met: requirements.hasMinLength)
                requirementRow("Uppercase letter", met: requirements.hasUppercase)
                requirementRow("Lowercase letter", met: requirements.hasLowercase)
                requirementRow("Number", met: requirements.hasDigit)
                requirementRow("Special character", met: requirements.hasSpecialChar)
                if !requirements.isNotCommon && password.count >= 4 {
                    requirementRow("Not a common password", met: false)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: password)
    }

    private func requirementRow(_ text: String, met: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundStyle(met ? Theme.success : Theme.textSecondary.opacity(0.5))
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(met ? Theme.textPrimary : Theme.textSecondary)
        }
    }

    private func strengthColor(_ strength: PasswordValidator.Strength) -> Color {
        switch strength {
        case .weak: Theme.error
        case .fair: Color.orange
        case .good: Theme.warning
        case .strong: Theme.success
        }
    }
}
