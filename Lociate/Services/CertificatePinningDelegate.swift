import Foundation
import CommonCrypto
import os.log

// MARK: - Certificate Pinning Configuration

enum CertificatePinningConfig {
    /// SHA-256 hashes of the public keys for pinned certificates.
    /// Generated via BuildSecrets from environment variables.
    ///
    /// To obtain the pin hash for your server, run:
    /// ```
    /// openssl s_client -connect your-project.supabase.co:443 -servername your-project.supabase.co 2>/dev/null \
    ///   | openssl x509 -pubkey -noout \
    ///   | openssl pkey -pubin -outform der \
    ///   | openssl dgst -sha256 -binary \
    ///   | base64
    /// ```
    ///
    /// Include at least two pins: the current leaf certificate and a backup (e.g., intermediate CA).
    static let pinnedPublicKeyHashes: Set<String> = {
        var hashes: Set<String> = []
        let primary = BuildSecrets.certificatePinHash
        let backup = BuildSecrets.certificateBackupPinHash
        if !primary.isEmpty { hashes.insert(primary) }
        if !backup.isEmpty { hashes.insert(backup) }
        return hashes
    }()

    /// Domains that should have certificate pinning enforced.
    /// Pinning is skipped if no pin hashes are configured (e.g., local development).
    static let pinnedDomains: Set<String> = {
        guard !pinnedPublicKeyHashes.isEmpty else { return [] }
        var domains: Set<String> = []
        if let host = SupabaseConfig.url.host {
            domains.insert(host)
        }
        return domains
    }()
}

// MARK: - Certificate Pinning Delegate

final class CertificatePinningDelegate: NSObject, URLSessionDelegate {

    #if DEBUG
    private let logger = Logger(subsystem: "app.lociate.ios", category: "CertificatePinning")
    #endif

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let host = Optional(challenge.protectionSpace.host),
              CertificatePinningConfig.pinnedDomains.contains(host)
        else {
            // Not a server trust challenge or not a pinned domain — use default handling
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the server trust
        var error: CFError?
        let isValid = SecTrustEvaluateWithError(serverTrust, &error)

        guard isValid else {
            #if DEBUG
            logger.error("Server trust evaluation failed for \(host): \(error?.localizedDescription ?? "unknown")")
            #endif
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Check certificate chain for pinned public key hash
        let certificateCount = SecTrustGetCertificateCount(serverTrust)

        for index in 0..<certificateCount {
            guard let certificate = SecTrustCopyCertificateChain(serverTrust)?[index] as? SecCertificate else {
                continue
            }

            if let publicKeyHash = publicKeyHashForCertificate(certificate),
               CertificatePinningConfig.pinnedPublicKeyHashes.contains(publicKeyHash) {
                // Pin matched — allow connection
                let credential = URLCredential(trust: serverTrust)
                completionHandler(.useCredential, credential)
                return
            }
        }

        // No pin matched — reject connection
        #if DEBUG
        logger.error("Certificate pinning failed for \(host): no matching public key hash found in chain of \(certificateCount) certificates")
        logCertificateChain(serverTrust, host: host)
        #endif

        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - Private

    /// Extracts the SHA-256 hash of the public key from a certificate, base64-encoded.
    private func publicKeyHashForCertificate(_ certificate: SecCertificate) -> String? {
        guard let publicKey = SecCertificateCopyKey(certificate) else {
            return nil
        }

        var error: Unmanaged<CFError>?
        guard let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            return nil
        }

        // Create the ASN.1 header for RSA 2048-bit public keys (most common for TLS)
        // This produces the SPKI (Subject Public Key Info) hash that matches openssl output
        let spkiHeader: [UInt8] = [
            0x30, 0x82, 0x01, 0x22, 0x30, 0x0d, 0x06, 0x09,
            0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01,
            0x01, 0x05, 0x00, 0x03, 0x82, 0x01, 0x0f, 0x00,
        ]

        var spkiData = Data(spkiHeader)
        spkiData.append(publicKeyData)

        // SHA-256 hash
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        spkiData.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(spkiData.count), &hash)
        }

        return Data(hash).base64EncodedString()
    }

    #if DEBUG
    private func logCertificateChain(_ serverTrust: SecTrust, host: String) {
        guard let chain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate] else {
            return
        }

        for (index, certificate) in chain.enumerated() {
            let summary = SecCertificateCopySubjectSummary(certificate) as String? ?? "unknown"
            let hash = publicKeyHashForCertificate(certificate) ?? "unable to extract"
            logger.debug("  Certificate[\(index)] subject=\(summary) publicKeyHash=\(hash)")
        }
    }
    #endif
}
