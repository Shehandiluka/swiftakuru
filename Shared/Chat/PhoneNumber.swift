import Foundation

/// E.164 phone number normalization ("+94771234567").
/// Numbers without a country code use the user's default calling code (Settings → Chat, default +94).
enum PhoneNumber {
    /// Calling codes for the countries Swift Akuru users are most likely in. Others can be typed with "+".
    static let callingCodes: [String: String] = [
        "LK": "94", "IL": "972", "IN": "91", "AE": "971", "QA": "974", "SA": "966", "KW": "965", "OM": "968", "BH": "973",
        "MV": "960", "IT": "39", "KR": "82", "JP": "81", "AU": "61", "NZ": "64", "GB": "44", "US": "1", "CA": "1",
        "CY": "357", "MY": "60", "SG": "65", "DE": "49", "FR": "33", "CH": "41", "NO": "47", "SE": "46",
    ]

    /// Returns "+<digits>" (8–15 digits, no leading zero after "+") or nil.
    static func normalize(_ raw: String, defaultCallingCode: String = "94") -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // only digits, +, spaces, dashes, dots, parentheses are allowed
        let allowed = CharacterSet(charactersIn: "0123456789+ -().\u{00A0}")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        let plusCount = trimmed.filter { $0 == "+" }.count
        guard plusCount == 0 || (plusCount == 1 && trimmed.hasPrefix("+")) else { return nil }
        var digits = trimmed.filter { $0.isASCII && $0.isNumber }
        let cc = defaultCallingCode.filter { $0.isASCII && $0.isNumber }
        if trimmed.hasPrefix("+") {
            // already international
        } else if digits.hasPrefix("00") {
            digits.removeFirst(2)
        } else if digits.hasPrefix("0") {
            digits = cc + String(digits.drop(while: { $0 == "0" }))
        } else if digits.count <= 10 {
            // national number typed without the trunk 0 (e.g. 771234567); longer = already has a country code
            digits = cc + digits
        }
        guard (8...15).contains(digits.count), let first = digits.first, first != "0" else { return nil }
        return "+" + digits
    }

    static func isValidE164(_ s: String) -> Bool {
        guard s.hasPrefix("+") else { return false }
        let d = s.dropFirst()
        return (8...15).contains(d.count) && d.allSatisfy { $0.isASCII && $0.isNumber } && d.first != "0"
    }

    /// "+94771234567" → "+94 77 123 4567" style grouping for display only.
    static func display(_ e164: String) -> String {
        guard e164.count > 6 else { return e164 }
        let d = Array(e164.dropFirst())
        var parts: [String] = []
        var i = 0
        let first = d.count > 11 ? 3 : 2
        parts.append(String(d[0..<first])); i = first
        while i < d.count { let n = min(i + 3, d.count); parts.append(String(d[i..<n])); i = n }
        return "+" + parts.joined(separator: " ")
    }
}

/// Parses the keyboard's Secret Chat access command: "<PIN><phone>" with a fixed-length PIN.
/// Used ONLY inside the Secret Chat access panel — never as a general typing rule.
enum SecretCommand {
    struct Parsed: Equatable { let pin: String; let phone: String }

    static func parse(_ input: String, pinLength: Int, defaultCallingCode: String) -> Parsed? {
        guard (4...8).contains(pinLength) else { return nil }
        let cleaned = input.filter { !$0.isWhitespace && $0 != "-" }
        guard cleaned.count > pinLength else { return nil }
        let pin = String(cleaned.prefix(pinLength))
        guard pin.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let rest = String(cleaned.dropFirst(pinLength))
        guard let phone = PhoneNumber.normalize(rest, defaultCallingCode: defaultCallingCode) else { return nil }
        return Parsed(pin: pin, phone: phone)
    }
}
