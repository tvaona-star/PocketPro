import Foundation
import SwiftData
import PocketProCore

// SwiftData models (PRD §6). CloudKit-compatible by construction (DECISIONS.md D4):
// every stored property has a default, every relationship is optional, no unique
// constraints. Enum-typed fields are stored as raw strings with typed accessors.

// MARK: - Bowler profile (PRD 5.4.1)

@Model
final class BowlerProfile {
    var displayName: String = ""
    /// PAP horizontal — inches over (primary field).
    var papOver: Double?
    /// PAP vertical — inches up (negative = down).
    var papUp: Double?
    var ballSpeedMPH: Double?
    var revRate: Double?
    var axisTilt: Double?
    var axisRotation: Double?
    var defaultGripTypeRaw: String = GripType.fingertip.rawValue
    var defaultBallWeight: Int = 15
    var createdAt: Date = Date()

    init() {}

    var defaultGripType: GripType {
        get { GripType(rawValue: defaultGripTypeRaw) ?? .fingertip }
        set { defaultGripTypeRaw = newValue.rawValue }
    }

    var papDisplay: String {
        Notation.pap(over: papOver, up: papUp)
    }
}

// MARK: - Session / Game / Frame (PRD 5.1, 5.2)

@Model
final class Session {
    var id: UUID = UUID()
    var typeRaw: String = SessionType.league.rawValue
    var leagueName: String?
    var eventName: String?
    var date: Date = Date()
    var notes: String = ""
    var createdAt: Date = Date()
    /// True while the Bowl tab has this session live.
    var isActive: Bool = false

    var location: Location?
    var pattern: Pattern?
    var bag: Bag?
    /// Ad-hoc "balls in bag today" multi-select (PRD 5.1) — pre-populates the ball picker.
    var todaysBallIDs: [UUID] = []

    @Relationship(deleteRule: .cascade, inverse: \Game.session)
    var games: [Game]? = []

    /// PinPal import bookkeeping (PRD 13.4): source row hash for re-import safety.
    var importSourceHash: String?
    var importedFromPinPal: Bool = false
    /// Imported sessions default to League and are flagged for re-tagging (PRD 13.2).
    var needsTypeReview: Bool = false
    var flaggedAsPotentialDuplicate: Bool = false

    init() {}

    var type: SessionType {
        get { SessionType(rawValue: typeRaw) ?? .league }
        set { typeRaw = newValue.rawValue }
    }

    var sortedGames: [Game] {
        (games ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// League or event name appropriate to the session type.
    var title: String {
        if let league = leagueName, !league.isEmpty { return league }
        if let event = eventName, !event.isEmpty { return event }
        return type.displayName
    }
}

@Model
final class Game {
    var id: UUID = UUID()
    var orderIndex: Int = 0
    var session: Session?
    /// Starting ball for the game.
    var ballID: UUID?
    var finalScoreStored: Int = 0
    /// False for imported games carrying only a final score (PRD 13.4).
    var hasFrameData: Bool = true
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \Frame.game)
    var frames: [Frame]? = []

    init() {}

    var sortedFrames: [Frame] {
        (frames ?? []).sorted { $0.number < $1.number }
    }

    /// Pinfall-count matrix for the scoring engine.
    var frameCounts: [[Int]] {
        sortedFrames.map { frame in frame.balls.map { $0.count } }
    }

    var liveScore: ScoringEngine.GameScore {
        ScoringEngine.score(frames: frameCounts)
    }

    /// Authoritative final score: engine result when frame data exists, stored value otherwise.
    var finalScore: Int {
        if hasFrameData, let computed = liveScore.final {
            return computed
        }
        return finalScoreStored
    }

    var isComplete: Bool {
        if hasFrameData {
            return ScoringEngine.isGameComplete(frames: frameCounts)
        }
        return true
    }

    /// Every ball used in this game (starting ball + mid-game swaps), in order of first use.
    var ballIDsUsed: [UUID] {
        var seen: [UUID] = []
        if let first = ballID { seen.append(first) }
        for frame in sortedFrames {
            if let swap = frame.ballID, !seen.contains(swap) {
                seen.append(swap)
            }
        }
        return seen
    }
}

@Model
final class Frame {
    var id: UUID = UUID()
    /// 1-based frame number (1...10).
    var number: Int = 1
    var game: Game?
    /// Balls delivered in this frame; pin identity carried when available.
    var balls: [BallEntry] = []
    /// Ball in hand for this frame when it differs from the game's starting ball (mid-game swap).
    var ballID: UUID?
    var ballSwapReason: String?

