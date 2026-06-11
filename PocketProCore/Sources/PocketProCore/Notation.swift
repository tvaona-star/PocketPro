import Foundation

/// Bowling-native notation formatting (PRD 7.5): layouts display as bowlers write them
/// (50° x 4 3/4" x 40°), never as decimals with unit words.
public enum Notation {

    /// Formats a measurement in inches as a fraction string: 4.75 → `4 3/4"`, 0.5 → `1/2"`, 4 → `4"`.
    /// Values are snapped to the nearest 1/16 inch.
    public static func inches(_ value: Double) -> String {
        let sign = value < 0 ? "-" : ""
        let totalSixteenths = Int((abs(value) * 16).rounded())
        let whole = totalSixteenths / 16
        let remainder = totalSixteenths % 16

        if remainder == 0 {
            return "\(sign)\(whole)\""
        }
        let divisor = gcd(remainder, 16)
        let num = remainder / divisor
        let den = 16 / divisor
        if whole == 0 {
            return "\(sign)\(num)/\(den)\""
        }
        return "\(sign)\(whole) \(num)/\(den)\""
    }

    /// Formats degrees: 50 → `50°`, 47.5 → `47.5°`.
    public static func degrees(_ value: Double) -> String {
        if value.rounded() == value {
            return "\(Int(value))°"
        }
        return String(format: "%.1f°", value)
    }

    /// Dual Angle shorthand: `50° x 4 3/4" x 40°`. Missing fields collapse out.
    public static func dualAngleShorthand(drillingAngle: Double?, pinToPAP: Double?, valAngle: Double?) -> String {
        var parts: [String] = []
        if let a = drillingAngle { parts.append(degrees(a)) }
        if let p = pinToPAP { parts.append(inches(p)) }
        if let v = valAngle { parts.append(degrees(v)) }
        return parts.joined(separator: " x ")
    }

    /// VLS shorthand: `4" / 3 3/4" / 2"` (pin-to-PAP / CG-to-PAP / pin buffer), `+ MB 3 1/2"` when present.
    public static func vlsShorthand(pinToPAP: Double?, cgToPAP: Double?, pinBuffer: Double?, mbDistance: Double?) -> String {
        var parts: [String] = []
        if let p = pinToPAP { parts.append(inches(p)) }
        if let c = cgToPAP { parts.append(inches(c)) }
        if let b = pinBuffer { parts.append(inches(b)) }
        var result = parts.joined(separator: " / ")
        if let mb = mbDistance {
            result += result.isEmpty ? "MB \(inches(mb))" : " + MB \(inches(mb))"
        }
        return result
    }

    /// PAP display: `5 1/2" over, 3/8" up` (PRD 5.4.1).
    public static func pap(over: Double?, up: Double?) -> String {
        guard let over else { return "Not set" }
        var result = "\(inches(over)) over"
        if let up, up != 0 {
            result += up > 0 ? ", \(inches(up)) up" : ", \(inches(abs(up))) down"
        }
        return result
    }

    /// One decimal place, used for RG/averages: 213.4.
    public static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    /// Percent display with one decimal: 67.4%.
    public static func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.1f%%", value)
    }

    /// Inches formatted for an editable text field — like `inches` but without the
    /// trailing quote, so it round-trips through `parseInches`. 4.5 → `4 1/2`.
    public static func editableInches(_ value: Double) -> String {
        let s = inches(value)
        return s.hasSuffix("\"") ? String(s.dropLast()) : s
    }

    /// Parses bowler-written inches into a Double. Accepts decimals (`4.5`),
    /// mixed fractions (`4 1/2`, `4-1/2`), bare fractions (`1/2`), and unicode
    /// vulgar fractions (`4½`, `½`). Returns nil for anything it can't read.
    public static func parseInches(_ raw: String) -> Double? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: ",", with: ".")

        // Expand unicode vulgar fractions to "n/d", inserting a space after a
        // preceding digit so "4½" becomes "4 1/2".
        let vulgar: [Character: String] = [
            "¼": "1/4", "½": "1/2", "¾": "3/4",
            "⅓": "1/3", "⅔": "2/3",
            "⅕": "1/5", "⅖": "2/5", "⅗": "3/5", "⅘": "4/5",
            "⅙": "1/6", "⅚": "5/6",
            "⅛": "1/8", "⅜": "3/8", "⅝": "5/8", "⅞": "7/8",
        ]
        var expanded = ""
        for ch in s {
            if let frac = vulgar[ch] {
                if let last = expanded.last, last.isNumber { expanded.append(" ") }
                expanded += frac
            } else {
                expanded.append(ch)
            }
        }
        s = expanded
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)

        func token(_ t: String) -> Double? {
            if t.contains("/") {
                let parts = t.split(separator: "/")
                guard parts.count == 2,
                      let n = Double(String(parts[0])), let d = Double(String(parts[1])), d != 0 else { return nil }
                return n / d
            }
            return Double(t)
        }

        let tokens = s.split(separator: " ").map(String.init)
        switch tokens.count {
        case 1:
            return token(tokens[0])
        case 2:
            guard let whole = Double(tokens[0]), let frac = token(tokens[1]) else { return nil }
            return whole < 0 ? whole - frac : whole + frac
        default:
            return nil
        }
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 {
            (x, y) = (y, x % y)
        }
        return max(x, 1)
    }
}
