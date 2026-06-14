import Foundation

/// Ten-pin scoring engine. Mirrors the verified reference implementation in
/// tools/scoring/scoring_tests.ps1 — any behavior change must be made in both.
///
/// Game model: up to 10 frames; each frame is an array of ball pinfall counts.
///   Frames 1-9: [10] for a strike, otherwise [b1, b2] ([b1] while mid-entry).
///   Frame 10:   [b1, b2] open, [b1, b2, b3] after a strike or spare.
public enum ScoringEngine {

    public struct GameScore: Equatable, Sendable {
        /// Per-frame scores; nil while a frame's bonuses are undetermined.
        public let frameScores: [Int?]
        /// Cumulative totals; nil from the first undetermined frame onward.
        public let cumulative: [Int?]
        /// Final score; non-nil only when all 10 frames are resolved.
        public let final: Int?
    }

    public struct FreshDelivery: Equatable, Sendable {
        public let pinfall: Int
        /// 0-based frame index.
        public let frame: Int
        /// 0-based ball index within the frame.
        public let ball: Int

        public var isStrike: Bool { pinfall == 10 }
    }

    public struct GameSummary: Equatable, Sendable {
        /// Strike balls thrown (X count, including 10th-frame bonus strikes).
        public let strikes: Int
        /// Spare conversions (including a 10th-frame bonus spare).
        public let spares: Int
        /// Open frames.
        public let opens: Int
    }

    // MARK: - Scoring

    public static func score(frames: [[Int]]) -> GameScore {
        var frameScores = [Int?](repeating: nil, count: 10)
        let frameCount = min(10, frames.count)

        for f in 0..<frameCount {
            let balls = frames[f]
            if balls.isEmpty { continue }
            if f < 9 {
                if balls[0] == 10 {
                    let next = rollsAfter(frames: frames, frameIndex: f)
                    if next.count >= 2 {
                        frameScores[f] = 10 + next[0] + next[1]
                    }
                } else if balls.count >= 2 {
                    if balls[0] + balls[1] == 10 {
                        let next = rollsAfter(frames: frames, frameIndex: f)
                        if next.count >= 1 {
                            frameScores[f] = 10 + next[0]
                        }
                    } else {
                        frameScores[f] = balls[0] + balls[1]
                    }
                }
            } else {
                let needsThree = balls[0] == 10 || (balls.count >= 2 && balls[0] + balls[1] == 10)
                let complete = needsThree ? balls.count >= 3 : balls.count >= 2
                if complete {
                    frameScores[f] = balls.reduce(0, +)
                }
            }
        }

        var cumulative = [Int?](repeating: nil, count: 10)
        var running = 0
        for f in 0..<10 {
            guard let s = frameScores[f] else { break }
            running += s
            cumulative[f] = running
        }
        return GameScore(frameScores: frameScores, cumulative: cumulative, final: cumulative[9])
    }

    private static func rollsAfter(frames: [[Int]], frameIndex: Int) -> [Int] {
        var rolls: [Int] = []
        var i = frameIndex + 1
        while i < frames.count {
            rolls.append(contentsOf: frames[i])
            i += 1
        }
        return rolls
    }

    // MARK: - Fresh-rack deliveries (DECISIONS.md D11)

    /// Deliveries thrown at a full rack: ball 1 of frames 1-9; in the 10th, ball 1,
    /// ball 2 after a strike, and ball 3 after a double or after a ball-2 spare.
    public static func freshDeliveries(frames: [[Int]]) -> [FreshDelivery] {
        var out: [FreshDelivery] = []
        let frameCount = min(10, frames.count)
        for f in 0..<frameCount {
            let balls = frames[f]
            if balls.isEmpty { continue }
            if f < 9 {
                out.append(FreshDelivery(pinfall: balls[0], frame: f, ball: 0))
            } else {
                out.append(FreshDelivery(pinfall: balls[0], frame: f, ball: 0))
                if balls.count >= 2 && balls[0] == 10 {
                    out.append(FreshDelivery(pinfall: balls[1], frame: f, ball: 1))
                }
                if balls.count >= 3 {
                    let freshThird = (balls[0] == 10 && balls[1] == 10)
                        || (balls[0] != 10 && balls[0] + balls[1] == 10)
                    if freshThird {
                        out.append(FreshDelivery(pinfall: balls[2], frame: f, ball: 2))
                    }
                }
            }
        }
        return out
    }

    // MARK: - Summary

