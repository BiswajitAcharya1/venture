import XCTest
@testable import Venture

final class PasswordKeyDerivationTests: XCTestCase {
    func testDerivationIsDeterministicForSamePasswordAndSalt() throws {
        let salt = Data(repeating: 0x5A, count: 32)
        let first = try PasswordKeyDerivation.derive(password: "a-long-test-password", salt: salt)
        let second = try PasswordKeyDerivation.derive(password: "a-long-test-password", salt: salt)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, PasswordKeyDerivation.keyByteCount)
    }

    func testDifferentSaltChangesDerivedKey() throws {
        let first = try PasswordKeyDerivation.derive(password: "a-long-test-password", salt: Data(repeating: 0x01, count: 32))
        let second = try PasswordKeyDerivation.derive(password: "a-long-test-password", salt: Data(repeating: 0x02, count: 32))

        XCTAssertNotEqual(first, second)
    }
}
