import Foundation
import os.log
import UIKit

// MARK: - Integrity Check Service (US-148)

/// Detects compromised runtime environments (jailbreak indicators, debugger attachment,
/// sandbox escape). Informational only — does not crash or block app per App Store guidelines.
@Observable
final class IntegrityCheckService {
    static let shared = IntegrityCheckService()

    private(set) var isCompromised = false
    private(set) var detectedIssues: [IntegrityIssue] = []

    /// US-184: Gate for sensitive operations — household management,
    /// biometric enrolment, account deletion, and data export refuse to
    /// proceed when this returns true. Surfaces a user-facing banner
    /// explaining why.
    var shouldBlockSensitiveOperations: Bool { isCompromised }

    private let logger = Logger(subsystem: "app.lociate.ios", category: "IntegrityCheck")

    enum IntegrityIssue: String, CaseIterable {
        case jailbreakPaths = "Suspicious file paths detected"
        case cydiaInstalled = "Cydia or alternative app stores detected"
        case writableSystemDirs = "System directories are writable"
        case sandboxEscape = "Sandbox boundary violation"
        case debuggerAttached = "Debugger attachment detected"
        case dynamicLibraries = "Suspicious dynamic libraries loaded"
    }

    // MARK: - Public API

    /// Run all integrity checks. Call on app launch and periodically.
    func performChecks() {
        var issues: [IntegrityIssue] = []

        if checkJailbreakPaths() { issues.append(.jailbreakPaths) }
        if checkCydiaInstalled() { issues.append(.cydiaInstalled) }
        if checkWritableSystemDirs() { issues.append(.writableSystemDirs) }
        if checkSandboxEscape() { issues.append(.sandboxEscape) }
        if checkDebuggerAttached() { issues.append(.debuggerAttached) }
        if checkSuspiciousDylibs() { issues.append(.dynamicLibraries) }

        detectedIssues = issues
        isCompromised = !issues.isEmpty

        if isCompromised {
            logger.warning("Integrity check failed: \(issues.map(\.rawValue).joined(separator: ", "))")
            // Log to analytics (non-blocking)
            AnalyticsService.shared.track(
                .appLaunch,
                properties: [
                    "integrity_compromised": "true",
                    "issues": issues.map(\.rawValue).joined(separator: "|"),
                ]
            )
        } else {
            logger.info("Integrity check passed")
        }
    }

    // MARK: - Jailbreak Indicators

    /// Check for common jailbreak file paths
    private func checkJailbreakPaths() -> Bool {
        let suspiciousPaths = [
            "/Applications/Cydia.app",
            "/Applications/Sileo.app",
            "/Applications/Zebra.app",
            "/usr/sbin/sshd",
            "/usr/bin/ssh",
            "/usr/libexec/sftp-server",
            "/etc/apt",
            "/private/var/lib/apt",
            "/private/var/lib/cydia",
            "/private/var/stash",
            "/private/var/mobile/Library/SBSettings/Themes",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/Library/MobileSubstrate/DynamicLibraries",
            "/var/cache/apt",
            "/var/lib/cydia",
            "/bin/bash",
            "/bin/sh",
        ]

        return suspiciousPaths.contains { FileManager.default.fileExists(atPath: $0) }
    }

    /// Check if Cydia or alternative stores can be opened via URL scheme
    private func checkCydiaInstalled() -> Bool {
        let suspiciousSchemes = [
            "cydia://",
            "sileo://",
            "zbra://",
            "undecimus://",
        ]

        return suspiciousSchemes.contains { scheme in
            guard let url = URL(string: scheme) else { return false }
            return UIApplication.shared.canOpenURL(url)
        }
    }

    /// Check if system directories are writable (they shouldn't be on non-jailbroken devices)
    private func checkWritableSystemDirs() -> Bool {
        let testPath = "/private/jailbreak_test_\(UUID().uuidString)"
        do {
            try "test".write(toFile: testPath, atomically: true, encoding: .utf8)
            // If write succeeded, device is compromised — clean up
            try? FileManager.default.removeItem(atPath: testPath)
            return true
        } catch {
            return false
        }
    }

    /// Check for sandbox escape (ability to write outside app sandbox)
    private func checkSandboxEscape() -> Bool {
        let outsidePath = "/tmp/lociate_sandbox_test_\(UUID().uuidString)"
        do {
            try "test".write(toFile: outsidePath, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(atPath: outsidePath)
            return true
        } catch {
            return false
        }
    }

    /// Check for debugger attachment via sysctl
    private func checkDebuggerAttached() -> Bool {
        #if DEBUG
        // Don't flag debugger in debug builds — it's expected during development
        return false
        #else
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0 else { return false }

        return (info.kp_proc.p_flag & P_TRACED) != 0
        #endif
    }

    /// Check for suspicious dynamic libraries (common in jailbreak tweaks)
    private func checkSuspiciousDylibs() -> Bool {
        let suspiciousLibs = [
            "SubstrateLoader",
            "MobileSubstrate",
            "TweakInject",
            "libhooker",
            "substitute",
            "Cephei",
        ]

        let imageCount = _dyld_image_count()
        for i in 0..<imageCount {
            if let imageName = _dyld_get_image_name(i) {
                let name = String(cString: imageName)
                if suspiciousLibs.contains(where: { name.contains($0) }) {
                    return true
                }
            }
        }
        return false
    }
}
