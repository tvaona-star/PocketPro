import XCTest
@testable import PocketProCore

/// Mirrors tools/classifier/tests.ps1 — the PRD 5.5.2 decision log is authoritative.
final class ClassifierTests: XCTestCase {

    private func tags(_ pins: [Int]) -> Set<LeaveCategory> {
        Set(LeaveClassifier.classify(standingPins: pins).categories)
    }

    private func primary(_ pins: [Int]) -> LeaveCategory {
        LeaveClassifier.classify(standingPins: pins).primary
    }

    private func name(_ pins: [Int]) -> String? {
        LeaveClassifier.classify(standingPins: pins).name
    }

    // MARK: PRD 5.5.2 decision log

    func testDecisionLog() {
        XCTAssertEqual(tags([1, 5]), [.sleeper], "1-5 is a sleeper (washout exception)")
        XCTAssertEqual(tags([2, 5]), [.other])
        XCTAssertEqual(tags([3, 5]), [.other])
        XCTAssertEqual(tags([1, 2, 4]), [.washout])
        XCTAssertEqual(tags([1, 3, 6]), [.washout])
        XCTAssertEqual(tags([2, 4, 5, 8]), [.bucket])
        XCTAssertEqual(tags([3, 5, 6, 9]), [.bucket])
        XCTAssertEqual(tags([4, 5]), [.split])
        XCTAssertEqual(tags([5, 6]), [.split])
        XCTAssertEqual(tags([7, 10]), [.sevenTen, .bigSplit, .split])
        XCTAssertEqual(tags([4, 6, 7, 10]), [.bigFour, .bigSplit, .split])
        XCTAssertEqual(tags([2, 7]), [.babySplit, .split])
        XCTAssertEqual(tags([3, 10]), [.babySplit, .split])
    }

    // MARK: Taxonomy examples (PRD 5.5.1)

    func testSinglePins() {
        for pin in 1...10 {
            if pin == 7 || pin == 10 {
                XCTAssertEqual(tags([pin]), [.cornerPin, .singlePin])
                XCTAssertEqual(primary([pin]), .cornerPin)
            } else {
                XCTAssertEqual(tags([pin]), [.singlePin])
            }
        }
    }

    func testSleepers() {
        XCTAssertEqual(tags([2, 8]), [.sleeper])
        XCTAssertEqual(tags([3, 9]), [.sleeper])
    }

    func testClusters() {
        for cluster in [[2, 4, 5], [3, 5, 6], [2, 4, 7], [3, 6, 10], [4, 7, 8], [6, 9, 10]] {
            XCTAssertEqual(tags(cluster), [.cluster], "cluster \(cluster)")
        }
    }

    func testWashouts() {
        for washout in [[1, 2, 4, 10], [1, 3, 6, 7], [1, 2, 10], [1, 2], [1, 10]] {
            XCTAssertEqual(tags(washout), [.washout], "washout \(washout)")
        }
    }

    func testBigSplits() {
        for big in [[4, 6], [7, 9], [8, 10], [4, 6, 7, 9, 10], [5, 7], [5, 10], [4, 10], [6, 7]] {
            XCTAssertEqual(tags(big), [.bigSplit, .split], "big split \(big)")
        }
    }

    func testAheadPinSplits() {
        for split in [[2, 3], [7, 8], [8, 9], [9, 10], [4, 5, 6], [7, 8, 9]] {
            XCTAssertEqual(tags(split), [.split], "split \(split)")
        }
    }

    func testDocumentedDivergences() {
        // DECISIONS.md D8 — PRD example conflicts resolved against its own rules.
        XCTAssertEqual(tags([4, 7]), [.other])
        XCTAssertEqual(tags([6, 7, 10]), [.bigSplit, .split])
    }

    func testOtherPairs() {
        for pair in [[2, 4], [3, 6], [4, 8], [5, 8], [5, 9], [6, 9], [6, 10]] {
            XCTAssertEqual(tags(pair), [.other], "other \(pair)")
        }
    }

