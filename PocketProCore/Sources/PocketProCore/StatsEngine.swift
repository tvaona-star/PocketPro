import Foundation

/// Session type (PRD §4). Raw values are the storage keys.
public enum SessionType: String, Codable, CaseIterable, Sendable, Identifiable {
    case league
    case tournament
    case practice

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .league: return "League"
        case .tournament: return "Tournament"
        case .practice: return "Practice"
        }
    }
}

/// Immutable snapshot of one leave, fed to the stats engine.
public struct LeaveRecord: Hashable, Sendable {
    /// 0-based frame index.
    public let frame: Int
    public let pins: PinSet
    public let converted: Bool
    /// False when the bowler never had a ball to convert it (e.g. a 10th-frame fill leave).
    public let hadOpportunity: Bool
    /// Manual category override (PRD 5.5.3), when the bowler re-tagged the leave.
    public let overridePrimary: LeaveCategory?

    public init(frame: Int, pins: PinSet, converted: Bool, hadOpportunity: Bool, overridePrimary: LeaveCategory? = nil) {
        self.frame = frame
        self.pins = pins
        self.converted = converted
        self.hadOpportunity = hadOpportunity
        self.overridePrimary = overridePrimary
    }

    public var classification: LeaveClassification {
        LeaveClassifier.classify(pins)
    }

    public var primary: LeaveCategory {
        overridePrimary ?? classification.primary
    }

    public var categories: [LeaveCategory] {
        var cats = classification.categories
        if let override = overridePrimary, !cats.contains(override) {
            cats.insert(override, at: 0)
        }
        return cats
    }
}

/// Immutable snapshot of one game, fed to the stats engine.
public struct GameRecord: Hashable, Sendable {
    public let id: UUID
    public let sessionID: UUID
    public let date: Date
    public let sessionType: SessionType
    /// Ball pinfall counts per frame; empty when only a final score was imported.
    public let frames: [[Int]]
    public let finalScore: Int
    /// Leaves with pin identity. Empty for count-only imported games.
    public let leaves: [LeaveRecord]
    /// False for imported games with no frame detail — excluded from frame-derived stats.
    public let hasFrameData: Bool
    public let ballIDs: [UUID]
    public let patternID: UUID?

    public init(
        id: UUID,
        sessionID: UUID,
        date: Date,
        sessionType: SessionType,
        frames: [[Int]],
        finalScore: Int,
        leaves: [LeaveRecord] = [],
        hasFrameData: Bool = true,
        ballIDs: [UUID] = [],
        patternID: UUID? = nil
    ) {
        self.id = id
        self.sessionID = sessionID
        self.date = date
        self.sessionType = sessionType
        self.frames = frames
        self.finalScore = finalScore
        self.leaves = leaves
        self.hasFrameData = hasFrameData
        self.ballIDs = ballIDs
        self.patternID = patternID
    }
}

/// One strike streak of 3+ for the streak history log (PRD 5.3).
public struct StreakEvent: Hashable, Sendable {
    public let sessionID: UUID
    public let gameID: UUID
    public let date: Date
    public let length: Int
}

/// The full PBA-style dashboard (PRD 5.3). Percentages are 0...100; nil when no data.
public struct DashboardStats: Equatable, Sendable {
    public let gamesCount: Int
    public let sessionsCount: Int
    public let strikePercent: Double?
    public let sparePercent: Double?
    public let splitPercent: Double?
    public let openFramePercent: Double?
    public let cleanGamePercent: Double?
    public let average: Double?
    public let doublesPercent: Double?
    public let turkeyPlusPercent: Double?
    public let maxStreakInGame: Int
    public let firstBallAverage: Double?
    public let streakHistory: [StreakEvent]
    /// Count of strike runs by length: 2 = doubles, 3 = turkeys, 4 = four-baggers, …
    public let streakCounts: [Int: Int]
}

/// One row of the spare breakdown panel (PRD 5.3) or leave-frequency list (PRD 5.5.4).
public struct LeaveAggregate: Equatable, Sendable {
    public let timesLeft: Int
    public let timesConverted: Int
    /// Conversion denominator — leaves where a conversion ball was actually thrown.
    public let opportunities: Int