    // Structured frame note (PRD 5.1): lane-play fields, all optional.
    var targetBoard: Int?
    var boardHit: Int?
    var breakpointBoard: Int?
    var breakpointDistanceFt: Double?
    var note: String?

    /// Manual leave-category override (PRD 5.5.3), storage key of LeaveCategory.
    var leaveOverrideRaw: String?

    init() {}

    var leaveOverride: LeaveCategory? {
        get { leaveOverrideRaw.flatMap { LeaveCategory(storageKey: $0) } }
        set { leaveOverrideRaw = newValue?.storageKey }
    }

    var counts: [Int] {
        balls.map { $0.count }
    }

    var hasLanePlayData: Bool {
        targetBoard != nil || boardHit != nil || breakpointBoard != nil || breakpointDistanceFt != nil
    }

    var hasNote: Bool {
        hasLanePlayData || !(note ?? "").isEmpty
    }
}

// MARK: - Equipment (PRD 5.4)

@Model
final class Ball {
    var id: UUID = UUID()
    /// Pocket Pro ball-database record ID; nil for manual entries and PinPal shell records.
    var dbBallID: String?

    // Identity snapshot (works offline and for shell/manual records).
    var brand: String = ""
    var model: String = ""
    var year: Int?
    var manufacturer: String = ""
    var coverstockTypeRaw: String?
    var coverstockName: String?
    var coreName: String?
    var asymmetric: Bool = false
    var factoryFinish: String?
    /// Specs snapshot at the bowler's weight (PRD 9.4 fallback noted via specIsFallback).
    var rg: Double?
    var diff: Double?
    var intDiff: Double?
    var specWeightUsed: Int?
    var specIsFallback: Bool = false
    var sharedCoreID: String?

    // Bowler fields.
    var weight: Int = 15
    var purchaseDate: Date?
    var drillingNotes: String = ""
    var active: Bool = true
    /// PinPal shell record awaiting spec completion (PRD 13.3 review action 2).
    var importedShell: Bool = false

    // Thumb type (PRD 5.4.4a).
    var thumbTypeRaw: String = ThumbType.noThumb.rawValue
    var thumbSlugBrand: String?
    var thumbSlugMaterialRaw: String?
    var thumbSystemBrandRaw: String?
    var thumbHoleSize: String?
    var thumbHolePitch: String?

    // Subjective chart ratings (PRD 5.4.10).
    var hookAmount: Int?
    var lengthRating: Int?

    // Performance notes by pattern bucket (PRD 5.4.8).
    var notesHouse: String = ""
    var notesSport: String = ""
    var notesShort: String = ""
    var notesMedium: String = ""
    var notesLong: String = ""

    var activeLayout: Layout?

    @Relationship(deleteRule: .cascade, inverse: \BallLayoutHistory.ball)
    var layoutHistory: [BallLayoutHistory]? = []

    @Relationship(deleteRule: .cascade, inverse: \SurfaceLog.ball)
    var surfaceLogs: [SurfaceLog]? = []

    init() {}

    var displayName: String {
        brand.isEmpty ? model : "\(brand) \(model)"
    }

    var coverstockType: CoverstockType? {
        get { coverstockTypeRaw.flatMap { CoverstockType(rawValue: $0) } }
        set { coverstockTypeRaw = newValue?.rawValue }
    }

