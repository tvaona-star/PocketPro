import Foundation
import PocketProCore

// Bridges SwiftData models to PocketProCore value types. All scoring and leave
// rules live in the core package (tested); this file only maps model objects to
// the value types those rules take.

extension Game {

    /// The entered frames in order, as the core package sees them.
    var shotFrames: [[ShotEntry]] {
        sortedFrames.map { frame in
            frame.balls.map { ShotEntry(count: $0.count, standingAfterMask: $0.standingAfterMask) }
        }
    }

    /// Manual leave-category overrides (PRD 5.5.3), keyed by 0-based frame index.
    var leaveOverrides: [Int: LeaveCategory] {
        var map: [Int: LeaveCategory] = [:]
        for frame in frames ?? [] {
            if let override = frame.leaveOverride { map[frame.number - 1] = override }
        }
        return map
    }

    /// All leaves in this game, in delivery order (rules: LeaveDerivation).
    func derivedLeaves() -> [LeaveRecord] {
        LeaveDerivation.leaves(frames: shotFrames, overrides: leaveOverrides)
    }

    /// Everything derived from this game's shots, computed once. Views should hold
    /// one of these and rebuild it only when a shot changes — never re-derive in a
    /// body (reading `Frame.balls` decodes a stored blob every time).
    func snapshot() -> GameSnapshot {
        GameSnapshot(frames: shotFrames,
                     hasFrameData: hasFrameData,
                     storedFinal: finalScoreStored,
                     overrides: leaveOverrides)
    }

    /// Immutable stats snapshot for this game.
    func record() -> GameRecord {
        let snap = snapshot()
        return GameRecord(
            id: id,
            sessionID: session?.id ?? UUID(),
            date: session?.date ?? Date(),
            sessionType: session?.type ?? .practice,
            frames: hasFrameData ? snap.frameCounts : [],
            finalScore: snap.finalScore,
            leaves: snap.leaves,
            hasFrameData: hasFrameData,
            ballIDs: ballIDsUsed,
            patternID: session?.pattern?.id
        )
    }
}

extension Session {

    /// Stats snapshots for all complete games in the session.
    func gameRecords() -> [GameRecord] {
        sortedGames.filter { $0.isComplete }.map { $0.record() }
    }

    /// End-of-session quick strip: total strikes / spares / opens across games.
    var quickStats: (strikes: Int, spares: Int, opens: Int) {
        var strikes = 0
        var spares = 0
        var opens = 0
        for game in sortedGames where game.hasFrameData {
            let summary = ScoringEngine.summary(frames: game.frameCounts)
            strikes += summary.strikes
            spares += summary.spares
            opens += summary.opens
        }
        return (strikes, spares, opens)
    }

    /// Split count across the session (for the session card stat strip).
    var splitCount: Int {
        sortedGames.flatMap { $0.derivedLeaves() }.filter { $0.categories.contains(.split) }.count
    }
}
