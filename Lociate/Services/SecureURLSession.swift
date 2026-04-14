import Foundation

/// Provides a pre-configured URLSession with security hardening:
/// - Certificate pinning via CertificatePinningDelegate
/// - Connection timeout: 30s, resource timeout: 60s
/// - Default X-Client-Version header on all requests
enum SecureURLSession {
    /// Shared session with certificate pinning and timeouts.
    static let shared: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        configuration.httpAdditionalHeaders = [
            "X-Client-Version": "\(version)(\(build))"
        ]

        return URLSession(
            configuration: configuration,
            delegate: SupabaseClientProvider.certificatePinningDelegate,
            delegateQueue: nil
        )
    }()

    /// Creates a signed URLRequest for sensitive mutations.
    static func signedRequest(url: URL, method: String = "POST", body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        RequestSigningService.sign(&request, body: body)
        return request
    }
}