    var thumbType: ThumbType {
        get { ThumbType(rawValue: thumbTypeRaw) ?? .noThumb }
        set { thumbTypeRaw = newValue.rawValue }
    }

    var thumbSlugMaterial: SlugMaterial? {
        get { thumbSlugMaterialRaw.flatMap { SlugMaterial(rawValue: $0) } }
        set { thumbSlugMaterialRaw = newValue?.rawValue }
    }

    var thumbSystemBrand: ThumbSystemBrand? {
        get { thumbSystemBrandRaw.flatMap { ThumbSystemBrand(rawValue: $0) } }
        set { thumbSystemBrandRaw = newValue?.rawValue }
    }

    var sortedSurfaceLogs: [SurfaceLog] {
        (surfaceLogs ?? []).sorted { $0.date > $1.date }
    }

    var latestSurfaceLog: SurfaceLog? {
        sortedSurfaceLogs.first
    }

    var sortedLayoutHistory: [BallLayoutHistory] {
        (layoutHistory ?? []).sorted { $0.becameActiveAt > $1.becameActiveAt }
    }

    func performanceNote(for bucket: PatternBucket) -> String {
        switch bucket {
        case .house: return notesHouse
        case .sport: return notesSport
        case .short: return notesShort
        case .medium: return notesMedium
        case .long: return notesLong
        }
    }

    func setPerformanceNote(_ text: String, for bucket: PatternBucket) {
        switch bucket {
        case .house: notesHouse = text
        case .sport: notesSport = text
        case .short: notesShort = text
        case .medium: notesMedium = text
        case .long: notesLong = text
        }
    }

    var performanceNoteCount: Int {
        PatternBucket.allCases.filter { !performanceNote(for: $0).isEmpty }.count
    }
}

@Model
final class Layout {
    var id: UUID = UUID()
    var name: String = ""
    var systemRaw: String = LayoutSystem.dualAngle.rawValue
    var createdAt: Date = Date()
    var notes: String = ""

    // Dual Angle fields (PRD 5.4.5).
    var drillingAngle: Double?
    var valAngle: Double?

    // Shared / VLS fields.
    var pinToPAP: Double?
    var cgToPAP: Double?
    var pinBuffer: Double?
    var mbPsaDistance: Double?

    // Drilling specs — shared across both systems (PRD 5.4.5).
    var gripTypeRaw: String?
    var spanConventionRaw: String?
    var middleSpan: Double?
    var ringSpan: Double?
    var bridgeWidth: Double?
    var middleHoleSize: String?
    var ringHoleSize: String?
    var middlePitch: String?
    var ringPitch: String?
    var thumbHoleSize: String?
    var thumbPitch: String?

    init() {}

    var system: LayoutSystem {
        get { LayoutSystem(rawValue: systemRaw) ?? .dualAngle }
        set { systemRaw = newValue.rawValue }
    }

    var gripType: GripType? {
        get { gripTypeRaw.flatMap { GripType(rawValue: $0) } }
        set { gripTypeRaw = newValue?.rawValue }
    }

    var spanConvention: SpanConvention? {
        get { spanConventionRaw.flatMap { SpanConvention(rawValue: $0) } }
        set { spanConventionRaw = newValue?.rawValue }
    }

    /// Bowling-notation shorthand (PRD 7.5): `50° x 4 3/4" x 40°` or VLS distances.
    var shorthand: String {
        switch system {
        case .dualAngle:
            return Notation.dualAngleShorthand(drillingAngle: drillingAngle, pinToPAP: pinToPAP, valAngle: valAngle)
        case .vls:
            return Notation.vlsShorthand(pinToPAP: pinToPAP, cgToPAP: cgToPAP, pinBuffer: pinBuffer, mbDistance: mbPsaDistance)
        }
    }

