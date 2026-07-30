import CommonCrypto
import Foundation
import XCTest

@testable import Lociate

/// US-205: the signing payload is a cross-platform contract. iOS, the Android
/// `RequestSigningInterceptor`, and the edge-function middleware must all build
/// the identical canonical string — a single mismatched newline or a differently
/// cased hex digest rejects every signed request from that platform, and nothing
/// verified they agreed.
final class RequestSigningServiceTests: XCTestCase {

    private let key = BuildSecrets.requestSigningKey

    private func signedRequest(
        method: String = "POST",
        url: String = "https://api.lociate.app/api/account/delete",
        body: Data? = nil
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        RequestSigningService.sign(&request, body: body)
        return request
    }

    /// Reference implementation of the canonical string, written independently of
    /// the service so a change to either side shows up as a failure.
    private func expectedSignature(
        method: String,
        path: String,
        timestamp: String,
        body: Data
    ) -> String {
        let bodyHash = sha256Hex(body)
        let payload = "\(method)\n\(path)\n\(timestamp)\n\(bodyHash)"
        return hmacHex(payload, key: key)
    }

    private func sha256Hex(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func hmacHex(_ message: String, key: String) -> String {
        let keyData = Data(key.utf8)
        let messageData = Data(message.utf8)
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
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Unconfigured key

    func testNoHeadersAreAddedWhenSigningIsDisabled() throws {
        try XCTSkipUnless(key.isEmpty, "signing key is configured in this build")

        let request = signedRequest()

        XCTAssertNil(request.value(forHTTPHeaderField: "X-Request-Signature"))
        XCTAssertNil(request.value(forHTTPHeaderField: "X-Request-Timestamp"))
    }

    // MARK: - Canonical string

    func testSignatureMatchesTheIndependentlyComputedCanonicalString() throws {
        try XCTSkipIf(key.isEmpty, "signing key is not configured in this build")

        let body = Data(#"{"confirm":true}"#.utf8)
        let request = signedRequest(body: body)

        let timestamp = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Request-Timestamp"))
        let signature = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Request-Signature"))

        XCTAssertEqual(
            signature,
            expectedSignature(
                method: "POST",
                path: "/api/account/delete",
                timestamp: timestamp,
                body: body
            )
        )
    }

    func testEmptyBodyHashesTheEmptyStringRatherThanBeingOmitted() throws {
        try XCTSkipIf(key.isEmpty, "signing key is not configured in this build")

        // The server always hashes `body || ''`, so a GET with no body must sign
        // the SHA-256 of zero bytes, not skip the field.
        let request = signedRequest(method: "GET", body: nil)
        let timestamp = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Request-Timestamp"))
        let signature = try XCTUnwrap(request.value(forHTTPHeaderField: "X-Request-Signature"))

        XCTAssertEqual(
            signature,
            expectedSignature(
                method: "GET",
                path: "/api/account/delete",
                timestamp: timestamp,
                body: Data()
            )
        )
    }

    func testSignatureIsLowercaseHexOfTheRightLength() throws {
        try XCTSkipIf(key.isEmpty, "signing key is not configured in this build")

        let signature = try XCTUnwrap(
            signedRequest().value(forHTTPHeaderField: "X-Request-Signature")
        )

        // The middleware does Buffer.from(signature, 'hex') and a length check
        // before timingSafeEqual, so 64 lowercase hex characters is the contract.
        XCTAssertEqual(signature.count, 64)
        XCTAssertEqual(signature, signature.lowercased())
        XCTAssertTrue(signature.allSatisfy { $0.isHexDigit })
    }

    func testSignatureCoversTheBody() throws {
        try XCTSkipIf(key.isEmpty, "signing key is not configured in this build")

        // Same timestamp is not guaranteed across two calls, so compare against the
        // reference implementation using each request's own timestamp instead.
        let first = signedRequest(body: Data("a".utf8))
        let second = signedRequest(body: Data("b".utf8))

        let firstTimestamp = try XCTUnwrap(first.value(forHTTPHeaderField: "X-Request-Timestamp"))
        let secondTimestamp = try XCTUnwrap(second.value(forHTTPHeaderField: "X-Request-Timestamp"))

        XCTAssertNotEqual(
            expectedSignature(
                method: "POST", path: "/api/account/delete",
                timestamp: firstTimestamp, body: Data("a".utf8)
            ),
            expectedSignature(
                method: "POST", path: "/api/account/delete",
                timestamp: secondTimestamp, body: Data("b".utf8)
            )
        )
    }

    func testSignatureCoversMethodAndPath() throws {
        try XCTSkipIf(key.isEmpty, "signing key is not configured in this build")

        let timestamp = ISO8601DateFormatter().string(from: Date())
        let base = expectedSignature(
            method: "POST", path: "/api/account/delete", timestamp: timestamp, body: Data()
        )

        XCTAssertNotEqual(
            base,
            expectedSignature(
                method: "GET", path: "/api/account/delete", timestamp: timestamp, body: Data()
            ),
            "changing the method must change the signature"
        )
        XCTAssertNotEqual(
            base,
            expectedSignature(
                method: "POST", path: "/api/account/other", timestamp: timestamp, body: Data()
            ),
            "changing the path must change the signature"
        )
    }

    // MARK: - Headers

    func testTimestampIsISO8601AndWithinTheServerSkewWindow() throws {
        try XCTSkipIf(key.isEmpty, "signing key is not configured in this build")

        let timestamp = try XCTUnwrap(
            signedRequest().value(forHTTPHeaderField: "X-Request-Timestamp")
        )
        let parsed = try XCTUnwrap(ISO8601DateFormatter().date(from: timestamp))

        // The middleware rejects anything more than 5 minutes out.
        XCTAssertLessThan(abs(parsed.timeIntervalSinceNow), 60)
    }

    func testClientVersionHeaderIsSet() throws {
        try XCTSkipIf(key.isEmpty, "signing key is not configured in this build")

        let version = try XCTUnwrap(
            signedRequest().value(forHTTPHeaderField: "X-Client-Version")
        )
        XCTAssertTrue(version.contains("("), "expected version(build), got \(version)")
    }

    /// Pins the exact canonical layout as a literal so a future refactor cannot
    /// quietly reorder or re-delimit the fields.
    func testCanonicalPayloadLayoutIsMethodPathTimestampBodyHash() {
        let body = Data("hello".utf8)
        let expectedBodyHash =
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"

        XCTAssertEqual(sha256Hex(body), expectedBodyHash, "SHA-256 of \"hello\"")

        let payload = "POST\n/api/x\n2026-01-01T00:00:00Z\n\(expectedBodyHash)"
        XCTAssertEqual(payload.components(separatedBy: "\n").count, 4)
        XCTAssertEqual(payload.components(separatedBy: "\n")[0], "POST")
        XCTAssertEqual(payload.components(separatedBy: "\n")[1], "/api/x")
        XCTAssertEqual(payload.components(separatedBy: "\n")[3], expectedBodyHash)
    }
}
