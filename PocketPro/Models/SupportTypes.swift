import Foundation
import PocketProCore

// MARK: - Equipment enums (PRD 5.4)

enum ThumbType: String, Codable, CaseIterable, Identifiable {
    case noThumb = "none"
    case slug
    case interchangeable

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noThumb: return "No Thumb"
        case .slug: return "Slug"
        case .interchangeable: return "Interchangeable"
        }
    }
}

enum SlugMaterial: String, Codable, CaseIterable, Identifiable {
    case urethane, plastic, rubber, custom

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

/// PRD 5.4.4a — confirm-before-ship list; extendable via OTA data update.
enum ThumbSystemBrand: String, Codable, CaseIterable, Identifiable {
    case viseIT = "vise_it"
    case joPo = "jopo"
    case turboSwitchGrip = "turbo_switch_grip"
    case monsterGrip = "monster_grip"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .viseIT: return "VISE IT"
        case .joPo: return "JoPo"
        case .turboSwitchGrip: return "Turbo Switch Grip"
        case .monsterGrip: return "Monster Grip"
        case .custom: return "Custom"
        }
    }
}

enum GripType: String, Codable, CaseIterable, Identifiable {
    case fingertip
    case conventional
    case modifiedFingertip = "modified_fingertip"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fingertip: return "Fingertip"
        case .conventional: return "Conventional"
        case .modifiedFingertip: return "Modified Fingertip"
        }
    }
}

enum SpanConvention: String, Codable, CaseIterable, Identifiable {
    case edgeToEdge = "edge_to_edge"
    case centerToCenter = "ctc"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .edgeToEdge: return "Edge-to-Edge"
        case .centerToCenter: return "Center-to-Center"
        }
    }

    var shortName: String {
        switch self {
        case .edgeToEdge: return "E-E"
        case .centerToCenter: return "CTC"
        }
    }
}

enum LayoutSystem: String, Codable, CaseIterable, Identifiable {
    case dualAngle = "dual_angle"
    case vls

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dualAngle: return "Dual Angle"
        case .vls: return "VLS"
        }
    }

    var shortName: String {
        switch self {
        case .dualAngle: return "DA"
        case .vls: return "VLS"
        }
    }
}

/// Layout archival reasons (PRD 5.4.6).
enum LayoutChangeReason: String, Codable, CaseIterable, Identifiable {
    case redrilled = "re_drilled"
    case crackedReplaced = "cracked_replaced"
    case newPurchase = "new_purchase"
    case adjustedLayout = "adjusted_layout"
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .redrilled: return "Re-drilled"
        case .crackedReplaced: return "Cracked ball — replaced"
        case .newPurchase: return "New purchase"
        case .adjustedLayout: return "Adjusted layout"
        case .other: return "Other"
        }
    }
}

// MARK: - Surface (PRD 5.4.7)

enum SurfaceGrit: String, Codable, CaseIterable, Identifiable {
    case grit500 = "500"
    case grit1000 = "1000"
    case grit1500 = "1500"
    case grit2000 = "2000"
    case grit2500 = "2500"
    case grit3000 = "3000"
    case grit4000 = "4000"
    case polished

    var id: String { rawValue }

    var displayName: String {
        self == .polished ? "Polished" : rawValue
    }

    /// Numeric value for the arsenal chart axis; polished plotted above the grit scale.
    var numericValue: Double {
        self == .polished ? 5000 : Double(rawValue) ?? 0
    }
}

enum FinishType: String, Codable, CaseIterable, Identifiable {
    case abralon
    case scotchBrite = "scotch_brite"
    case factoryFinish = "factory_finish"
    case highGlossPolish = "high_gloss_polish"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .abralon: return "Abralon"
        case .scotchBrite: return "Scotch-Brite"
        case .factoryFinish: return "Factory Finish"
        case .highGlossPolish: return "High Gloss Polish"
        case .custom: return "Custom"
        }
    }
}

// MARK: - Patterns (PRD 5.1.1)

