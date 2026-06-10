import XCTest
@testable import PocketProCore

final class PinPalImportTests: XCTestCase {

    private let sampleCSV = """
    Date,Center,League,Oil Pattern,Ball,Notes,Game1,Game1Frames,Game2,Game2Frames
    2024-09-12,Maple Lanes,Tuesday Classic,House,Phaze II,"Felt strong, moved left",168,"10|7,3|9,0|10|0,8|8,2|0,6|10|10|10,8,2",190,"9,1|9,1|9,1|9,1|9,1|9,1|9,1|9,1|9,1|9,1,9"
    9/19/2024,Maple Lanes,Tuesday Classic,House,Phaze II,,215,,180,
    2024-09-26,Sunset Bowl,,Sport 41,IQ Tour,Short notes,300,"10|10|10|10|10|10|10|10|10|10,10,10",,
    """

    func testParse() throws {
        let result = try PinPalImport.parse(csv: sampleCSV)
        XCTAssertEqual(result.sessions.count, 3)
        XCTAssertTrue(result.issues.isEmpty, "issues: \(result.issues)")

        let first = result.sessions[0]
        XCTAssertEqual(first.locationName, "Maple Lanes")
        XCTAssertEqual(first.leagueName, "Tuesday Classic")
        XCTAssertEqual(first.patternName, "House")
        XCTAssertEqual(first.ballName, "Phaze II")
        XCTAssertEqual(first.notes, "Felt strong, moved left")
        XCTAssertEqual(first.games.count, 2)
        XCTAssertEqual(first.games[0].finalScore, 168)
        XCTAssertEqual(first.games[0].frames?.count, 10)
        XCTAssertEqual(first.games[1].finalScore, 190)

        let second = result.sessions[1]
        XCTAssertEqual(second.games.count, 2)
        XCTAssertNil(second.games[0].frames, "score-only games carry no frame data")

        let third = result.sessions[2]
        XCTAssertEqual(third.games.count, 1)
        XCTAssertEqual(third.games[0].finalScore, 300)
        XCTAssertNotNil(third.games[0].frames)
    }

    func testFrameScoreMismatchKeepsScoreOnly() throws {
        let csv = """
        Date,Game1,Game1Frames
        2024-01-05,200,"9,0|9,0|9,0|9,0|9,0|9,0|9,0|9,0|9,0|9,0"
        """
        let result = try PinPalImport.parse(csv: csv)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions[0].games[0].finalScore, 200)
        XCTAssertNil(result.sessions[0].games[0].frames, "mismatched frames must be dropped")
        XCTAssertEqual(result.issues.count, 1)
    }

    func testBadRowsSkippedWithIssues() throws {
        let csv = """
        Date,Game1
        not-a-date,200
        2024-02-01,abc
        2024-02-08,188
        """
        let result = try PinPalImport.parse(csv: csv)
        XCTAssertEqual(result.sessions.count, 1)
        XCTAssertEqual(result.sessions[0].games[0].finalScore, 188)
        XCTAssertEqual(result.issues.count, 2)
    }

    func testRehashStability() throws {
        let result1 = try PinPalImport.parse(csv: sampleCSV)
        let result2 = try PinPalImport.parse(csv: sampleCSV)
        XCTAssertEqual(
            result1.sessions.map { $0.sourceHash },
            result2.sessions.map { $0.sourceHash },
            "re-import must produce identical hashes (PRD 13.4 re-import safety)"
        )
        XCTAssertEqual(Set(result1.sessions.map { $0.sourceHash }).count, 3, "distinct rows hash distinctly")
    }

    func testPreview() throws {
        let result = try PinPalImport.parse(csv: sampleCSV)
        let preview = PinPalImport.preview(result.sessions)
        XCTAssertEqual(preview.sessionCount, 3)
        XCTAssertEqual(preview.gameCount, 5)
        XCTAssertEqual(preview.ballNames, ["IQ Tour", "Phaze II"])
        XCTAssertEqual(preview.patternNames, ["House", "Sport 41"])
        XCTAssertEqual(preview.locationNames, ["Maple Lanes", "Sunset Bowl"])
        XCTAssertEqual(preview.gamesWithoutFrameData, 2)
        XCTAssertNotNil(preview.dateRange)
    }

    func testEmptyFileThrows() {
        XCTAssertThrowsError(try PinPalImport.parse(csv: ""))
    }

    func testMissingDateColumnThrows() {
        XCTAssertThrowsError(try PinPalImport.parse(csv: "Foo,Bar\n1,2"))
    }
}
