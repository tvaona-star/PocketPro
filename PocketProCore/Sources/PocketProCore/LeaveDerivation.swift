import Foundation

/// One delivered ball as the leave/scoring logic sees it: pinfall plus, when pin
/// identity was captured, the pins left standing afterwards.
public struct ShotEntry: Hashable, Sendable {
    public let count: Int
    public let standingAfterMask: Int?

    public init(count: Int, standingAfterMask: Int?) {
        self.count = count
        self.standingAfterMask = standingAfterMask
    }
}

/// Derives the leaves of a game from raw shot data (PRD 5.5).
///
/// Lives in the core package — not the app — so the spare-opportunity rules are
/// unit-tested and cannot silently regress. The rules, as settled by the bowler:
///
/// * Frames 1–9: a non-strike first ball that leaves pins is a spare opportunity.
///   The second ball is the attempt; it converted iff ball 1 + ball 2 = 10.
/// * 10th frame, non-strike first ball: same as above. If the spare is made, the
///   3rd (fill) ball faces a fresh rack — any leave there is recorded as an
///   occurrence but is NOT an opportunity (nothing can complete it).
/// * 10th frame, strike first ball: ball 2 faces a fresh rack. If ball 2 is a
///   non-strike that leaves pins, ball 3 IS a real attempt (strike, 9, open counts
///   as a missed spare). Only two strikes (X X _) leave a bonus ball with no spare
///   to make.
public enum LeaveDerivation {

    /// `frames` holds the entered frames in order (index 0 = frame 1). Frames with no
    /// balls, and balls without pin identity, contribute nothing.
    /// `overrides` maps a 0-based frame index to a manual category override; in the
    /// 10th frame it applies to that frame's first leave only.
    public static func leaves(frames: [[ShotEntry]],
                              overrides: [Int: LeaveCategory] = [:]) -> [LeaveRecord] {
        var leaves: [LeaveRecord] = []
        for (frameIndex, balls) in frames.enumerated() {
            guard !balls.isEmpty else { continue }
            if frameIndex < 9 {
                guard balls[0].count < 10,
                      let mask = balls[0].standingAfterMask, mask != 0 else { continue }
                let converted = balls.count >= 2 && balls[0].count + balls[1].count == 10
                leaves.append(LeaveRecord(
                    frame: frameIndex,
                    pins: PinSet(mask: mask),
                    converted: converted,
                    hadOpportunity: balls.count >= 2,
                    overridePrimary: overrides[frameIndex]
                ))
            } else {
                leaves.append(contentsOf: tenthFrameLeaves(balls, override: overrides[9]))
            }
        }
        return leaves
    }

    /// Rack-state walk of the 10th frame (mirrors ScoringEngine.freshDeliveries).
    private static func tenthFrameLeaves(_ balls: [ShotEntry],
                                         override: LeaveCategory?) -> [LeaveRecord] {
        var leaves: [LeaveRecord] = []
        var overrideRemaining = override
        func takeOverride() -> LeaveCategory? {
            defer { overrideRemaining = nil }
            return overrideRemaining
        }

        if balls[0].count < 10 {
            // Rack 1: open attempt with ball 2.
            if let mask = balls[0].standingAfterMask, mask != 0 {
                let converted = balls.count >= 2 && balls[0].count + balls[1].count == 10
                leaves.append(LeaveRecord(frame: 9, pins: PinSet(mask: mask),
                                          converted: converted,
                                          hadOpportunity: balls.count >= 2,
                                          overridePrimary: takeOverride()))
            }
            // Spare made → ball 3 is a fresh rack; its leave cannot be converted.
            if balls.count >= 3, balls[0].count + balls[1].count == 10, balls[2].count < 10,
               let mask = balls[2].standingAfterMask, mask != 0 {
                leaves.append(LeaveRecord(frame: 9, pins: PinSet(mask: mask),
                                          converted: false, hadOpportunity: false,
                                          overridePrimary: takeOverride()))
            }
        } else if balls.count >= 2 {
            if balls[1].count < 10 {
                // Strike then a non-strike: ball 3 is a genuine attempt at ball 2's leave.
                if let mask = balls[1].standingAfterMask, mask != 0 {
                    let converted = balls.count >= 3 && balls[1].count + balls[2].count == 10
                    leaves.append(LeaveRecord(frame: 9, pins: PinSet(mask: mask),
                                              converted: converted,
                                              hadOpportunity: balls.count >= 3,
                                              overridePrimary: takeOverride()))
                }
            } else if balls.count >= 3, balls[2].count < 10,
                      let mask = balls[2].standingAfterMask, mask != 0 {
                // Double → ball 3 faces a fresh rack with no spare to make.
                leaves.append(LeaveRecord(frame: 9, pins: PinSet(mask: mask),
                                          converted: false, hadOpportunity: false,
                                          overridePrimary: takeOverride()))
            }
        }
        return leaves
    }
}
