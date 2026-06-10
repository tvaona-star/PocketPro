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

    private static func gcd(_ a: Int, _ b: Int) -> Int {
        var x = a
        var y = b
        while y != 0 {
            (x, y) = (y, x % y)
        }
        return max(x, 1)
    }
}
