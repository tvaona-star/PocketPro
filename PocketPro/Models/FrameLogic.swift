import Foundation
import PocketProCore

// Bridges SwiftData models to PocketProCore value types.
// Leave derivation rules (PRD 5.5): every non-strike fresh-rack delivery with known
// pin identity produces a leave. The 10th frame can produce up to two leaves
// (e.g. open attempt on rack 1, then a fill-ball leave on rack 2).

extension Game {

    /// All leaves in this game, in delivery order. Frames without pin identity
    /// (direct-score entry, PinPal imports) contribute nothing.
    func derivedLeaves() -> [LeaveRecord] {
        var leaves: [LeaveRecord] = []
        for frame in sortedFrames {
            let balls = frame.balls
            guard !balls.isEmpty else { continue }
            let frameIndex = frame.number - 1

            if frameIndex < 9 {
                guard balls[0].count < 10, let mask = balls[0].standingAfterMask, mask != 0 else { continue }
                let converted = balls.count >= 2 && balls[0].count + balls[1].count == 10
                leaves.append(LeaveRecord(
                    frame: frameIndex,
                    pins: PinSet(mask: mask),
                    converted: converted,
                    hadOpportunity: balls.count >= 2,
                    overridePrimary: frame.leaveOverride
                ))
            } else {
                leaves.append(contentsOf: tenthFrameLeaves(frame: frame))
            }
        }
        return leaves
    }

    /// Rack-state walk of the 10th frame (mirrors ScoringEngine.freshDeliveries).
    private func tenthFrameLeaves(frame: Frame) -> [LeaveRecord] {
        let balls = frame.balls
        guard !balls.isEmpty else { return [] }
        var leaves: [LeaveRecord] = []
        var overrideRemaining = frame.leaveOverride

        func takeOverride() -> LeaveCategory? {
            let value = overrideRemaining
            overrideRemaining = nil
            return value
        }

        if balls[0].count < 10 {
            // Rack 1: open attempt with ball 2.
            if let mask = balls[0].standingAfterMask, mask != 0 {
                let converted = balls.count >= 2 && balls[0].count + balls[1].count == 10
                leaves.append(LeaveRecord(
                    frame: 9,
                    pins: PinSet(mask: mask),
                    converted: converted,
                    hadOpportunity: balls.count >= 2,
                    overridePrimary: takeOverride()
                ))
            }
            // Spare made → ball 3 is a fresh rack; its leave has no conversion chance.
            if balls.count >= 3, balls[0].count + balls[1].count == 10, balls[2].count < 10 {
                if let mask = balls[2].standingAfterMask, mask != 0 {
                    leaves.append(LeaveRecord(
                        frame: 9,
                        pins: PinSet(mask: mask),
                        converted: false,
                        hadOpportunity: false,
                        overridePrimary: takeOverride()
                    ))
                }
            }
        } else {
            // Strike on ball 1 → ball 2 is a fresh rack. If ball 2 is a non-strike that
            // leaves pins, ball 3 is thrown to clear them — a real spare attempt
            // (converted iff ball 2 + ball 3 = 10). Only two strikes (X X _, below) or a
            // spare then a fill ball (above) leave a bonus ball with no spare to make.
            if balls.count >= 2 {
                if balls[1].count < 10 {
                    if let mask = balls[1].standingAfterMask, mask != 0 {
                        let converted = balls.count >= 3 && balls[1].count + balls[2].count == 10
                        leaves.append(LeaveRecord(
                            frame: 9,
                            pins: PinSet(mask: mask),
                            converted: converted,
                            hadOpportunity: balls.count >= 3,
                            overridePrimary: takeOverride()
                        ))
                    }
                } else if balls.count >= 3, balls[2].count < 10 {
                    // Double → ball 3 fresh rack, no conversion chance.
                    if let mask = balls[2].standingAfterMask, mask != 0 {
                        leaves.append(LeaveRecord(
                            frame: 9,
                            pins: PinSet(mask: mask),
                            converted: false,
                            hadOpportunity: false,
                            overridePrimary: takeOverride()
                        ))
                    }
                }
            }
        }
        return leaves
    }

    /// Immutable stats snapshot for this game.
    func record() -> GameRecord {
        GameRecord(
            id: id,
            sessionID: session?.id ?? UUID(),
            date: session?.date ?? Date(),
            sessionType: session?.type ?? .practice,
            frames: hasFrameData ? frameCounts : [],
            finalScore: finalScore,
            leaves: hasFrameData ? derivedLeaves() : [],
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