    // MARK: Names

    func testNames() {
        XCTAssertEqual(name([7, 10]), "7-10")
        XCTAssertEqual(name([4, 6, 7, 10]), "Big Four")
        XCTAssertEqual(name([2, 4, 5, 8]), "Bucket")
        XCTAssertEqual(name([3, 5, 6, 9]), "Bucket")
        XCTAssertEqual(name([2, 7]), "Baby Split")
        XCTAssertEqual(name([1, 5]), "Sleeper")
        XCTAssertEqual(name([5, 10]), "Woolworth")
        XCTAssertEqual(name([5, 7, 10]), "Sour Apple")
        XCTAssertEqual(name([4, 6, 7, 9, 10]), "Greek Church")
        XCTAssertEqual(name([1, 2, 4, 7]), "Picket Fence")
        XCTAssertEqual(name([10]), "10 Pin")
        XCTAssertNil(name([4, 6, 9]))
        XCTAssertEqual(LeaveClassifier.classify(standingPins: [4, 6, 9]).displayTitle, "4-6-9")
    }

    // MARK: Whole-table invariants (validated against the generator's counts)

    func testTableInvariants() {
        var tagCounts = [LeaveCategory: Int]()
        var primaryCounts = [LeaveCategory: Int]()

        for mask in 1...1023 {
            let classification = LeaveClassifier.classify(PinSet(mask: mask))
            XCTAssertFalse(classification.categories.isEmpty, "mask \(mask) must classify")
            XCTAssertEqual(classification.categories, classification.categories.sorted(), "mask \(mask) tags sorted by priority")
            for tag in classification.categories {
                tagCounts[tag, default: 0] += 1
            }
            primaryCounts[classification.primary, default: 0] += 1

            let tagSet = Set(classification.categories)
            if tagSet.contains(.bigSplit) {
                XCTAssertTrue(tagSet.contains(.split), "mask \(mask): big split implies split")
            }
            if tagSet.contains(.cornerPin) {
                XCTAssertTrue(tagSet.contains(.singlePin), "mask \(mask): corner implies single")
            }
            XCTAssertFalse(tagSet.contains(.bucket) && tagSet.contains(.cluster), "mask \(mask): bucket suppresses cluster")
            if tagSet.contains(.washout) {
                XCTAssertEqual(tagSet.count, 1, "mask \(mask): washout is exclusive")
            }
        }

        // Counts locked by tools/classifier/tests.ps1.
        XCTAssertEqual(tagCounts[.singlePin], 10)
        XCTAssertEqual(tagCounts[.cornerPin], 2)
        XCTAssertEqual(tagCounts[.washout], 510)
        XCTAssertEqual(tagCounts[.sleeper], 3)
        XCTAssertEqual(tagCounts[.babySplit], 2)
        XCTAssertEqual(tagCounts[.bucket], 2)
        XCTAssertEqual(tagCounts[.sevenTen], 1)
        XCTAssertEqual(tagCounts[.bigFour], 1)
        XCTAssertEqual(tagCounts[.bigSplit], 222)
        XCTAssertEqual(tagCounts[.split], 465)
        XCTAssertEqual(tagCounts[.cluster], 23)
        XCTAssertEqual(tagCounts[.other], 10)

        XCTAssertEqual(primaryCounts.values.reduce(0, +), 1023)
    }

    func testPinSetBasics() {
        var pins = PinSet.full
        XCTAssertEqual(pins.count, 10)
        pins.remove(1)
        pins.remove(5)
        XCTAssertEqual(pins.pins, [2, 3, 4, 6, 7, 8, 9, 10])
        pins.toggle(5)
        XCTAssertTrue(pins.contains(5))
        XCTAssertEqual(PinSet(pins: [3, 6, 10]).displayString, "3-6-10")
        XCTAssertEqual(PinSet(pins: [3, 6, 10]).mask, 0b1000100100)
    }
}