    public static func summary(frames: [[Int]]) -> GameSummary {
        var strikes = 0
        var spares = 0
        var opens = 0
        let frameCount = min(10, frames.count)

        for f in 0..<frameCount {
            let balls = frames[f]
            if balls.isEmpty { continue }
            if f < 9 {
                if balls[0] == 10 {
                    strikes += 1
                } else if balls.count >= 2 {
                    if balls[0] + balls[1] == 10 {
                        spares += 1
                    } else {
                        opens += 1
                    }
                }
            } else {
                if balls[0] == 10 {
                    strikes += 1
                    if balls.count >= 2 {
                        if balls[1] == 10 {
                            strikes += 1
                            if balls.count >= 3 && balls[2] == 10 {
                                strikes += 1
                            }
                        } else if balls.count >= 3 && balls[1] + balls[2] == 10 {
                            spares += 1
                        }
                    }
                } else if balls.count >= 2 {
                    if balls[0] + balls[1] == 10 {
                        spares += 1
                        if balls.count >= 3 && balls[2] == 10 {
                            strikes += 1
                        }
                    } else {
                        opens += 1
                    }
                }
            }
        }
        return GameSummary(strikes: strikes, spares: spares, opens: opens)
    }

    // MARK: - Streaks & doubles

    /// Lengths of consecutive fresh-rack strike runs within one game, in order of occurrence.
    public static func streaks(frames: [[Int]]) -> [Int] {
        var result: [Int] = []
        var current = 0
        for d in freshDeliveries(frames: frames) {
            if d.isStrike {
                current += 1
            } else {
                if current > 0 { result.append(current) }
                current = 0
            }
        }
        if current > 0 { result.append(current) }
        return result
    }

    /// Doubles conversion: among fresh-rack strikes with a following fresh delivery
    /// in the same game, how many were followed by another strike.
    public static func doubles(frames: [[Int]]) -> (made: Int, opportunities: Int) {
        let deliveries = freshDeliveries(frames: frames)
        var made = 0
        var opportunities = 0
        for i in 0..<deliveries.count {
            if deliveries[i].isStrike && i + 1 < deliveries.count {
                opportunities += 1
                if deliveries[i + 1].isStrike {
                    made += 1
                }
            }
        }
        return (made, opportunities)
    }

    /// Turkey conversion: after a double (two consecutive fresh-rack strikes) with a
    /// following fresh delivery, how often the third was also a strike.
    public static func turkeys(frames: [[Int]]) -> (made: Int, opportunities: Int) {
        let deliveries = freshDeliveries(frames: frames)
        var made = 0
        var opportunities = 0
        for i in 0..<deliveries.count where i + 2 < deliveries.count {
            if deliveries[i].isStrike && deliveries[i + 1].isStrike {
                opportunities += 1
                if deliveries[i + 2].isStrike {
                    made += 1
                }
            }
        }
        return (made, opportunities)
    }

    // MARK: - Entry-flow helpers

    /// True when no further balls can be thrown in the frame.
    public static func isFrameComplete(balls: [Int], frameIndex: Int) -> Bool {
        if frameIndex < 9 {
            if balls.first == 10 { return true }
            return balls.count >= 2
        }
        guard balls.count >= 2 else { return false }
        let earnsThird = balls[0] == 10 || balls[0] + balls[1] == 10
        return earnsThird ? balls.count >= 3 : true
    }

    /// True when every frame of the game is complete.
    public static func isGameComplete(frames: [[Int]]) -> Bool {
        guard frames.count >= 10 else { return false }
        for f in 0..<10 where !isFrameComplete(balls: frames[f], frameIndex: f) {
            return false
        }
        return true
    }

    /// Maximum legal pinfall for the next ball of a frame (for direct-entry validation).
    public static func maxPinsForNextBall(balls: [Int], frameIndex: Int) -> Int {
        if frameIndex < 9 {
            return balls.isEmpty ? 10 : 10 - balls[0]
        }
        switch balls.count {
        case 0:
            return 10
        case 1:
            return balls[0] == 10 ? 10 : 10 - balls[0]
        default:
            // Third ball: fresh rack after a double or a spare; otherwise remaining pins.
            if balls[0] == 10 {
                return balls[1] == 10 ? 10 : 10 - balls[1]
            }
            return 10
        }
    }

    /// Highest final score still achievable from the current (partial) game —
    /// every remaining ball assumed to knock the most pins legally available.
    public static func maxPossibleScore(frames: [[Int]]) -> Int {
        var best: [[Int]] = []
        for index in 0..<10 {
            var frame = index < frames.count ? frames[index] : []
            while !isFrameComplete(balls: frame, frameIndex: index) {
                frame.append(maxPinsForNextBall(balls: frame, frameIndex: index))
            }
            best.append(frame)
        }
        return score(frames: best).final ?? 0
    }
}
