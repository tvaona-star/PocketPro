import Foundation

/// Where the next ball goes and what rack it faces (PRD 5.1 entry).
/// `rack` is nil when pin identity is unavailable (prior ball entered without pin data).
public struct EntryContext: Hashable, Sendable {
    /// 0-based frame index; equals the number of entered frames once the game is complete.
    public let frameIndex: Int
    public let ballIndex: Int
    public let rack: PinSet?

    public init(frameIndex: Int, ballIndex: Int, rack: PinSet?) {
        self.frameIndex = frameIndex
        self.ballIndex = ballIndex
        self.rack = rack
    }
}

/// Everything a screen needs to know about one game, computed once from its shots.
///
/// This exists because deriving these values inline in SwiftUI bodies — re-scoring
/// and re-decoding frame data on every render — was the recurring cause of sluggish
/// entry. Views should hold a snapshot and rebuild it only when shots change.
/// Being a plain value type, it is also cheap to compare for view-skipping.
public struct GameSnapshot: Hashable, Sendable {
    /// The entered frames, each with its balls (the input, kept for rack logic).
    public let shots: [[ShotEntry]]
    /// Pinfall per ball, per entered frame (the scoring engine's input).
    public let frameCounts: [[Int]]
    /// Running total after each of the 10 frames; nil from the first frame whose
    /// bonus is still pending.
    public let cumulative: [Int?]
    public let finalScore: Int
    public let isComplete: Bool
    public let maxPossible: Int
    public let leaves: [LeaveRecord]
    public let hasFrameData: Bool
    /// 1-based numbers of frames whose FIRST ball left a split — the scoresheet
    /// convention circles that first-ball count.
    public let splitFrameNumbers: Set<Int>

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
        self.shots = frames
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

        var splits = Set<Int>()
        for (index, balls) in frames.enumerated() {
            guard let first = balls.first, first.count < 10,
                  let mask = first.standingAfterMask, mask != 0,
                  LeaveClassifier.classify(PinSet(mask: mask)).categories.contains(.split) else { continue }
            splits.insert(index + 1)
        }
        self.splitFrameNumbers = splits
    }

    /// The 1-based number of the frame the next ball goes into, or nil when complete.
    public var currentFrameNumber: Int? {
        for (index, balls) in frameCounts.enumerated()
        where !ScoringEngine.isFrameComplete(balls: balls, frameIndex: index) {
            return index + 1
        }
        return frameCounts.count < 10 ? frameCounts.count + 1 : nil
    }

    /// Rack-state walk to the next ball (mirrors ScoringEngine.freshDeliveries).
    /// Lives here — not in the entry view — so the 10th-frame cases are tested.
    public var entryContext: EntryContext {
        for (index, balls) in shots.enumerated() {
            let counts = balls.map(\.count)
            guard !ScoringEngine.isFrameComplete(balls: counts, frameIndex: index) else { continue }
            if index < 9 {
                if balls.isEmpty { return EntryContext(frameIndex: index, ballIndex: 0, rack: .full) }
                return EntryContext(frameIndex: index, ballIndex: 1,
                                    rack: balls[0].standingAfterMask.map { PinSet(mask: $0) })
            }
            // Tenth frame.
            switch balls.count {
            case 0:
                return EntryContext(frameIndex: 9, ballIndex: 0, rack: .full)
            case 1:
                if balls[0].count == 10 { return EntryContext(frameIndex: 9, ballIndex: 1, rack: .full) }
                return EntryContext(frameIndex: 9, ballIndex: 1,
                                    rack: balls[0].standingAfterMask.map { PinSet(mask: $0) })
            default:
                if balls[0].count == 10 {
                    if balls[1].count == 10 { return EntryContext(frameIndex: 9, ballIndex: 2, rack: .full) }
                    return EntryContext(frameIndex: 9, ballIndex: 2,
                                        rack: balls[1].standingAfterMask.map { PinSet(mask: $0) })
                }
                // Spare made → fresh rack for the fill ball.
                return EntryContext(frameIndex: 9, ballIndex: 2, rack: .full)
            }
        }
        return EntryContext(frameIndex: shots.count, ballIndex: 0, rack: .full)
    }
}
