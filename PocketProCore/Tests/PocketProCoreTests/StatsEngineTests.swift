import XCTest
@testable import PocketProCore

final class StatsEngineTests: XCTestCase {

    private func makeGame(
        session: UUID,
        daysAgo: Int,
        type: SessionType = .league,
        frames: [[Int]],
        finalScore: Int,
        leaves: [LeaveRecord] = []
    ) -> GameRecord {
        GameRecord(
            id: UUID(),
            sessionID: session,
            date: Date(timeIntervalSince1970: 1_700_000_000 - Double(daysAgo) * 86_400),
            sessionType: type,
            frames: frames,
            finalScore: finalScore,
            leaves: leaves
        )
    }

    func testDashboardSingleMixedGame() {
        // V4 mixed game: 168, 5 strikes, 11 fresh, doubles 2/5, turkey present.
        let session = UUID()
        let frames: [[Int]] = [[10], [7, 3], [9, 0], [10], [0, 8], [8, 2], [0, 6], [10], [10], [10, 8, 2]]
        let leaves = [
            LeaveRecord(frame: 1, pins: PinSet(pins: [3]), converted: true, hadOpportunity: true),
            LeaveRecord(frame: 2, pins: PinSet(pins: [10]), converted: false, hadOpportunity: true),
            LeaveRecord(frame: 4, pins: PinSet(pins: [4, 5]), converted: false, hadOpportunity: true),
            LeaveRecord(frame: 5, pins: PinSet(pins: [2, 8]), converted: true, hadOpportunity: true),
            LeaveRecord(frame: 6, pins: PinSet(pins: [7, 10]), converted: false, hadOpportunity: true),
            LeaveRecord(frame: 9, pins: PinSet(pins: [3, 9]), converted: true, hadOpportunity: true),
        ]
        let game = makeGame(session: session, daysAgo: 0, frames: frames, finalScore: 168, leaves: leaves)
        let stats = StatsEngine.dashboard(games: [game])

        XCTAssertEqual(stats.gamesCount, 1)
        XCTAssertEqual(stats.average, 168)
        XCTAssertEqual(stats.strikePercent.map { round($0 * 10) / 10 }, round(5.0 / 11.0 * 1000) / 10)
        // Splits: 4-5 and 7-10 → 2 of 11 fresh racks.
        XCTAssertEqual(stats.splitPercent.map { round($0 * 10) / 10 }, round(2.0 / 11.0 * 1000) / 10)
        // Spare % counts every leave with a shot, splits included: 3 converted of 6.
        XCTAssertEqual(stats.sparePercent, 50.0)
        XCTAssertEqual(stats.openFramePercent, 30.0)
        XCTAssertEqual(stats.cleanGamePercent, 0.0)
        XCTAssertEqual(stats.doublesPercent, 40.0)
        XCTAssertEqual(stats.turkeyPlusPercent, 100.0)
        XCTAssertEqual(stats.maxStreakInGame, 3)
        XCTAssertEqual(stats.streakHistory.count, 1)
        XCTAssertEqual(stats.streakHistory.first?.length, 3)
        XCTAssertEqual(stats.firstBallAverage.map { round($0 * 100) / 100 }, round(82.0 / 11.0 * 100) / 100)
    }

    func testCleanGameAndAverages() {
        let s1 = UUID()
        let s2 = UUID()
        let clean = [[Int]](repeating: [9, 1], count: 9) + [[9, 1, 9]]      // 190, clean
        let perfect = [[Int]](repeating: [10], count: 9) + [[10, 10, 10]]   // 300, clean
        let opens = [[Int]](repeating: [9, 0], count: 10)                    // 90, 10 opens

        let games = [
            makeGame(session: s1, daysAgo: 2, frames: clean, finalScore: 190),
            makeGame(session: s1, daysAgo: 2, frames: opens, finalScore: 90),
            makeGame(session: s2, daysAgo: 1, frames: perfect, finalScore: 300),
        ]
        let stats = StatsEngine.dashboard(games: games)
        XCTAssertEqual(stats.gamesCount, 3)
        XCTAssertEqual(stats.sessionsCount, 2)
        XCTAssertEqual(stats.cleanGamePercent.map { round($0) }, round(200.0 / 3.0))
        XCTAssertEqual(stats.average.map { round($0 * 10) / 10 }, round(580.0 / 3.0 * 10) / 10)

        let averages = StatsEngine.sessionAverages(games: games)
        XCTAssertEqual(averages.count, 2)
        XCTAssertEqual(averages.first?.average, 140.0)  // older session first
        XCTAssertEqual(averages.last?.average, 300.0)
    }

