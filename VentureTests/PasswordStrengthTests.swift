import XCTest
@testable import Venture

final class PasswordStrengthTests: XCTestCase {
    func testAcceptablePasswordUsesLengthAndThreeCharacterClasses() {
        XCTAssertTrue(PasswordStrength(password: "ventureSecure42").isAcceptable)
        XCTAssertFalse(PasswordStrength(password: "alllowercasepassword").isAcceptable)
        XCTAssertFalse(PasswordStrength(password: "Short42!").isAcceptable)
        XCTAssertTrue(PasswordStrength(password: "venture42!x").isAcceptable)
    }

    func testStrongPasswordUsesAllClassesAndLongerLength() {
        let strength = PasswordStrength(password: "venture-Is-Private-42")
        XCTAssertEqual(strength.score, 4)
        XCTAssertEqual(strength.label, "strong")
    }

    func testWhitespaceIsRejected() {
        XCTAssertFalse(PasswordStrength(password: "venture Secure 42!").isAcceptable)
    }
}
