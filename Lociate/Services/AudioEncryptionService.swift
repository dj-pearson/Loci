import CryptoKit
import Foundation
import os.log

enum AudioEncryptionService {
    // MARK: - Errors

    enum EncryptionError: Error, LocalizedError {
        case keyGenerationFailed
        case encryptionFailed(String)
        case decryptionFailed(String)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed:
                "Failed to generate or retrieve encryption key"
            case .encryptionFailed(let reason):
                "Encryption failed: \(reason)"
            case .decryptionFailed(let reason):
                "Decryption failed: \(reason)"
            case .invalidData:
                "Invalid encrypted data format"
            }
        }
    }

    // MARK: - Key Management

    private static let keychainKey = "com.pearsonmedia.loci.audioEncryptionKey"

    /// Retrieves or generates the AES-256 encryption key stored in Keychain.
    private static func getOrCreateKey() throws -> SymmetricKey {
        // Try to load existing key from Keychain
        if let existingKeyData = try KeychainService.load(key: keychainKey) {
            return SymmetricKey(data: existingKeyData)
        }

        // Generate a new 256-bit key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }

        try KeychainService.save(key: keychainKey, data: keyData)

        return newKey
    }

    // MARK: - Encrypt / Decrypt

    /// Encrypts data using AES-GCM. Returns the combined nonce + ciphertext + tag.
    static func encrypt(data: Data) throws -> Data {
        let key: SymmetricKey
        do {
            key = try getOrCreateKey()
        } catch {
            throw EncryptionError.keyGenerationFailed
        }

        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw EncryptionError.encryptionFailed("Failed to produce combined sealed box")
            }
            return combined
        } catch let error as EncryptionError {
            throw error
        } catch {
            throw EncryptionError.encryptionFailed(error.localizedDescription)
        }
    }

    /// Decrypts AES-GCM data (nonce + ciphertext + tag).
    static func decrypt(data: Data) throws -> Data {
        let key: SymmetricKey
        do {
            key = try getOrCreateKey()
        } catch {
            throw EncryptionError.keyGenerationFailed
        }

        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw EncryptionError.decryptionFailed(error.localizedDescription)
        }
    }

    // MARK: - File Operations

    /// Encrypts an audio file in place. The original file is replaced with the encrypted version.
    static func encryptFile(at url: URL) throws {
        let plainData = try Data(contentsOf: url)
        let encryptedData = try encrypt(data: plainData)
        try encryptedData.write(to: url)
    }

    /// Decrypts an encrypted audio file and returns a temporary URL for playback.
    /// The caller is responsible for cleaning up the temporary file.
    static func decryptFileForPlayback(at url: URL) throws -> URL {
        let encryptedData = try Data(contentsOf: url)
        let plainData = try decrypt(data: encryptedData)

        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(UUID().uuidString + ".\(AppConstants.Audio.fileExtension)")
        try plainData.write(to: tempURL)

        return tempURL
    }

    /// Checks whether a file appears to be encrypted (not a valid M4A header).
    /// M4A files start with "ftyp" at byte offset 4.
    static func isFileEncrypted(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        guard let header = try? handle.read(upToCount: 8), header.count >= 8 else {
            return false
        }

        // M4A/MP4 files have "ftyp" at bytes 4-7
        let ftypSignature = Data([0x66, 0x74, 0x79, 0x70]) // "ftyp"
        let headerSlice = header[4..<8]
        return headerSlice != ftypSignature
    }

    // MARK: - Migration

    /// Encrypts all existing unencrypted audio files in the documents/audio directories.
    static func migrateUnencryptedFiles() {
        let fileManager = FileManager.default
        let documentsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!

        let enumerator = fileManager.enumerator(
            at: documentsDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )

        while let fileURL = enumerator?.nextObject() as? URL {
            guard fileURL.pathExtension == AppConstants.Audio.fileExtension else { continue }
            guard !isFileEncrypted(at: fileURL) else { continue }

            do {
                try encryptFile(at: fileURL)
            } catch {
                #if DEBUG
                Logger(subsystem: "com.pearsonmedia.loci", category: "AudioEncryption")
                    .error("Failed to migrate \(fileURL.lastPathComponent): \(error.localizedDescription)")
                #endif
            }
        }
    }
}