    func testCountOnlyImportedGamesExcludedFromFrameStats() {
        let session = UUID()
        let scoreOnly = GameRecord(
            id: UUID(),
            sessionID: session,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            sessionType: .league,
            frames: [],
            finalScore: 215,
            leaves: [],
            hasFrameData: false
        )
        let stats = StatsEngine.dashboard(games: [scoreOnly])
        XCTAssertEqual(stats.average, 215.0, "score-only games count toward average")
        XCTAssertNil(stats.strikePercent, "no frame data → no strike percent")
        XCTAssertNil(stats.openFramePercent)
    }

    func testTrendDelta() {
        var games: [GameRecord] = []
        // 10 sessions, one game each: averages 180,180,180,180,180 then 200,200,200,200,200.
        for i in 0..<10 {
            let score = i < 5 ? 180 : 200
            games.append(makeGame(
                session: UUID(),
                daysAgo: 10 - i,
                frames: [],
                finalScore: score
            ))
        }
        let trend = StatsEngine.trend(games: games)
        XCTAssertEqual(trend.recentSessionAverages, [200, 200, 200, 200, 200])
        XCTAssertEqual(trend.deltaVsPrior, 20.0)
    }

    func testSpareAggregations() {
        let session = UUID()
        let leaves = [
            LeaveRecord(frame: 0, pins: PinSet(pins: [10]), converted: true, hadOpportunity: true),
            LeaveRecord(frame: 1, pins: PinSet(pins: [10]), converted: false, hadOpportunity: true),
            LeaveRecord(frame: 2, pins: PinSet(pins: [10]), converted: true, hadOpportunity: true),
            LeaveRecord(frame: 3, pins: PinSet(pins: [7]), converted: false, hadOpportunity: true),
            LeaveRecord(frame: 4, pins: PinSet(pins: [7, 10]), converted: false, hadOpportunity: true),
            LeaveRecord(frame: 5, pins: PinSet(pins: [2, 4, 5, 8]), converted: true, hadOpportunity: true),
            // Fill-ball leave: counted as left, no conversion opportunity.
            LeaveRecord(frame: 9, pins: PinSet(pins: [10]), converted: false, hadOpportunity: false),
        ]
        let game = makeGame(session: session, daysAgo: 0, frames: [], finalScore: 0, leaves: leaves)

        let tenPin = StatsEngine.pinAggregate(games: [game], pins: PinSet(pins: [10]))
        XCTAssertEqual(tenPin.timesLeft, 4)
        XCTAssertEqual(tenPin.timesConverted, 2)
        XCTAssertEqual(tenPin.opportunities, 3)
        XCTAssertEqual(tenPin.conversionPercent.map { round($0 * 10) / 10 }, round(200.0 / 3.0 * 10) / 10)

        let corner = StatsEngine.categoryAggregate(games: [game], category: .cornerPin)
        XCTAssertEqual(corner.timesLeft, 5, "four 10-pins + one 7-pin")

        let bigSplit = StatsEngine.categoryAggregate(games: [game], category: .bigSplit)
        XCTAssertEqual(bigSplit.timesLeft, 1)

        let frequency = StatsEngine.leaveFrequency(games: [game])
        XCTAssertEqual(frequency.first?.pins, PinSet(pins: [10]), "most frequent leave first")
        XCTAssertEqual(frequency.first?.aggregate.timesLeft, 4)
        XCTAssertEqual(frequency.count, 4)

        let pinCounts = StatsEngine.pinLeaveCounts(games: [game])
        XCTAssertEqual(pinCounts[10], 5, "10 pin appears in 5 leaves")
        XCTAssertEqual(pinCounts[7], 2)
        XCTAssertEqual(pinCounts[5], 1)
    }

    func testManualOverride() {
        let leave = LeaveRecord(
            frame: 0,
            pins: PinSet(pins: [2, 5]),
            converted: true,
            hadOpportunity: true,
            overridePrimary: .sleeper
        )
        XCTAssertEqual(leave.primary, .sleeper, "manual override wins")
        XCTAssertTrue(leave.categories.contains(.sleeper))
        XCTAssertTrue(leave.categories.contains(.other), "original tags retained")
    }
}
