import CommonCrypto
import Foundation

enum PasswordKeyDerivation {
    static let currentVersion = 2
    static let iterations: UInt32 = 310_000
    static let keyByteCount = 32

    static func derive(password: String, salt: Data) throws -> Data {
        var derived = Data(repeating: 0, count: keyByteCount)
        let status = password.withCString { passwordBytes in
            salt.withUnsafeBytes { saltBytes in
                derived.withUnsafeMutableBytes { derivedBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes,
                        password.lengthOfBytes(using: .utf8),
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        iterations,
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        keyByteCount
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw PasswordDerivationError.failed(status) }
        return derived
    }
}

enum PasswordDerivationError: Error {
    case failed(Int32)
}
