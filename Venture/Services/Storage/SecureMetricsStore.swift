import Compression
import CryptoKit
import Foundation
import Security

actor SecureMetricsStore {
    private var fileURL: URL
    private let keyStore = EncryptionKeyStore()
    private var lastSavedDigest: SHA256.Digest?
    private var selectedAccount: String?

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "Venture", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? SensitiveFileProtection.apply(to: directory)
        fileURL = directory.appending(path: "metrics.v1.secure")
    }

    func selectAccount(_ userID: String) {
        let digest = SHA256.hash(data: Data(userID.utf8)).map { String(format: "%02x", $0) }.joined()
        fileURL = fileURL.deletingLastPathComponent().appending(path: "account-\(digest).secure")
        lastSavedDigest = nil
        selectedAccount = userID
    }

    func save(_ state: PersistedVentureState, expectedAccount: String?) {
        guard expectedAccount == selectedAccount else { return }
        save(state)
    }

    func load() -> PersistedVentureState? {
        guard
            let data = try? Data(contentsOf: fileURL, options: [.mappedIfSafe]),
            let key = try? keyStore.key(),
            let sealed = try? AES.GCM.SealedBox(combined: data),
            let clear = try? AES.GCM.open(sealed, using: key)
        else {
            return nil
        }
        let decoded = SecurePayloadCodec.unpack(clear)
        guard let state = try? JSONDecoder().decode(PersistedVentureState.self, from: decoded) else {
            return nil
        }
        lastSavedDigest = SHA256.hash(data: decoded)
        return state
    }

    func save(_ state: PersistedVentureState) {
        guard
            let encoded = try? JSONEncoder().encode(state),
            SHA256.hash(data: encoded) != lastSavedDigest,
            let key = try? keyStore.key(),
            let encrypted = try? AES.GCM.seal(SecurePayloadCodec.pack(encoded), using: key).combined
        else { return }
        do {
            try encrypted.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try SensitiveFileProtection.apply(to: fileURL)
            lastSavedDigest = SHA256.hash(data: encoded)
        } catch {
            return
        }
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        lastSavedDigest = nil
    }

    func destroy() {
        try? FileManager.default.removeItem(at: fileURL)
        keyStore.delete()
        lastSavedDigest = nil
    }
}

enum SecurePayloadCodec {
    private static let magic = Data([0x53, 0x4E, 0x44, 0x32]) // SND2
    private static let headerSize = 12
    private static let maximumDecodedBytes = 64 * 1_024 * 1_024

    static func pack(_ source: Data) -> Data {
        guard source.count >= 512,
              let compressed = compress(source),
              compressed.count + headerSize < source.count
        else { return source }

        var output = magic
        var originalSize = UInt64(source.count).littleEndian
        withUnsafeBytes(of: &originalSize) { output.append(contentsOf: $0) }
        output.append(compressed)
        return output
    }

    static func unpack(_ payload: Data) -> Data {
        guard payload.count > headerSize,
              payload.prefix(magic.count) == magic
        else { return payload }

        let lengthBytes = payload.dropFirst(magic.count).prefix(8)
        let expectedSize = lengthBytes.enumerated().reduce(UInt64(0)) { result, pair in
            result | (UInt64(pair.element) << UInt64(pair.offset * 8))
        }
        guard expectedSize > 0, expectedSize <= maximumDecodedBytes else { return payload }

        let compressed = payload.dropFirst(headerSize)
        var decoded = Data(count: Int(expectedSize))
        let written = decoded.withUnsafeMutableBytes { destination in
            compressed.withUnsafeBytes { source in
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    Int(expectedSize),
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    compressed.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard written == Int(expectedSize) else { return payload }
        return decoded
    }

    private static func compress(_ source: Data) -> Data? {
        let capacity = source.count + 64
        var destination = Data(count: capacity)
        let written = destination.withUnsafeMutableBytes { destinationBytes in
            source.withUnsafeBytes { sourceBytes in
                compression_encode_buffer(
                    destinationBytes.bindMemory(to: UInt8.self).baseAddress!,
                    capacity,
                    sourceBytes.bindMemory(to: UInt8.self).baseAddress!,
                    source.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
        }
        guard written > 0 else { return nil }
        destination.removeSubrange(written..<destination.count)
        return destination
    }
}

enum SensitiveFileProtection {
    static let protection: FileProtectionType = .complete

    static func apply(to url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: protection],
            ofItemAtPath: url.path
        )
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
    }
}

private struct EncryptionKeyStore: Sendable {
    private let service = "com.venture.metrics.encryption"
    private let account = "primary"

    func key() throws -> SymmetricKey {
        if let existing = read() {
            return SymmetricKey(data: existing)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try save(data)
        return key
    }

    private func read() -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func save(_ data: Data) throws {
        var query = baseQuery
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemDelete(baseQuery as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeyStoreError.unavailable }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private enum KeyStoreError: Error { case unavailable }
}
