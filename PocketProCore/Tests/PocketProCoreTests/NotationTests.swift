import XCTest
@testable import PocketProCore

final class NotationTests: XCTestCase {

    func testInchFractions() {
        XCTAssertEqual(Notation.inches(4.75), "4 3/4\"")
        XCTAssertEqual(Notation.inches(4.0), "4\"")
        XCTAssertEqual(Notation.inches(0.5), "1/2\"")
        XCTAssertEqual(Notation.inches(0.3125), "5/16\"")
        XCTAssertEqual(Notation.inches(4.4375), "4 7/16\"")
        XCTAssertEqual(Notation.inches(4.5625), "4 9/16\"")
    }

    func testInchFractionSnapping() {
        // Values finer than the 1/16 grid snap to the nearest sixteenth.
        // (Hole sizes in 32nds/64ths are stored as free-text strings, not through this formatter.)
        XCTAssertEqual(Notation.inches(0.9375), "15/16\"")
        XCTAssertEqual(Notation.inches(0.96875), "1\"")
        XCTAssertEqual(Notation.inches(1.0), "1\"")
    }

    func testDegrees() {
        XCTAssertEqual(Notation.degrees(50), "50°")
        XCTAssertEqual(Notation.degrees(47.5), "47.5°")
    }

    func testLayoutShorthand() {
        XCTAssertEqual(
            Notation.dualAngleShorthand(drillingAngle: 50, pinToPAP: 4.75, valAngle: 40),
            "50° x 4 3/4\" x 40°"
        )
        XCTAssertEqual(
            Notation.vlsShorthand(pinToPAP: 4, cgToPAP: 3.75, pinBuffer: 2, mbDistance: nil),
            "4\" / 3 3/4\" / 2\""
        )
        XCTAssertEqual(
            Notation.vlsShorthand(pinToPAP: 4, cgToPAP: 3.75, pinBuffer: 2, mbDistance: 3.5),
            "4\" / 3 3/4\" / 2\" + MB 3 1/2\""
        )
    }

    func testPAP() {
        XCTAssertEqual(Notation.pap(over: 5.5, up: 0.375), "5 1/2\" over, 3/8\" up")
        XCTAssertEqual(Notation.pap(over: 5.5, up: -0.5), "5 1/2\" over, 1/2\" down")
        XCTAssertEqual(Notation.pap(over: 5.5, up: 0), "5 1/2\" over")
        XCTAssertEqual(Notation.pap(over: nil, up: nil), "Not set")
    }

    func testPercentAndDecimal() {
        XCTAssertEqual(Notation.percent(67.42), "67.4%")
        XCTAssertEqual(Notation.percent(nil), "--")
        XCTAssertEqual(Notation.oneDecimal(213.44), "213.4")
    }
}