    public var conversionPercent: Double? {
        guard opportunities > 0 else { return nil }
        return Double(timesConverted) / Double(opportunities) * 100
    }
}

public struct LeaveFrequencyEntry: Equatable, Sendable {
    public let pins: PinSet
    public let classification: LeaveClassification
    public let aggregate: LeaveAggregate
}

public enum StatsEngine {

    // MARK: - Dashboard

    public static func dashboard(games: [GameRecord]) -> DashboardStats {
        let framed = games.filter { $0.hasFrameData }
        var freshTotal = 0
        var freshStrikes = 0
        var freshPinfall = 0
        var splitLeaves = 0
        var spareAttempts = 0
        var spareMakes = 0
        var openFrames = 0
        var totalFrames = 0
        var cleanGames = 0
        var doublesMade = 0
        var doublesOpportunities = 0
        var gamesWithTurkey = 0
        var maxStreak = 0
        var streakHistory: [StreakEvent] = []
        var streakCounts: [Int: Int] = [:]

        for game in framed {
            let fresh = ScoringEngine.freshDeliveries(frames: game.frames)
            freshTotal += fresh.count
            freshStrikes += fresh.filter { $0.isStrike }.count
            freshPinfall += fresh.reduce(0) { $0 + $1.pinfall }

            let summary = ScoringEngine.summary(frames: game.frames)
            openFrames += summary.opens
            totalFrames += min(10, game.frames.count)
            if summary.opens == 0 && ScoringEngine.isGameComplete(frames: game.frames) {
                cleanGames += 1
            }

            let d = ScoringEngine.doubles(frames: game.frames)
            doublesMade += d.made
            doublesOpportunities += d.opportunities

            let gameStreaks = ScoringEngine.streaks(frames: game.frames)
            if let best = gameStreaks.max(), best > maxStreak {
                maxStreak = best
            }
            if gameStreaks.contains(where: { $0 >= 3 }) {
                gamesWithTurkey += 1
            }
            for s in gameStreaks where s >= 3 {
                streakHistory.append(StreakEvent(sessionID: game.sessionID, gameID: game.id, date: game.date, length: s))
            }
            // Tally every run by length (2+): doubles, turkeys, four-baggers, …
            for s in gameStreaks where s >= 2 {
                streakCounts[s, default: 0] += 1
            }

            for leave in game.leaves {
                let isSplit = leave.categories.contains(.split)
                if isSplit {
                    splitLeaves += 1
                } else if leave.hadOpportunity {
                    spareAttempts += 1
                    if leave.converted { spareMakes += 1 }
                }
            }
        }

        let sessionIDs = Set(games.map { $0.sessionID })

        func percent(_ num: Int, _ den: Int) -> Double? {
            den > 0 ? Double(num) / Double(den) * 100 : nil
        }

        return DashboardStats(
            gamesCount: games.count,
            sessionsCount: sessionIDs.count,
            strikePercent: percent(freshStrikes, freshTotal),
            sparePercent: percent(spareMakes, spareAttempts),
            splitPercent: percent(splitLeaves, freshTotal),
            openFramePercent: percent(openFrames, totalFrames),
            cleanGamePercent: percent(cleanGames, framed.count),
            average: games.isEmpty ? nil : Double(games.reduce(0) { $0 + $1.finalScore }) / Double(games.count),
            doublesPercent: percent(doublesMade, doublesOpportunities),
            turkeyPlusPercent: percent(gamesWithTurkey, framed.count),
            maxStreakInGame: maxStreak,
            firstBallAverage: freshTotal > 0 ? Double(freshPinfall) / Double(freshTotal) : nil,
            streakHistory: streakHistory.sorted { $0.date > $1.date },
            streakCounts: streakCounts
        )
    }

    // MARK: - Session averages

    public struct SessionAverage: Equatable, Sendable {
        public let sessionID: UUID
        public let date: Date
        public let average: Double
        public let gameCount: Int
    }