    var hasDrillingSpecs: Bool {
        middleSpan != nil || ringSpan != nil || bridgeWidth != nil
            || middleHoleSize != nil || ringHoleSize != nil
            || middlePitch != nil || ringPitch != nil
            || thumbHoleSize != nil || thumbPitch != nil
    }
}

@Model
final class BallLayoutHistory {
    var id: UUID = UUID()
    var ball: Ball?
    var layout: Layout?
    var layoutNameSnapshot: String = ""
    var layoutSpecSnapshot: String = ""
    var becameActiveAt: Date = Date()
    var archivedAt: Date?
    var reasonRaw: String?
    var reasonNote: String?

    init() {}

    var reason: LayoutChangeReason? {
        get { reasonRaw.flatMap { LayoutChangeReason(rawValue: $0) } }
        set { reasonRaw = newValue?.rawValue }
    }
}

@Model
final class SurfaceLog {
    var id: UUID = UUID()
    var ball: Ball?
    var date: Date = Date()
    var gritRaw: String = SurfaceGrit.grit2000.rawValue
    var finishTypeRaw: String = FinishType.abralon.rawValue
    /// Auto-calculated from session history at log time (PRD 5.4.7).
    var gamesSincePriorPrep: Int = 0
    var notes: String = ""

    init() {}

    var grit: SurfaceGrit {
        get { SurfaceGrit(rawValue: gritRaw) ?? .grit2000 }
        set { gritRaw = newValue.rawValue }
    }

    var finishType: FinishType {
        get { FinishType(rawValue: finishTypeRaw) ?? .abralon }
        set { finishTypeRaw = newValue.rawValue }
    }

    var displayString: String {
        "\(grit.displayName) \(finishType.displayName)"
    }
}

// MARK: - Patterns & locations

@Model
final class Pattern {
    var id: UUID = UUID()
    var typeRaw: String = PatternType.houseShot.rawValue
    var name: String = ""
    var lengthFt: Int?
    var ratioRaw: String?
    var notes: String = ""
    var createdAt: Date = Date()
    /// Imported patterns default to House Shot and are flagged (PRD 13.2).
    var needsTypeReview: Bool = false

    init() {}

    var type: PatternType {
        get { PatternType(rawValue: typeRaw) ?? .houseShot }
        set { typeRaw = newValue.rawValue }
    }

    var ratio: OilRatio? {
        get { ratioRaw.flatMap { OilRatio(rawValue: $0) } }
        set { ratioRaw = newValue?.rawValue }
    }

    var summary: String {
        var parts: [String] = [type.displayName]
        if let length = lengthFt { parts.append("\(length) ft") }
        if let ratio { parts.append(ratio.shortName) }
        return parts.joined(separator: " · ")
    }
}

@Model
final class Location {
    var id: UUID = UUID()
    var name: String = ""
    var city: String?
    var state: String?

    init() {}
}

// MARK: - Bags (PRD 5.4.11)

@Model
final class Bag {
    var id: UUID = UUID()
    var typeRaw: String = BagType.league.rawValue
    var name: String = ""
    var leagueName: String?
    var eventName: String?
    var pattern: Pattern?
    /// Max-ball limit for tournament bags; nil = unlimited.
    var maxBalls: Int?
    var notes: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \BagVariation.bag)
    var variations: [BagVariation]? = []

    init() {}

    var type: BagType {
        get { BagType(rawValue: typeRaw) ?? .league }
        set { typeRaw = newValue.rawValue }
    }

    var sortedVariations: [BagVariation] {
        (variations ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    /// The default variation is the first one (PRD: default bag + named variations).
    var defaultVariation: BagVariation? {
        sortedVariations.first
    }
}

@Model
final class BagVariation {
    var id: UUID = UUID()
    var bag: Bag?
    var name: String = "Default"
    var orderIndex: Int = 0
    var slots: [BagSlot] = []

    init() {}

    var sortedSlots: [BagSlot] {
        slots.sorted { $0.order < $1.order }
    }
}
