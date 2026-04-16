import SwiftUI

/// US-148: Warning banner shown when device integrity checks fail.
/// Informational only — does not block app usage per App Store guidelines.
struct IntegrityWarningBanner: View {
    let issues: [IntegrityCheckService.IntegrityIssue]
    @State private var isDismissed = false

    var body: some View {
        if !isDismissed && !issues.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(.white)
                    Text("Device Security Warning")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        withAnimation { isDismissed = true }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }

                Text("This device may have been modified. Some security features may be reduced.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(Theme.Spacing.md)
            .background(Theme.warning)
            .cornerRadius(Theme.CornerRadius.medium)
            .padding(.horizontal, Theme.Spacing.md)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
