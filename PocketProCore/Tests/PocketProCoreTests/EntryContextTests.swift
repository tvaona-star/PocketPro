import XCTest
@testable import PocketProCore

/// The rack walk that decides where the next ball goes. The 10th-frame cases are
/// the ones that break when the tenth is reasoned about casually.
final class EntryContextTests: XCTestCase {

    private func shot(_ count: Int, standing: [Int]? = nil) -> ShotEntry {
        ShotEntry(count: count, standingAfterMask: standing.map { PinSet(pins: $0).mask })
    }
    private func ctx(_ frames: [[ShotEntry]]) -> EntryContext {
        GameSnapshot(frames: frames, hasFrameData: true, storedFinal: 0).entryContext
    }
    private var nineStrikes: [[ShotEntry]] { Array(repeating: [shot(10, standing: [])], count: 9) }

    func testFreshGameStartsAtFrameOneBallOneFullRack() {
        XCTAssertEqual(ctx([]), EntryContext(frameIndex: 0, ballIndex: 0, rack: .full))
    }

    func testAfterStrikeAdvancesToNextFrame() {
        XCTAssertEqual(ctx([[shot(10, standing: [])]]), EntryContext(frameIndex: 1, ballIndex: 0, rack: .full))
    }

    func testAfterOpenFirstBallSecondBallFacesTheLeave() {
        let c = ctx([[shot(7, standing: [2, 4, 8])]])
        XCTAssertEqual(c.frameIndex, 0)
        XCTAssertEqual(c.ballIndex, 1)
        XCTAssertEqual(c.rack, PinSet(pins: [2, 4, 8]))
    }

    func testFirstBallWithoutPinIdentityHasNoRack() {
        let c = ctx([[shot(7)]])
        XCTAssertEqual(c.ballIndex, 1)
        XCTAssertNil(c.rack, "direct-score entry cannot show a pin deck")
    }

    func testTenth_afterStrike_ballTwoFacesFreshRack() {
        XCTAssertEqual(ctx(nineStrikes + [[shot(10, standing: [])]]),
                       EntryContext(frameIndex: 9, ballIndex: 1, rack: .full))
    }

    func testTenth_afterOpen_ballTwoFacesTheLeave() {
        let c = ctx(nineStrikes + [[shot(9, standing: [10])]])
        XCTAssertEqual(c.frameIndex, 9)
        XCTAssertEqual(c.ballIndex, 1)
        XCTAssertEqual(c.rack, PinSet(pins: [10]))
    }

    func testTenth_afterDouble_ballThreeFacesFreshRack() {
        XCTAssertEqual(ctx(nineStrikes + [[shot(10, standing: []), shot(10, standing: [])]]),
                       EntryContext(frameIndex: 9, ballIndex: 2, rack: .full))
    }

    func testTenth_strikeThenOpen_ballThreeFacesBallTwoLeave() {
        let c = ctx(nineStrikes + [[shot(10, standing: []), shot(9, standing: [10])]])
        XCTAssertEqual(c.ballIndex, 2)
        XCTAssertEqual(c.rack, PinSet(pins: [10]))
    }

    func testTenth_afterSpare_fillBallFacesFreshRack() {
        XCTAssertEqual(ctx(nineStrikes + [[shot(9, standing: [10]), shot(1, standing: [])]]),
                       EntryContext(frameIndex: 9, ballIndex: 2, rack: .full))
    }

    func testTenth_open_gameIsOver() {
        // 9 then a miss: no third ball; context points past the last frame.
        let c = ctx(nineStrikes + [[shot(9, standing: [10]), shot(0, standing: [10])]])
        XCTAssertEqual(c.frameIndex, 10)
    }

    func testCompleteGamePointsPastLastFrame() {
        let c = ctx(nineStrikes + [[shot(10, standing: []), shot(10, standing: []), shot(10, standing: [])]])
        XCTAssertEqual(c.frameIndex, 10)
        XCTAssertEqual(c.ballIndex, 0)
    }

    func testSplitFrameNumbersUseFirstBallOnly() {
        // Frame 1: 7-10 split on ball 1. Frame 2: strike then a split on ball 2 is NOT
        // a first-ball split (no scoresheet circle).
        let frames: [[ShotEntry]] = [
            [shot(8, standing: [7, 10]), shot(1, standing: [10])],
            [shot(10, standing: [])],
        ]
        let snap = GameSnapshot(frames: frames, hasFrameData: true, storedFinal: 0)
        XCTAssertEqual(snap.splitFrameNumbers, [1])
    }
}
