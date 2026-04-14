import SwiftUI

// MARK: - Error Type

enum AppErrorType: Identifiable {
    case networkOffline
    case permissionLocation
    case permissionMicrophone
    case permissionNotifications
    case storageFull
    case syncFailure
    case recordingFailure

    var id: String {
        switch self {
        case .networkOffline: "networkOffline"
        case .permissionLocation: "permissionLocation"
        case .permissionMicrophone: "permissionMicrophone"
        case .permissionNotifications: "permissionNotifications"
        case .storageFull: "storageFull"
        case .syncFailure: "syncFailure"
        case .recordingFailure: "recordingFailure"
        }
    }

    var icon: String {
        switch self {
        case .networkOffline: "wifi.slash"
        case .permissionLocation: "location.slash"
        case .permissionMicrophone: "mic.slash"
        case .permissionNotifications: "bell.slash"
        case .storageFull: "externaldrive.badge.exclamationmark"
        case .syncFailure: "arrow.triangle.2.circlepath.circle"
        case .recordingFailure: "mic.slash"
        }
    }

    var message: String {
        switch self {
        case .networkOffline:
            String(localized: "No internet connection. Your loci are saved locally.")
        case .permissionLocation:
            String(localized: "Location access is required to pin voice notes. Enable it in Settings.")
        case .permissionMicrophone:
            String(localized: "Could not start recording. Check microphone access.")
        case .permissionNotifications:
            String(localized: "Enable notifications to get reminders when you're near your loci.")
        case .storageFull:
            String(localized: "Device storage full. Archive old loci to free space.")
        case .syncFailure:
            String(localized: "Sync failed. Will retry automatically.")
        case .recordingFailure:
            String(localized: "Could not start recording. Check microphone access.")
        }
    }

    var actionLabel: String {
        switch self {
        case .networkOffline, .syncFailure:
            String(localized: "Retry")
        case .permissionLocation, .permissionMicrophone, .permissionNotifications, .recordingFailure:
            String(localized: "Open Settings")
        case .storageFull:
            String(localized: "Manage Storage")
        }
    }

    var tintColor: Color {
        switch self {
        case .networkOffline, .syncFailure:
            Theme.warning
        case .permissionLocation, .permissionMicrophone, .permissionNotifications, .recordingFailure:
            Theme.error
        case .storageFull:
            Theme.warning
        }
    }
}

// MARK: - Error Banner View

struct ErrorBannerView: View {
    let error: AppErrorType
    let onAction: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: error.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(error.tintColor)

            Text(error.message)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button(error.actionLabel) {
                onAction()
            }
            .font(Theme.Typography.caption.bold())
            .foregroundStyle(error.tintColor)
            .accessibilityHint(actionHint)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .accessibilityLabel(String(localized: "Dismiss error"))
        }
        .padding(Theme.Spacing.md)
        .background(error.tintColor.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.CornerRadius.medium)
                .strokeBorder(error.tintColor.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal, Theme.Spacing.md)
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(error.message)
        .accessibilityAction(named: Text(error.actionLabel)) {
            onAction()
        }
    }

    private var actionHint: String {
        switch error {
        case .permissionLocation, .permissionMicrophone, .permissionNotifications, .recordingFailure:
            String(localized: "Opens the Settings app")
        case .networkOffline, .syncFailure:
            String(localized: "Retries the operation")
        case .storageFull:
            String(localized: "Opens storage management")
        }
    }
}

// MARK: - Error Banner Modifier

struct ErrorBannerModifier: ViewModifier {
    @Binding var error: AppErrorType?
    let onAction: (AppErrorType) -> Void

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let error {
                    ErrorBannerView(
                        error: error,
                        onAction: { onAction(error) },
                        onDismiss: {
                            withAnimation {
                                self.error = nil
                            }
                        }
                    )
                    .padding(.top, Theme.Spacing.sm)
                }
            }
    }
}

extension View {
    func errorBanner(_ error: Binding<AppErrorType?>, onAction: @escaping (AppErrorType) -> Void) -> some View {
        modifier(ErrorBannerModifier(error: error, onAction: onAction))
    }
}

// MARK: - Helpers

enum ErrorBannerActions {
    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Previews

#Preview("Network Offline") {
    VStack {
        ErrorBannerView(
            error: .networkOffline,
            onAction: {},
            onDismiss: {}
        )
        Spacer()
    }
    .padding(.top)
}

#Preview("Permission Denied") {
    VStack {
        ErrorBannerView(
            error: .permissionMicrophone,
            onAction: {},
            onDismiss: {}
        )
        Spacer()
    }
    .padding(.top)
}

#Preview("Storage Full") {
    VStack {
        ErrorBannerView(
            error: .storageFull,
            onAction: {},
            onDismiss: {}
        )
        Spacer()
    }
    .padding(.top)
}
