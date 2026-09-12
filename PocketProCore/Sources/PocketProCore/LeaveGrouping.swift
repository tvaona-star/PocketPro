import Foundation

/// One distinct leave (by standing pins) aggregated across a set of games: how often
/// it came up and how often it was converted when a spare was actually possible.
public struct LeaveGroup: Hashable, Identifiable, Sendable {
    /// The pin mask — stable identity for the group.
    public let id: Int
    public let pins: PinSet
    /// Category of the first occurrence (respects a manual override on that leave).
    public let primary: LeaveCategory
    public let isSplit: Bool
    /// Times the leave came up, including fill-ball occurrences.
    public let total: Int
    /// Occurrences where a spare could be made (fill-ball leaves excluded).
    public let attempts: Int
    public let made: Int

    public var percent: Double? {
        attempts == 0 ? nil : Double(made) / Double(attempts) * 100
    }

    public var classification: LeaveClassification {
        LeaveClassifier.classify(pins)
    }

    public init(id: Int, pins: PinSet, primary: LeaveCategory, isSplit: Bool,
                total: Int, attempts: Int, made: Int) {
        self.id = id
        self.pins = pins
        self.primary = primary
        self.isSplit = isSplit
        self.total = total
        self.attempts = attempts
        self.made = made
    }
}

public enum LeaveGrouping {
    /// Groups leaves by standing pins. Ordered most-frequent first, then by fewest
    /// pins so simple leaves sort ahead of clusters at equal frequency.
    public static func group(_ leaves: [LeaveRecord]) -> [LeaveGroup] {
        var order: [Int] = []
        var sample: [Int: LeaveRecord] = [:]
        var total: [Int: Int] = [:]
        var attempts: [Int: Int] = [:]
        var made: [Int: Int] = [:]
        for leave in leaves {
            let key = leave.pins.mask
            if sample[key] == nil { sample[key] = leave; order.append(key) }
            total[key, default: 0] += 1
            if leave.hadOpportunity {
                attempts[key, default: 0] += 1
                if leave.converted { made[key, default: 0] += 1 }
            }
        }
        return order.compactMap { key -> LeaveGroup? in
            guard let first = sample[key] else { return nil }
            return LeaveGroup(id: key,
                              pins: first.pins,
                              primary: first.primary,
                              isSplit: first.categories.contains(.split),
                              total: total[key] ?? 0,
                              attempts: attempts[key] ?? 0,
                              made: made[key] ?? 0)
        }
        .sorted {
            if $0.total != $1.total { return $0.total > $1.total }
            return $0.pins.count < $1.pins.count
        }
    }
}
