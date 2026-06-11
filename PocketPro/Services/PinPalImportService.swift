import Foundation
import Observation
import SwiftData
import PocketProCore

/// PinPal import orchestration (PRD §13): parse → preview → additive import with
/// duplicate detection, ball-name matching, and re-import hash safety.
@Observable
final class PinPalImportService {

    enum Phase: Equatable {
        case idle
        case previewing
        case importing
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var preview: PinPalImport.Preview?
    private(set) var issues: [PinPalImport.RowIssue] = []
    private(set) var progress: Double = 0
    private(set) var importedSessionCount = 0
    private(set) var skippedAsReimported = 0
    private(set) var duplicatesFlagged = 0
    private(set) var shellBallsCreated = 0

    private var parsedSessions: [PinPalImport.ImportedSession] = []

    func reset() {
        phase = .idle
        preview = nil
        issues = []
        progress = 0
        importedSessionCount = 0
        skippedAsReimported = 0
        duplicatesFlagged = 0
        shellBallsCreated = 0
        parsedSessions = []
    }

    // MARK: - Step 2: parse + preview

    func loadFile(at url: URL) {
        reset()
        do {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let csv = try String(contentsOf: url, encoding: .utf8)
            let result = try PinPalImport.parse(csv: csv)
            parsedSessions = result.sessions
            issues = result.issues
            preview = PinPalImport.preview(result.sessions)
            phase = .previewing
        } catch let error as PinPalImport.ImportError {
            phase = .failed(describe(error))
        } catch {
            phase = .failed("Could not read the file: \(error.localizedDescription)")
        }
    }

    private func describe(_ error: PinPalImport.ImportError) -> String {
        switch error {
        case .emptyFile: return "The file is empty."
        case .missingDateColumn: return "No Date column found — is this a PinPal export?"
        case .noSessions: return "No readable sessions found in the file."
        }
    }

    // MARK: - Step 3: import (additive — PRD 13.3/13.4)

    @MainActor
    func runImport(context: ModelContext) {
        guard phase == .previewing, !parsedSessions.isEmpty else { return }
        phase = .importing
        progress = 0

        let existingSessions = (try? context.fetch(FetchDescriptor<Session>())) ?? []
        var existingHashes = Set(existingSessions.compactMap { $0.importSourceHash })
        var existingBalls = (try? context.fetch(FetchDescriptor<Ball>())) ?? []
        var existingLocations = (try? context.fetch(FetchDescriptor<Location>())) ?? []
        var existingPatterns = (try? context.fetch(FetchDescriptor<Pattern>())) ?? []

        let total = parsedSessions.count
        var imported = 0

        for (index, source) in parsedSessions.enumerated() {
            defer { progress = Double(index + 1) / Double(total) }

            // Re-import safety: identical source rows are skipped, never duplicated —
            // including duplicate rows within the same file.
            if existingHashes.contains(source.sourceHash) {
                skippedAsReimported += 1
                continue
            }
            existingHashes.insert(source.sourceHash)

            let session = Session()
            session.type = .league                       // PRD 13.2: default, flagged for re-tag
            session.needsTypeReview = true
            session.importedFromPinPal = true
            session.importSourceHash = source.sourceHash
            session.date = source.date
            session.leagueName = source.leagueName
            session.notes = source.notes ?? ""

            // Location: reuse by case-insensitive name match, create otherwise.
            if let locationName = source.locationName {
                if let existing = existingLocations.first(where: { $0.name.caseInsensitiveCompare(locationName) == .orderedSame }) {
                    session.location = existing
                } else {
                    let location = Location()
                    location.name = locationName
                    context.insert(location)
                    existingLocations.append(location)
                    session.location = location
                }
            }

            // Pattern: free text → House Shot default, flagged for review (PRD 13.1).
            if let patternName = source.patternName {
                if let existing = existingPatterns.first(where: { $0.name.caseInsensitiveCompare(patternName) == .orderedSame }) {
                    session.pattern = existing
                } else {
                    let pattern = Pattern()
                    pattern.name = patternName
                    pattern.type = .houseShot
                    pattern.needsTypeReview = true
                    context.insert(pattern)
                    existingPatterns.append(pattern)
                    session.pattern = pattern
                }
            }

            // Ball: link by exact case-insensitive name, else create a shell record (PRD 13.4).
            var ballID: UUID?
            if let ballName = source.ballName {
                if let existing = existingBalls.first(where: {
                    $0.model.caseInsensitiveCompare(ballName) == .orderedSame
                        || $0.displayName.caseInsensitiveCompare(ballName) == .orderedSame
                }) {
                    ballID = existing.id
                } else {
                    let shell = Ball()
                    shell.model = ballName
                    shell.importedShell = true
                    context.insert(shell)
                    existingBalls.append(shell)
                    shellBallsCreated += 1
                    ballID = shell.id
                }
            }

            // Exact-duplicate detection: same date + location + scores (PRD 13.4).
            let sourceScores = source.games.map { $0.finalScore }.sorted()
            let isDuplicate = existingSessions.contains { existing in
                guard Calendar.current.isDate(existing.date, inSameDayAs: source.date) else { return false }
                let sameLocation = (existing.location?.name ?? "").caseInsensitiveCompare(source.locationName ?? "") == .orderedSame
                let existingScores = existing.sortedGames.map { $0.finalScore }.sorted()
                return sameLocation && existingScores == sourceScores
            }
            if isDuplicate {
                session.flaggedAsPotentialDuplicate = true
                duplicatesFlagged += 1
            }

            context.insert(session)

            for (gameIndex, sourceGame) in source.games.enumerated() {
                let game = Game()
                game.orderIndex = gameIndex
                game.session = session
                game.ballID = ballID
                game.finalScoreStored = sourceGame.finalScore

                if let frames = sourceGame.frames {
                    game.hasFrameData = true
                    for (frameIndex, counts) in frames.enumerated() {
                        let frame = Frame()
                        frame.number = frameIndex + 1
                        frame.game = game
                        // Carry pin identity (standing-pin masks) when the export
                        // provided it, so leaves/spares reconstruct; else counts only.
                        let frameMasks = sourceGame.frameMasks?[frameIndex]
                        frame.balls = counts.enumerated().map { ballIndex, count in
                            let mask = (frameMasks != nil && ballIndex < frameMasks!.count) ? frameMasks![ballIndex] : nil
                            return BallEntry(count: count, standingAfterMask: mask)
                        }
                        context.insert(frame)
                    }
                } else {
                    game.hasFrameData = false   // PRD 13.4: excluded from frame-derived stats
                }
                context.insert(game)
            }
            imported += 1
        }

        importedSessionCount = imported
        try? context.save()
        phase = .done
    }
}
