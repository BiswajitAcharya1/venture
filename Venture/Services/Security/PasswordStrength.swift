import Foundation

struct PasswordStrength {
    let password: String

    var hasMinimumLength: Bool { password.count >= 10 }
    var hasLowercase: Bool { password.rangeOfCharacter(from: .lowercaseLetters) != nil }
    var hasUppercase: Bool { password.rangeOfCharacter(from: .uppercaseLetters) != nil }
    var hasNumber: Bool { password.rangeOfCharacter(from: .decimalDigits) != nil }
    var hasSymbol: Bool {
        let allowedSymbols = CharacterSet.punctuationCharacters.union(.symbols)
        return password.rangeOfCharacter(from: allowedSymbols) != nil
    }
    var hasNoWhitespace: Bool { password.rangeOfCharacter(from: .whitespacesAndNewlines) == nil }

    var characterVariety: Int {
        [hasLowercase, hasUppercase, hasNumber, hasSymbol].filter { $0 }.count
    }

    var isAcceptable: Bool {
        hasMinimumLength && hasNoWhitespace && characterVariety >= 3 && password.count <= 128
    }

    var score: Int {
        guard !password.isEmpty else { return 0 }
        var value = 0
        if password.count >= 6 { value += 1 }
        if hasMinimumLength { value += 1 }
        if characterVariety >= 3 && hasNoWhitespace { value += 1 }
        if hasMinimumLength && hasNoWhitespace && (characterVariety == 4 || password.count >= 14) { value += 1 }
        return min(4, value)
    }

    var label: String {
        switch score {
        case 0, 1: "weak"
        case 2: "fair"
        case 3: "good"
        default: "strong"
        }
    }
}
