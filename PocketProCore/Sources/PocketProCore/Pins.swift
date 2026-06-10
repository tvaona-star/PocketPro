import Foundation

/// A set of standing pins, stored as a 10-bit mask (bit `pin - 1` set = pin standing).
/// The canonical pin-identity type used by the classifier, scoring flows, and pin diagrams.
public struct PinSet: Hashable, Codable, Sendable {
    public var mask: Int

    public init(mask: Int) {
        self.mask = mask & 0x3FF
    }

    public init(pins: [Int]) {
        var m = 0
        for p in pins where (1...10).contains(p) {
            m |= 1 << (p - 1)
        }
        self.mask = m
    }

    public static let full = PinSet(mask: 0x3FF)
    public static let empty = PinSet(mask: 0)

    /// Standing pin numbers in ascending order.
    public var pins: [Int] {
        (1...10).filter { contains($0) }
    }

    public var count: Int {
        mask.nonzeroBitCount
    }

    public var isEmpty: Bool {
        mask == 0
    }

    public func contains(_ pin: Int) -> Bool {
        guard (1...10).contains(pin) else { return false }
        return mask & (1 << (pin - 1)) != 0
    }

    public mutating func insert(_ pin: Int) {
        guard (1...10).contains(pin) else { return }
        mask |= 1 << (pin - 1)
    }

    public mutating func remove(_ pin: Int) {
        guard (1...10).contains(pin) else { return }
        mask &= ~(1 << (pin - 1))
    }

    public mutating func toggle(_ pin: Int) {
        if contains(pin) { remove(pin) } else { insert(pin) }
    }

    /// Pins in `self` that are not in `other` (e.g. pins knocked down between balls).
    public func subtracting(_ other: PinSet) -> PinSet {
        PinSet(mask: mask & ~other.mask)
    }

    /// Display string like "3-6-10".
    public var displayString: String {
        pins.map(String.init).joined(separator: "-")
    }
}

/// Pin deck geometry shared by diagrams and entry views.
/// Row 0 is the head pin; x2 is the doubled board offset so positions stay integral.
public enum PinGeometry {
    /// (row, x2) indexed by pin number 1...10. Index 0 is unused.
    public static let positions: [(row: Int, x2: Int)] = [
        (0, 0),   // unused
        (0, 0),   // 1
        (1, -1),  // 2
        (1, 1),   // 3
        (2, -2),  // 4
        (2, 0),   // 5
        (2, 2),   // 6
        (3, -3),  // 7
        (3, -1),  // 8
        (3, 1),   // 9
        (3, 3),   // 10
    ]

    /// Unit-square layout point for a pin (x, y in 0...1), back row at top.
    /// Suitable for scaling into any square drawing rect.
    public static func unitPoint(pin: Int) -> (x: Double, y: Double) {
        guard (1...10).contains(pin) else { return (0.5, 0.5) }
        let p = positions[pin]
        // x2 spans -3...3 → map to 0.1...0.9; row 0...3 → y 0.9 (front) ... 0.1 (back)
        let x = 0.5 + Double(p.x2) / 7.5
        let y = 0.9 - Double(p.row) * (0.8 / 3.0)
        return (x, y)
    }
}
