import CryptoKit
import Foundation
import XCTest

@testable import Lociate

/// US-205: voice recordings are encrypted at rest with a key held in the Keychain.
/// A silent failure here means either unreadable recordings or plaintext audio on
/// disk, and neither was covered by a test.
final class AudioEncryptionServiceTests: XCTestCase {

    private var tempDirectory: URL!

    override func setUpWithError() throws {
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-encryption-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDirectory, FileManager.default.fileExists(atPath: tempDirectory.path) {
            try FileManager.default.removeItem(at: tempDirectory)
        }
    }

    private func writeFile(named name: String, contents: Data) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    /// Stands in for a recorded M4A: the leading bytes matter, because
    /// `isFileEncrypted` has to distinguish ciphertext from a real container.
    private var fakeM4A: Data {
        var data = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70])  // ....ftyp
        data.append(Data(repeating: 0xAB, count: 4096))
        return data
    }

    // MARK: - Round trip

    func testEncryptThenDecryptReturnsTheOriginalBytes() throws {
        let plaintext = fakeM4A

        let ciphertext = try AudioEncryptionService.encrypt(data: plaintext)
        let recovered = try AudioEncryptionService.decrypt(data: ciphertext)

        XCTAssertEqual(recovered, plaintext)
    }

    func testCiphertextDoesNotContainThePlaintext() throws {
        let plaintext = Data("spare key is under the third flowerpot".utf8)

        let ciphertext = try AudioEncryptionService.encrypt(data: plaintext)

        XCTAssertNotEqual(ciphertext, plaintext)
        XCTAssertFalse(
            ciphertext.range(of: plaintext) != nil,
            "plaintext must not survive verbatim in the ciphertext"
        )
    }

    func testEncryptingTwiceProducesDifferentCiphertext() throws {
        // AES-GCM uses a fresh nonce per seal; identical output would mean a reused
        // nonce, which breaks the cipher's guarantees.
        let plaintext = Data("same input".utf8)

        let first = try AudioEncryptionService.encrypt(data: plaintext)
        let second = try AudioEncryptionService.encrypt(data: plaintext)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try AudioEncryptionService.decrypt(data: first), plaintext)
        XCTAssertEqual(try AudioEncryptionService.decrypt(data: second), plaintext)
    }

    func testEmptyPayloadRoundTrips() throws {
        let ciphertext = try AudioEncryptionService.encrypt(data: Data())
        XCTAssertEqual(try AudioEncryptionService.decrypt(data: ciphertext), Data())
    }

    // MARK: - Tamper and wrong-key handling

    func testDecryptingTamperedCiphertextThrows() throws {
        var ciphertext = try AudioEncryptionService.encrypt(data: fakeM4A)
        // Flip a byte in the middle of the sealed box; GCM authentication must catch it.
        let index = ciphertext.index(ciphertext.startIndex, offsetBy: ciphertext.count / 2)
        ciphertext[index] ^= 0xFF

        XCTAssertThrowsError(try AudioEncryptionService.decrypt(data: ciphertext))
    }

    func testDecryptingTruncatedCiphertextThrows() throws {
        let ciphertext = try AudioEncryptionService.encrypt(data: fakeM4A)
        let truncated = ciphertext.prefix(ciphertext.count / 2)

        XCTAssertThrowsError(try AudioEncryptionService.decrypt(data: Data(truncated)))
    }

    func testDecryptingPlaintextThrowsRatherThanReturningGarbage() {
        // A file that was never encrypted must fail loudly, not silently produce
        // corrupt audio the player would choke on.
        XCTAssertThrowsError(try AudioEncryptionService.decrypt(data: fakeM4A))
    }

    // MARK: - File-level operations

    func testEncryptFileReplacesContentsInPlace() throws {
        let plaintext = fakeM4A
        let url = try writeFile(named: "note.m4a", contents: plaintext)

        try AudioEncryptionService.encryptFile(at: url)

        let onDisk = try Data(contentsOf: url)
        XCTAssertNotEqual(onDisk, plaintext, "the file must not still hold plaintext")
        XCTAssertEqual(try AudioEncryptionService.decrypt(data: onDisk), plaintext)
    }

    func testIsFileEncryptedDistinguishesCiphertextFromARealContainer() throws {
        let plaintextURL = try writeFile(named: "plain.m4a", contents: fakeM4A)
        XCTAssertFalse(AudioEncryptionService.isFileEncrypted(at: plaintextURL))

        try AudioEncryptionService.encryptFile(at: plaintextURL)
        XCTAssertTrue(AudioEncryptionService.isFileEncrypted(at: plaintextURL))
    }

    func testDecryptFileForPlaybackYieldsReadablePlaintext() throws {
        let plaintext = fakeM4A
        let url = try writeFile(named: "playme.m4a", contents: plaintext)
        try AudioEncryptionService.encryptFile(at: url)

        let temp = try AudioEncryptionService.decryptFileForPlayback(at: url)
        defer { AudioEncryptionService.cleanupTempFiles() }

        XCTAssertEqual(try Data(contentsOf: temp), plaintext)
        XCTAssertNotEqual(temp, url, "playback must not decrypt over the stored file")
    }

    func testReleaseTempFileDeletesThatFileImmediately() throws {
        let url = try writeFile(named: "release.m4a", contents: fakeM4A)
        try AudioEncryptionService.encryptFile(at: url)
        let temp = try AudioEncryptionService.decryptFileForPlayback(at: url)

        AudioEncryptionService.releaseTempFile(at: temp)

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: temp.path),
            "releasing a tracked temp file must delete it, not just untrack it"
        )
    }

    func testCleanupTempFilesRemovesDecryptedPlaintext() throws {
        // US-178/US-184: a decrypted copy left in /tmp defeats encryption at rest.
        let url = try writeFile(named: "cleanup.m4a", contents: fakeM4A)
        try AudioEncryptionService.encryptFile(at: url)
        let temp = try AudioEncryptionService.decryptFileForPlayback(at: url)

        XCTAssertTrue(FileManager.default.fileExists(atPath: temp.path))

        // Only cleanupTempFiles() here: releaseTempFile() deletes the file itself,
        // so calling it first would make this pass without exercising cleanup.
        AudioEncryptionService.cleanupTempFiles()

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: temp.path),
            "decrypted plaintext must not survive cleanup"
        )
    }
}