enum PatternType: String, Codable, CaseIterable, Identifiable {
    case houseShot = "house_shot"
    case sport
    case pbaExperience = "pba_experience"
    case usbcSport = "usbc_sport"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .houseShot: return "House Shot"
        case .sport: return "Sport"
        case .pbaExperience: return "PBA Experience"
        case .usbcSport: return "USBC Sport"
        case .custom: return "Custom"
        }
    }
}

enum OilRatio: String, Codable, CaseIterable, Identifiable {
    case easy
    case medium
    case difficult
    case sport

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy: return "Easy (10:1+)"
        case .medium: return "Medium (7:1–9:1)"
        case .difficult: return "Difficult (4:1–6:1)"
        case .sport: return "Sport (3:1 or less)"
        }
    }

    var shortName: String {
        switch self {
        case .easy: return "Easy"
        case .medium: return "Medium"
        case .difficult: return "Difficult"
        case .sport: return "Sport"
        }
    }
}

/// Performance-note pattern buckets (PRD 5.4.8).
enum PatternBucket: String, Codable, CaseIterable, Identifiable {
    case house
    case sport
    case short
    case medium
    case long

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .house: return "House Shot"
        case .sport: return "Sport / Challenge"
        case .short: return "Short Pattern (≤35 ft)"
        case .medium: return "Medium Pattern (36–42 ft)"
        case .long: return "Long Pattern (43 ft+)"
        }
    }
}

// MARK: - Bags (PRD 5.4.11)

enum BagType: String, Codable, CaseIterable, Identifiable {
    case league
    case tournament
    case practice

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }
}

enum BallRole: String, Codable, CaseIterable, Identifiable {
    case earlyRead = "early_read"
    case benchmark
    case midLane = "mid_lane"
    case backEnd = "back_end"
    case urethane
    case control
    case spare

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .earlyRead: return "Early read"
        case .benchmark: return "Benchmark"
        case .midLane: return "Mid-lane"
        case .backEnd: return "Back end"
        case .urethane: return "Urethane"
        case .control: return "Control"
        case .spare: return "Spare"
        }
    }
}

// MARK: - Codable attribute payloads

/// One delivered ball within a frame. `standingAfterMask` is the standing-pin bitmask
/// at the current rack after this ball; nil when pin identity is unknown
/// (direct-score entry or PinPal count-only import).
struct BallEntry: Codable, Hashable {
    var count: Int = 0
    var standingAfterMask: Int?
}

/// One ordered ball slot in a bag variation (PRD §6 BagVariation.ball_slots).
struct BagSlot: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var ballID: UUID
    var roleLabel: String?
    var order: Int = 0
}

// MARK: - Stats filters (PRD 5.3)

enum StatDateRange: String, CaseIterable, Identifiable {
    case thisWeek = "week"
    case thisMonth = "month"
    case thisSeason = "season"
    case lastYear = "year"
    case allTime = "all"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thisWeek: return "This Week"
        case .thisMonth: return "Last Month"
        case .thisSeason: return "This Season"
        case .lastYear: return "Last Year"
        case .allTime: return "All Time"
        case .custom: return "Custom"
        }
    }
}

/// Season definition (PRD 15 open question → user-configurable, DECISIONS.md D13).
enum SeasonDefinition: String, CaseIterable, Identifiable {
    case usbc          // Aug 1 – Jul 31
    case rolling12     // trailing 12 months

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .usbc: return "USBC Season (Aug–Jul)"
        case .rolling12: return "Rolling 12 Months"
        }
    }

    /// Start date of the current season relative to `now`.
    func seasonStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .rolling12:
            return calendar.date(byAdding: .month, value: -12, to: now) ?? now
        case .usbc:
            var components = calendar.dateComponents([.year, .month], from: now)
            let month = components.month ?? 1
            components.month = 8
            components.day = 1
            if month < 8 {
                components.year = (components.year ?? 0) - 1
            }
            return calendar.date(from: components) ?? now
        }
    }
}

enum ScoreEntryMode: String, CaseIterable, Identifiable {
    case pinDeck = "pin_deck"
    case direct

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pinDeck: return "Pin-by-pin"
        case .direct: return "Direct score"
        }
    }
}
