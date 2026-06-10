import XCTest
@testable import PocketProCore

/// Mirrors tools/scoring/scoring_tests.ps1 vectors V1–V10 exactly.
final class ScoringEngineTests: XCTestCase {

    // MARK: V1 perfect game

    func testPerfectGame() {
        let frames = [[Int]](repeating: [10], count: 9) + [[10, 10, 10]]
        let score = ScoringEngine.score(frames: frames)
        XCTAssertEqual(score.final, 300)
        XCTAssertEqual(score.frameScores.compactMap { $0 }, [Int](repeating: 30, count: 10))
        XCTAssertEqual(ScoringEngine.freshDeliveries(frames: frames).count, 12)
        XCTAssertEqual(ScoringEngine.summary(frames: frames).strikes, 12)
        XCTAssertEqual(ScoringEngine.streaks(frames: frames), [12])
    }

    // MARK: V2 all spares

    func testAllSpares() {
        let frames = [[Int]](repeating: [9, 1], count: 9) + [[9, 1, 9]]
        let score = ScoringEngine.score(frames: frames)
        XCTAssertEqual(score.final, 190)
        XCTAssertEqual(score.cumulative.compactMap { $0 }, [19, 38, 57, 76, 95, 114, 133, 152, 171, 190])
        let summary = ScoringEngine.summary(frames: frames)
        XCTAssertEqual(summary.spares, 10)
        XCTAssertEqual(summary.strikes, 0)
        XCTAssertEqual(summary.opens, 0)
    }

    // MARK: V3 gutters

    func testAllGutters() {
        let frames = [[Int]](repeating: [0, 0], count: 10)
        XCTAssertEqual(ScoringEngine.score(frames: frames).final, 0)
    }

    // MARK: V4 mixed game — 168

    func testMixedGame() {
        let frames: [[Int]] = [[10], [7, 3], [9, 0], [10], [0, 8], [8, 2], [0, 6], [10], [10], [10, 8, 2]]
        let score = ScoringEngine.score(frames: frames)
        XCTAssertEqual(score.final, 168)
        XCTAssertEqual(score.frameScores.compactMap { $0 }, [20, 19, 9, 18, 8, 10, 6, 30, 28, 20])

        let summary = ScoringEngine.summary(frames: frames)
        XCTAssertEqual(summary.strikes, 5)
        XCTAssertEqual(summary.spares, 3)
        XCTAssertEqual(summary.opens, 3)

        let fresh = ScoringEngine.freshDeliveries(frames: frames)
        XCTAssertEqual(fresh.count, 11)
        XCTAssertEqual(fresh.reduce(0) { $0 + $1.pinfall }, 82)

        let doubles = ScoringEngine.doubles(frames: frames)
        XCTAssertEqual(doubles.made, 2)
        XCTAssertEqual(doubles.opportunities, 5)

        XCTAssertEqual(ScoringEngine.streaks(frames: frames), [1, 1, 3])
    }

    // MARK: V5 tenth-frame spare + fill

    func testTenthSpareWithFill() {
        let frames = [[Int]](repeating: [9, 0], count: 9) + [[9, 1, 7]]
        XCTAssertEqual(ScoringEngine.score(frames: frames).final, 98)
        XCTAssertEqual(ScoringEngine.freshDeliveries(frames: frames).count, 11, "ball 3 after a spare is a fresh rack")
        let summary = ScoringEngine.summary(frames: frames)
        XCTAssertEqual(summary.spares, 1)
        XCTAssertEqual(summary.opens, 9)
    }

    // MARK: V6 tenth-frame turkey

    func testTenthTurkey() {
        let frames = [[Int]](repeating: [9, 0], count: 9) + [[10, 10, 10]]
        XCTAssertEqual(ScoringEngine.score(frames: frames).final, 111)
        XCTAssertEqual(ScoringEngine.streaks(frames: frames), [3])
        let summary = ScoringEngine.summary(frames: frames)
        XCTAssertEqual(summary.strikes, 3)
        XCTAssertEqual(summary.opens, 9)
    }

