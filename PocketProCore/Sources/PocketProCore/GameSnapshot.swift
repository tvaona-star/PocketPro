import Foundation

/// Everything a screen needs to know about one game, computed once from its shots.
///
/// This exists because deriving these values inline in SwiftUI bodies — re-scoring
/// and re-decoding frame data on every render — was the recurring cause of sluggish
/// entry. Views should hold a snapshot and rebuild it only when shots change.
/// Being a plain value type, it is also cheap to compare for view-skipping.
public struct GameSnapshot: Hashable, Sendable {
    /// Pinfall per ball, per entered frame (the scoring engine's input).
    public let frameCounts: [[Int]]
    /// Running total after each frame; nil while a frame's bonus is still pending.
    public let cumulative: [Int?]
    public let finalScore: Int
    public let isComplete: Bool
    public let maxPossible: Int
    public let leaves: [LeaveRecord]
    public let hasFrameData: Bool

    /// - Parameters:
    ///   - frames: entered frames in order, each with its balls.
    ///   - hasFrameData: false for count-only imports (score comes from `storedFinal`).
    ///   - storedFinal: the persisted final score, used when frame data is absent or
    ///     the engine has no final yet.
    ///   - overrides: manual leave-category overrides by 0-based frame index.
    public init(frames: [[ShotEntry]],
                hasFrameData: Bool,
                storedFinal: Int,
                overrides: [Int: LeaveCategory] = [:]) {
        let counts = frames.map { $0.map(\.count) }
        let score = ScoringEngine.score(frames: counts)
        self.frameCounts = counts
        self.cumulative = score.cumulative
        self.hasFrameData = hasFrameData
        if hasFrameData, let computed = score.final {
            self.finalScore = computed
        } else {
            self.finalScore = storedFinal
        }
        self.isComplete = hasFrameData ? ScoringEngine.isGameComplete(frames: counts) : true
        self.maxPossible = ScoringEngine.maxPossibleScore(frames: counts)
        self.leaves = hasFrameData ? LeaveDerivation.leaves(frames: frames, overrides: overrides) : []
    }

    /// The 1-based number of the frame the next ball goes into, or nil when complete.
    public var currentFrameNumber: Int? {
        for (index, balls) in frameCounts.enumerated()
        where !ScoringEngine.isFrameComplete(balls: balls, frameIndex: index) {
            return index + 1
        }
        return frameCounts.count < 10 ? frameCounts.count + 1 : nil
    }
}
