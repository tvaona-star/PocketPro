import XCTest
@testable import PocketProCore

final class LeaveGroupingTests: XCTestCase {

    private func leave(_ pins: [Int], made: Bool, opportunity: Bool = true, frame: Int = 0) -> LeaveRecord {
        LeaveRecord(frame: frame, pins: PinSet(pins: pins), converted: made, hadOpportunity: opportunity)
    }

    func testGroupsByPinsAndCountsConversion() {
        let groups = LeaveGrouping.group([
            leave([10], made: true), leave([10], made: false), leave([10], made: true),
            leave([7], made: false),
        ])
        XCTAssertEqual(groups.count, 2)
        let ten = groups.first { $0.pins == PinSet(pins: [10]) }!
        XCTAssertEqual(ten.total, 3)
        XCTAssertEqual(ten.attempts, 3)
        XCTAssertEqual(ten.made, 2)
        XCTAssertEqual(ten.percent.map { Int($0.rounded()) }, 67)
    }

    func testFillBallLeavesCountAsOccurrencesNotAttempts() {
        let groups = LeaveGrouping.group([
            leave([10], made: true),
            leave([10], made: false, opportunity: false),   // 10th-frame fill ball
        ])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].total, 2)
        XCTAssertEqual(groups[0].attempts, 1)
        XCTAssertEqual(groups[0].made, 1)
        XCTAssertEqual(groups[0].percent, 100)
    }

    func testPercentIsNilWithNoAttempts() {
        let groups = LeaveGrouping.group([leave([7], made: false, opportunity: false)])
        XCTAssertNil(groups[0].percent)
    }

    func testOrderIsMostFrequentThenFewestPins() {
        let groups = LeaveGrouping.group([
            leave([2, 4, 8], made: false), leave([2, 4, 8], made: true),   // 2 total, 3 pins
            leave([10], made: false), leave([10], made: false),           // 2 total, 1 pin
            leave([7, 10], made: false),                                   // 1 total
        ])
        XCTAssertEqual(groups.map { $0.pins }, [PinSet(pins: [10]), PinSet(pins: [2, 4, 8]), PinSet(pins: [7, 10])])
    }

    func testSplitFlagFollowsClassification() {
        let groups = LeaveGrouping.group([leave([7, 10], made: false), leave([10], made: true)])
        XCTAssertTrue(groups.first { $0.pins == PinSet(pins: [7, 10]) }!.isSplit)
        XCTAssertFalse(groups.first { $0.pins == PinSet(pins: [10]) }!.isSplit)
    }
}
