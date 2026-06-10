import Foundation
import SwiftData
import PocketProCore

/// Equipment-management operations shared by Arsenal views.
enum ArsenalActions {

    /// Snapshot a database record onto a Ball at the bowler's weight (PRD 5.4.2, 9.4).
    static func apply(record: BallDBRecord, to ball: Ball, weight: Int) {
        ball.dbBallID = record.id
        ball.brand = record.brand
        ball.model = record.model
        ball.year = record.year
        ball.manufacturer = record.manufacturer
        ball.coverstockTypeRaw = record.coverstockType.rawValue
        ball.coverstockName = record.coverstockName
        ball.coreName = record.coreName
        ball.asymmetric = record.asymmetric
        ball.factoryFinish = record.factoryFinish
        ball.sharedCoreID = record.sharedCoreID
        ball.weight = weight
        ball.importedShell = false

        if let (spec, isFallback) = record.spec(atWeight: weight) {
            ball.rg = spec.rg
            ball.diff = spec.diff
            ball.intDiff = spec.intDiff
            ball.specWeightUsed = isFallback ? 15 : weight
            ball.specIsFallback = isFallback
        } else {
            ball.rg = nil
            ball.diff = nil
            ball.intDiff = nil
            ball.specWeightUsed = nil
            ball.specIsFallback = false
        }
    }

    /// Assign a layout from the library, archiving the current one (PRD 5.4.6).
    static func assignLayout(
        _ layout: Layout,
        to ball: Ball,
        reason: LayoutChangeReason?,
        reasonNote: String?,
        context: ModelContext
    ) {
        let now = Date()
        if let current = ball.activeLayout {
            // Close the open history entry for the outgoing layout.
            if let open = (ball.layoutHistory ?? []).first(where: { $0.archivedAt == nil && $0.layout === current }) {
                open.archivedAt = now
                open.reasonRaw = reason?.rawValue
                open.reasonNote = reasonNote
            } else {
                let archived = BallLayoutHistory()
                archived.ball = ball
                archived.layout = current
                archived.layoutNameSnapshot = current.name
                archived.layoutSpecSnapshot = current.shorthand
                archived.becameActiveAt = now
                archived.archivedAt = now
                archived.reasonRaw = reason?.rawValue
                archived.reasonNote = reasonNote
                context.insert(archived)
            }
        }

        let entry = BallLayoutHistory()
        entry.ball = ball
        entry.layout = layout
        entry.layoutNameSnapshot = layout.name
        entry.layoutSpecSnapshot = layout.shorthand
        entry.becameActiveAt = now
        context.insert(entry)

        ball.activeLayout = layout
    }

    /// Layouts may only be deleted when not active on any ball (PRD 5.4.6).
    static func canDelete(layout: Layout, balls: [Ball]) -> Bool {
        !balls.contains { $0.activeLayout === layout }
    }

    /// Games thrown with this ball since its most recent surface prep (PRD 5.4.7).
    static func gamesSinceLastPrep(ball: Ball, sessions: [Session]) -> Int {
        let since = ball.latestSurfaceLog?.date ?? .distantPast
        return gamesUsingBall(ball, sessions: sessions, after: since)
    }

    /// Count of games where the ball was used (starting ball or mid-game swap).
    static func gamesUsingBall(_ ball: Ball, sessions: [Session], after cutoff: Date = .distantPast) -> Int {
        var count = 0
        for session in sessions where session.date > cutoff {
            for game in session.sortedGames where game.ballIDsUsed.contains(ball.id) {
                count += 1
            }
        }
        return count
    }

    /// Sessions where the ball was used: ball detail session history (PRD 5.4.4).
    static func sessions(using ball: Ball, in sessions: [Session]) -> [Session] {
        sessions
            .filter { session in
                session.sortedGames.contains { $0.ballIDsUsed.contains(ball.id) }
            }
            .sorted { $0.date > $1.date }
    }
}
