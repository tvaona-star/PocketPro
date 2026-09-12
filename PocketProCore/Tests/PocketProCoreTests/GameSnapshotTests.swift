import XCTest
@testable import PocketProCore

final class GameSnapshotTests: XCTestCase {

    private func shot(_ count: Int, standing: [Int]? = nil) -> ShotEntry {
        ShotEntry(count: count, standingAfterMask: standing.map { PinSet(pins: $0).mask })
    }

    func testPerfectGame() {
        let frames = [[ShotEntry]](repeating: [shot(10, standing: [])], count: 9)
            + [[shot(10, standing: []), shot(10, standing: []), shot(10, standing: [])]]
        let snap = GameSnapshot(frames: frames, hasFrameData: true, storedFinal: 0)
        XCTAssertEqual(snap.finalScore, 300)
        XCTAssertTrue(snap.isComplete)
        XCTAssertEqual(snap.maxPossible, 300)
        XCTAssertTrue(snap.leaves.isEmpty)
        XCTAssertNil(snap.currentFrameNumber)
        XCTAssertEqual(snap.cumulative.last ?? nil, 300)
    }

    func testPartialGameIsIncompleteWithPendingCumulative() {
        // A strike (bonus pending) then a spare (bonus pending).
        let frames = [[shot(10, standing: [])], [shot(9, standing: [10]), shot(1, standing: [])]]
        let snap = GameSnapshot(frames: frames, hasFrameData: true, storedFinal: 0)
        XCTAssertFalse(snap.isComplete)
        XCTAssertEqual(snap.currentFrameNumber, 3)
        XCTAssertEqual(snap.cumulative.count, 2)
        XCTAssertNil(snap.cumulative[1], "spare bonus still pending")
        XCTAssertEqual(snap.leaves.count, 1)
        XCTAssertTrue(snap.leaves[0].converted)
        XCTAssertGreaterThan(snap.maxPossible, 20)
    }

    func testCountOnlyImportUsesStoredScoreAndNoLeaves() {
        // Imported with a final score but no frame detail.
        let snap = GameSnapshot(frames: [], hasFrameData: false, storedFinal: 187)
        XCTAssertEqual(snap.finalScore, 187)
        XCTAssertTrue(snap.isComplete, "count-only games are always complete")
        XCTAssertTrue(snap.leaves.isEmpty)
    }

    func testUnfinishedFrameDataFallsBackToStoredFinal() {
        // Frame data present but the game is not finished: the engine has no final,
        // so the stored value is reported rather than a bogus total.
        let snap = GameSnapshot(frames: [[shot(7, standing: [2, 4, 8])]], hasFrameData: true, storedFinal: 0)
        XCTAssertEqual(snap.finalScore, 0)
        XCTAssertFalse(snap.isComplete)
    }

    func testSnapshotIsValueEquatable() {
        let frames = [[shot(9, standing: [10]), shot(1, standing: [])]]
        let a = GameSnapshot(frames: frames, hasFrameData: true, storedFinal: 0)
        let b = GameSnapshot(frames: frames, hasFrameData: true, storedFinal: 0)
        XCTAssertEqual(a, b, "identical shots must yield an equal snapshot, which drives view skipping")
    }
}
