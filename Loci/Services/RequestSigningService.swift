import Foundation
import CommonCrypto

/// Provides HMAC-SHA256 request signing for sensitive API mutations.
enum RequestSigningService {
    /// Signs a request by adding HMAC-SHA256 signature headers.
    ///
    /// Headers added:
    /// - `X-Client-Version`: App version and build number
    /// - `X-Request-Timestamp`: ISO 8601 timestamp
    /// - `X-Request-Signature`: HMAC-SHA256(method + path + timestamp + bodyHash)
    static func sign(_ request: inout URLRequest, body: Data? = nil) {
        let signingKey = BuildSecrets.requestSigningKey
        guard !signingKey.isEmpty else { return }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        request.setValue("\(version)(\(build))", forHTTPHeaderField: "X-Client-Version")

        let timestamp = ISO8601DateFormatter().string(from: Date())
        request.setValue(timestamp, forHTTPHeaderField: "X-Request-Timestamp")

        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "/"
        let bodyHash = sha256Hex(body ?? Data())
        let payload = "\(method)\n\(path)\n\(timestamp)\n\(bodyHash)"

        if let signature = hmacSHA256(payload, key: signingKey) {
            request.setValue(signature, forHTTPHeaderField: "X-Request-Signature")
        }
    }

    // MARK: - Private

    private static func hmacSHA256(_ message: String, key: String) -> String? {
        guard let keyData = key.data(using: .utf8),
              let messageData = message.data(using: .utf8) else { return nil }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))

        keyData.withUnsafeBytes { keyBuffer in
            messageData.withUnsafeBytes { messageBuffer in
                CCHmac(
                    CCHmacAlgorithm(kCCHmacAlgSHA256),
                    keyBuffer.baseAddress, keyData.count,
                    messageBuffer.baseAddress, messageData.count,
                    &digest
                )
            }
        }

        return Data(digest).map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash).map { String(format: "%02x", $0) }.joined()
    }
}
