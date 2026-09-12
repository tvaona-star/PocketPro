import XCTest
@testable import PocketProCore

/// Spare-opportunity rules as settled by the bowler. The 10th-frame cases here
/// were each gotten wrong once before this suite existed. Do not change them
/// without re-reading the doc comment on LeaveDerivation.
final class LeaveDerivationTests: XCTestCase {

    // MARK: helpers

    private func mask(_ pins: [Int]) -> Int { PinSet(pins: pins).mask }
    private func shot(_ count: Int, standing: [Int]? = nil) -> ShotEntry {
        ShotEntry(count: count, standingAfterMask: standing.map(mask))
    }
    /// Nine open frames (7 count, leaves the 2-4-8) to reach the 10th.
    private var nineFrames: [[ShotEntry]] {
        Array(repeating: [shot(7, standing: [2, 4, 8]), shot(0, standing: [2, 4, 8])], count: 9)
    }
    private func tenthLeaves(_ tenth: [ShotEntry], overrides: [Int: LeaveCategory] = [:]) -> [LeaveRecord] {
        LeaveDerivation.leaves(frames: nineFrames + [tenth], overrides: overrides).filter { $0.frame == 9 }
    }

    // MARK: frames 1-9

    func testOpenFrameIsAMissedAttempt() {
        let leaves = LeaveDerivation.leaves(frames: [[shot(9, standing: [10]), shot(0, standing: [10])]])
        XCTAssertEqual(leaves.count, 1)
        XCTAssertEqual(leaves[0].pins, PinSet(pins: [10]))
        XCTAssertTrue(leaves[0].hadOpportunity)
        XCTAssertFalse(leaves[0].converted)
    }

    func testSpareIsAMadeAttempt() {
        let leaves = LeaveDerivation.leaves(frames: [[shot(9, standing: [10]), shot(1, standing: [])]])
        XCTAssertEqual(leaves.count, 1)
        XCTAssertTrue(leaves[0].hadOpportunity)
        XCTAssertTrue(leaves[0].converted)
    }

    func testStrikeProducesNoLeave() {
        XCTAssertTrue(LeaveDerivation.leaves(frames: [[shot(10, standing: [])]]).isEmpty)
    }

    func testFirstBallWithoutPinIdentityProducesNoLeave() {
        // Direct-score entry: count known, standing pins unknown.
        XCTAssertTrue(LeaveDerivation.leaves(frames: [[shot(9), shot(0)]]).isEmpty)
    }

    func testFirstBallPendingSecondIsNotYetAnAttempt() {
        let leaves = LeaveDerivation.leaves(frames: [[shot(9, standing: [10])]])
        XCTAssertEqual(leaves.count, 1)
        XCTAssertFalse(leaves[0].hadOpportunity, "no second ball thrown yet")
    }

    // MARK: 10th frame

    func testTenth_nonStrikeThenSpare_countsMade_fillBallDoesNot() {
        // 9 / 9: the spare is a made attempt; the fill-ball 7-pin leave is an
        // occurrence with no chance to convert.
        let leaves = tenthLeaves([shot(9, standing: [10]), shot(1, standing: []), shot(9, standing: [7])])
        XCTAssertEqual(leaves.count, 2)
        XCTAssertTrue(leaves[0].hadOpportunity)
        XCTAssertTrue(leaves[0].converted)
        XCTAssertFalse(leaves[1].hadOpportunity, "fill-ball leave must not count toward conversion")
        XCTAssertFalse(leaves[1].converted)
        XCTAssertEqual(leaves[1].pins, PinSet(pins: [7]))
    }

    func testTenth_nonStrikeOpen_countsMissed() {
        let leaves = tenthLeaves([shot(8, standing: [7, 10]), shot(1, standing: [10])])
        XCTAssertEqual(leaves.count, 1)
        XCTAssertTrue(leaves[0].hadOpportunity)
        XCTAssertFalse(leaves[0].converted)
    }

    func testTenth_strikeThenOpen_countsAsMissedSpare() {
        // "strike, 9, open": ball 3 is a real attempt, so this is an open and a
        // missed spare. This is the case that was once wrongly excluded.
        let leaves = tenthLeaves([shot(10, standing: []), shot(9, standing: [10]), shot(0, standing: [10])])
        XCTAssertEqual(leaves.count, 1)
        XCTAssertEqual(leaves[0].pins, PinSet(pins: [10]))
        XCTAssertTrue(leaves[0].hadOpportunity, "strike then open ball 2 IS a spare opportunity")
        XCTAssertFalse(leaves[0].converted)
    }

    func testTenth_strikeThenSpare_countsMade() {
        let leaves = tenthLeaves([shot(10, standing: []), shot(9, standing: [10]), shot(1, standing: [])])
        XCTAssertEqual(leaves.count, 1)
        XCTAssertTrue(leaves[0].hadOpportunity)
        XCTAssertTrue(leaves[0].converted)
    }

    func testTenth_strikeThenLeavePendingThirdBall_notYetAnAttempt() {
        let leaves = tenthLeaves([shot(10, standing: []), shot(9, standing: [10])])
        XCTAssertEqual(leaves.count, 1)
        XCTAssertFalse(leaves[0].hadOpportunity, "ball 3 not thrown yet")
    }

    func testTenth_doubleThenFill_isNotAnAttempt() {
        let leaves = tenthLeaves([shot(10, standing: []), shot(10, standing: []), shot(7, standing: [2, 4, 8])])
        XCTAssertEqual(leaves.count, 1)
        XCTAssertFalse(leaves[0].hadOpportunity, "after two strikes the 3rd ball has no spare to make")
        XCTAssertFalse(leaves[0].converted)
    }

    func testTenth_tripleStrike_noLeaves() {
        XCTAssertTrue(tenthLeaves([shot(10, standing: []), shot(10, standing: []), shot(10, standing: [])]).isEmpty)
    }

    // MARK: overrides

    func testOverrideAppliesToFirstTenthFrameLeaveOnly() {
        let leaves = tenthLeaves([shot(9, standing: [10]), shot(1, standing: []), shot(9, standing: [7])],
                                 overrides: [9: .split])
        XCTAssertEqual(leaves[0].overridePrimary, .split)
        XCTAssertNil(leaves[1].overridePrimary)
    }

    func testOverrideAppliesToRegularFrame() {
        let leaves = LeaveDerivation.leaves(frames: [[shot(9, standing: [10]), shot(0, standing: [10])]],
                                            overrides: [0: .split])
        XCTAssertEqual(leaves[0].overridePrimary, .split)
    }
}