    /// Per-session averages sorted oldest → newest (trend strip input).
    public static func sessionAverages(games: [GameRecord]) -> [SessionAverage] {
        let grouped = Dictionary(grouping: games, by: { $0.sessionID })
        return grouped.map { sessionID, sessionGames in
            let total = sessionGames.reduce(0) { $0 + $1.finalScore }
            let earliest = sessionGames.map { $0.date }.min() ?? Date(timeIntervalSince1970: 0)
            return SessionAverage(
                sessionID: sessionID,
                date: earliest,
                average: Double(total) / Double(sessionGames.count),
                gameCount: sessionGames.count
            )
        }
        .sorted { $0.date < $1.date }
    }

    public struct Trend: Equatable, Sendable {
        /// Averages of the most recent (up to) 5 sessions, oldest → newest.
        public let recentSessionAverages: [Double]
        /// Mean of recent 5 minus mean of the prior 5; nil without a prior block.
        public let deltaVsPrior: Double?
    }

    public static func trend(games: [GameRecord]) -> Trend {
        let averages = sessionAverages(games: games)
        let recent = averages.suffix(5)
        let prior = averages.dropLast(recent.count).suffix(5)
        let recentValues = recent.map { $0.average }
        var delta: Double?
        if !prior.isEmpty && !recent.isEmpty {
            let recentMean = recentValues.reduce(0, +) / Double(recentValues.count)
            let priorValues = prior.map { $0.average }
            let priorMean = priorValues.reduce(0, +) / Double(priorValues.count)
            delta = recentMean - priorMean
        }
        return Trend(recentSessionAverages: recentValues, deltaVsPrior: delta)
    }

    // MARK: - Spare aggregations

    /// Aggregate across all leaves matching a predicate.
    public static func aggregate(games: [GameRecord], matching predicate: (LeaveRecord) -> Bool) -> LeaveAggregate {
        var left = 0
        var converted = 0
        var opportunities = 0
        for game in games {
            for leave in game.leaves where predicate(leave) {
                left += 1
                if leave.hadOpportunity {
                    opportunities += 1
                    if leave.converted { converted += 1 }
                }
            }
        }
        return LeaveAggregate(timesLeft: left, timesConverted: converted, opportunities: opportunities)
    }

    /// Aggregate for one category (uses full tag array, so 7-10 counts under Big Split too).
    public static func categoryAggregate(games: [GameRecord], category: LeaveCategory) -> LeaveAggregate {
        aggregate(games: games) { $0.categories.contains(category) }
    }

    /// Aggregate for one exact pin combination.
    public static func pinAggregate(games: [GameRecord], pins: PinSet) -> LeaveAggregate {
        aggregate(games: games) { $0.pins == pins }
    }

    /// Leave-frequency list: every distinct combination left, sorted most-frequent first (PRD 5.5.4).
    public static func leaveFrequency(games: [GameRecord]) -> [LeaveFrequencyEntry] {
        var byPins: [PinSet: (left: Int, converted: Int, opportunities: Int)] = [:]
        for game in games {
            for leave in game.leaves {
                var entry = byPins[leave.pins] ?? (0, 0, 0)
                entry.left += 1
                if leave.hadOpportunity {
                    entry.opportunities += 1
                    if leave.converted { entry.converted += 1 }
                }
                byPins[leave.pins] = entry
            }
        }
        return byPins.map { pins, counts in
            LeaveFrequencyEntry(
                pins: pins,
                classification: LeaveClassifier.classify(pins),
                aggregate: LeaveAggregate(timesLeft: counts.left, timesConverted: counts.converted, opportunities: counts.opportunities)
            )
        }
        .sorted {
            if $0.aggregate.timesLeft != $1.aggregate.timesLeft {
                return $0.aggregate.timesLeft > $1.aggregate.timesLeft
            }
            return $0.pins.mask < $1.pins.mask
        }
    }

    /// How often each pin position appears in any leave — heatmap input (PRD 5.5.4).
    /// Returns counts indexed 1...10 (index 0 unused).
    public static func pinLeaveCounts(games: [GameRecord]) -> [Int] {
        var counts = [Int](repeating: 0, count: 11)
        for game in games {
            for leave in game.leaves {
                for pin in leave.pins.pins {
                    counts[pin] += 1
                }
            }
        }
        return counts
    }
}