    // MARK: V7/V8 incomplete games (live entry)

    func testPartialGame() {
        let frames: [[Int]] = [[10], [7, 3], [8]]
        let score = ScoringEngine.score(frames: frames)
        XCTAssertEqual(score.frameScores[0], 20)
        XCTAssertEqual(score.frameScores[1], 18)
        XCTAssertNil(score.frameScores[2])
        XCTAssertNil(score.final)
    }

    func testLoneStrikeUnresolved() {
        let score = ScoringEngine.score(frames: [[10]])
        XCTAssertNil(score.frameScores[0])
        XCTAssertNil(score.final)
    }

    // MARK: V9 tenth double then 9

    func testTenthDouble() {
        let frames = [[Int]](repeating: [9, 0], count: 9) + [[10, 10, 9]]
        XCTAssertEqual(ScoringEngine.score(frames: frames).final, 110)
        XCTAssertEqual(ScoringEngine.freshDeliveries(frames: frames).count, 12)
        let doubles = ScoringEngine.doubles(frames: frames)
        XCTAssertEqual(doubles.made, 1)
        XCTAssertEqual(doubles.opportunities, 2)
    }

    // MARK: V10 spare-heavy game — 192

    func testSpareHeavyGame() {
        let frames: [[Int]] = [[9, 1], [9, 0], [10], [8, 2], [7, 2], [10], [10], [9, 1], [10], [10, 9, 1]]
        let score = ScoringEngine.score(frames: frames)
        XCTAssertEqual(score.final, 192)
        XCTAssertEqual(score.frameScores.compactMap { $0 }, [19, 9, 20, 17, 9, 29, 20, 20, 29, 20])
        let summary = ScoringEngine.summary(frames: frames)
        XCTAssertEqual(summary.spares, 4)
        XCTAssertEqual(summary.opens, 2)
        XCTAssertEqual(summary.strikes, 5)
    }

    // MARK: Entry helpers

    func testFrameCompletion() {
        XCTAssertTrue(ScoringEngine.isFrameComplete(balls: [10], frameIndex: 0))
        XCTAssertFalse(ScoringEngine.isFrameComplete(balls: [9], frameIndex: 0))
        XCTAssertTrue(ScoringEngine.isFrameComplete(balls: [9, 0], frameIndex: 0))
        XCTAssertFalse(ScoringEngine.isFrameComplete(balls: [10], frameIndex: 9))
        XCTAssertFalse(ScoringEngine.isFrameComplete(balls: [10, 10], frameIndex: 9))
        XCTAssertTrue(ScoringEngine.isFrameComplete(balls: [10, 10, 10], frameIndex: 9))
        XCTAssertFalse(ScoringEngine.isFrameComplete(balls: [9, 1], frameIndex: 9))
        XCTAssertTrue(ScoringEngine.isFrameComplete(balls: [9, 1, 7], frameIndex: 9))
        XCTAssertTrue(ScoringEngine.isFrameComplete(balls: [9, 0], frameIndex: 9))
    }

    func testMaxPinsValidation() {
        XCTAssertEqual(ScoringEngine.maxPinsForNextBall(balls: [], frameIndex: 0), 10)
        XCTAssertEqual(ScoringEngine.maxPinsForNextBall(balls: [7], frameIndex: 0), 3)
        XCTAssertEqual(ScoringEngine.maxPinsForNextBall(balls: [10], frameIndex: 9), 10)
        XCTAssertEqual(ScoringEngine.maxPinsForNextBall(balls: [7], frameIndex: 9), 3)
        XCTAssertEqual(ScoringEngine.maxPinsForNextBall(balls: [10, 7], frameIndex: 9), 3)
        XCTAssertEqual(ScoringEngine.maxPinsForNextBall(balls: [10, 10], frameIndex: 9), 10)
        XCTAssertEqual(ScoringEngine.maxPinsForNextBall(balls: [7, 3], frameIndex: 9), 10)
    }
}
