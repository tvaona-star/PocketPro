import Foundation

/// Leave classification categories (PRD 5.5.1).
/// Raw values are both the badge/priority order (lower = higher priority) and the
/// bit positions in the generated `LeaveTable.packed` bitsets — do not reorder.
public enum LeaveCategory: Int, CaseIterable, Codable, Sendable, Comparable, Identifiable {
    case washout = 0
    case sevenTen = 1
    case bigFour = 2
    case bucket = 3
    case cornerPin = 4
    case singlePin = 5
    case sleeper = 6
    case babySplit = 7
    case bigSplit = 8
    case split = 9
    case cluster = 10
    case other = 11

    public var id: Int { rawValue }

    public static func < (lhs: LeaveCategory, rhs: LeaveCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Stable storage identifier matching the PRD §6 data-model enum strings.
    public var storageKey: String {
        switch self {
        case .washout: return "washout"
        case .sevenTen: return "seven_ten"
        case .bigFour: return "big_four"
        case .bucket: return "bucket"
        case .cornerPin: return "corner_pin"
        case .singlePin: return "single_pin"
        case .sleeper: return "sleeper"
        case .babySplit: return "baby_split"
        case .bigSplit: return "big_split"
        case .split: return "split"
        case .cluster: return "cluster"
        case .other: return "other"
        }
    }

    public init?(storageKey: String) {
        guard let match = LeaveCategory.allCases.first(where: { $0.storageKey == storageKey }) else {
            return nil
        }
        self = match
    }

    /// Bowler-facing display name (PRD 7.5: bowling-native language).
    public var displayName: String {
        switch self {
        case .washout: return "Washout"
        case .sevenTen: return "7-10"
        case .bigFour: return "Big Four"
        case .bucket: return "Bucket"
        case .cornerPin: return "Corner Pin"
        case .singlePin: return "Single Pin"
        case .sleeper: return "Sleeper"
        case .babySplit: return "Baby Split"
        case .bigSplit: return "Big Split"
        case .split: return "Split"
        case .cluster: return "Cluster"
        case .other: return "Other"
        }
    }

    /// Plural form used for filter chips and breakdown rows.
    public var pluralDisplayName: String {
        switch self {
        case .washout: return "Washouts"
        case .sevenTen: return "7-10"
        case .bigFour: return "Big Four"
        case .bucket: return "Buckets"
        case .cornerPin: return "Corner Pins"
        case .singlePin: return "Single Pins"
        case .sleeper: return "Sleepers"
        case .babySplit: return "Baby Splits"
        case .bigSplit: return "Big Splits"
        case .split: return "Splits"
        case .cluster: return "Clusters"
        case .other: return "Other"
        }
    }
}

/// The resolved classification for one leave.
public struct LeaveClassification: Hashable, Sendable {
    public let pins: PinSet
    /// All applicable categories, sorted by priority. First element is the primary (badge) category.
    public let categories: [LeaveCategory]
    /// Display name for named leaves ("Bucket", "7-10", "Greek Church", ...), nil otherwise.
    public let name: String?

    public var primary: LeaveCategory {
        categories.first ?? .other
    }

    /// True when this leave counts toward Split % (includes baby splits, big splits, 7-10, Big Four).
    public var isSplit: Bool {
        categories.contains(.split)
    }

    /// Row title for leave lists: the name when one exists, pin numbers otherwise (PRD 5.5.4).
    public var displayTitle: String {
        name ?? pins.displayString
    }
}

/// Lookup-table classifier (PRD 5.5.3): all 1,023 combinations pre-resolved at build time
/// by tools/classifier/generate.ps1. No rule evaluation happens at runtime.
public enum LeaveClassifier {
    public static func classify(_ pins: PinSet) -> LeaveClassification {
        let mask = pins.mask
        guard mask > 0, mask < LeaveTable.packed.count else {
            return LeaveClassification(pins: pins, categories: [], name: nil)
        }
        let packed = LeaveTable.packed[mask]
        var categories: [LeaveCategory] = []
        for category in LeaveCategory.allCases where (packed & (UInt16(1) << category.rawValue)) != 0 {
            categories.append(category)
        }
        return LeaveClassification(pins: pins, categories: categories, name: LeaveTable.names[mask])
    }

    public static func classify(standingPins: [Int]) -> LeaveClassification {
        classify(PinSet(pins: standingPins))
    }
}
