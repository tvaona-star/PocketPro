import Foundation

/// PinPal CSV import (PRD §13). Column layout is documented in docs/PINPAL_FORMAT.md —
/// the real PinPal export schema is an open question in the PRD (D7), so the parser
/// uses tolerant header matching and this file is the only place mapping would change.
public enum PinPalImport {

    public struct ImportedGame: Hashable, Sendable {
        public let finalScore: Int
        /// Per-frame ball pinfall counts; nil when PinPal exported only a final score.
        public let frames: [[Int]]?
        /// Standing-pin mask after each ball, parallel to `frames` (PocketPro PinSet
        /// bits: bit `pin-1`). nil when only counts — or only the score — were available.
        /// Present means leave/spare history can be reconstructed for this game.
        public let frameMasks: [[Int]]?

        public init(finalScore: Int, frames: [[Int]]?, frameMasks: [[Int]]? = nil) {
            self.finalScore = finalScore
            self.frames = frames
            self.frameMasks = frameMasks
        }
    }

    public struct ImportedSession: Hashable, Sendable {
        public let date: Date
        public let locationName: String?
        public let leagueName: String?
        public let patternName: String?
        public let ballName: String?
        public let notes: String?
        public let games: [ImportedGame]
        /// Stable content hash of the source row — re-import safety (PRD 13.4).
        public let sourceHash: String
    }

    public struct Preview: Equatable, Sendable {
        public let sessionCount: Int
        public let gameCount: Int
        public let dateRange: ClosedRange<Date>?
        public let ballNames: [String]
        public let patternNames: [String]
        public let locationNames: [String]
        public let gamesWithoutFrameData: Int
    }

    public enum ImportError: Error, Equatable, Sendable {
        case emptyFile
        case missingDateColumn
        case noSessions
    }

    public struct RowIssue: Equatable, Sendable {
        public let row: Int
        public let message: String
    }

    public struct ParseResult: Sendable {
        public let sessions: [ImportedSession]
        public let issues: [RowIssue]
    }

    // MARK: - Parsing

    public static func parse(csv: String) throws -> ParseResult {
        let rows = tokenize(csv: csv)
        guard rows.count >= 1, !rows[0].isEmpty else { throw ImportError.emptyFile }

        let header = rows[0].map { normalizeHeader($0) }
        func column(_ candidates: [String]) -> Int? {
            for c in candidates {
                if let idx = header.firstIndex(of: c) { return idx }
            }
            return nil
        }

        guard let dateCol = column(["date"]) else { throw ImportError.missingDateColumn }
        let locationCol = column(["location", "center", "centerlocation", "bowlingcenter"])
        let leagueCol = column(["league", "leaguename"])
        let patternCol = column(["pattern", "oilpattern"])
        let ballCol = column(["ball", "ballname"])
        let notesCol = column(["notes", "note"])

        var gameCols: [(score: Int, frames: Int?)] = []
        // Up to 12 games/session — covers tournament blocks (PinPal exports can
        // group many games under one date) without truncating.
        for n in 1...12 {
            if let scoreIdx = column(["game\(n)", "g\(n)", "game\(n)score"]) {
                let framesIdx = column(["game\(n)frames", "g\(n)frames"])
                gameCols.append((scoreIdx, framesIdx))
            }
        }

        var sessions: [ImportedSession] = []
        var issues: [RowIssue] = []

        for rowIndex in 1..<rows.count {
            let row = rows[rowIndex]
            if row.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }

            func field(_ idx: Int?) -> String? {
                guard let idx, idx < row.count else { return nil }
                let value = row[idx].trimmingCharacters(in: .whitespaces)
                return value.isEmpty ? nil : value
            }

            guard let dateString = field(dateCol), let date = parseDate(dateString) else {
                issues.append(RowIssue(row: rowIndex + 1, message: "Unreadable date — row skipped"))
                continue
            }

            var games: [ImportedGame] = []
            for (scoreIdx, framesIdx) in gameCols {
                guard let scoreString = field(scoreIdx), let score = Int(scoreString) else { continue }
                guard (0...300).contains(score) else {
                    issues.append(RowIssue(row: rowIndex + 1, message: "Score \(score) out of range — game skipped"))
                    continue
                }
                var frames: [[Int]]?
                var frameMasks: [[Int]]?
                if let frameString = field(framesIdx) {
                    // Prefer the richer count:mask format (carries pin identity for
                    // leave/spare history); fall back to count-only frames.
                    if let (counts, masks) = parseFramesAndMasks(frameString) {
                        if ScoringEngine.score(frames: counts).final == score {
                            frames = counts
                            frameMasks = masks
                        } else {
                            issues.append(RowIssue(row: rowIndex + 1, message: "Frame data does not match score \(score) — kept score only"))
                        }
                    } else if let parsed = parseFrames(frameString) {
                        // Trust frame data only when it reproduces the exported score.
                        if ScoringEngine.score(frames: parsed).final == score {
                            frames = parsed
                        } else {
                            issues.append(RowIssue(row: rowIndex + 1, message: "Frame data does not match score \(score) — kept score only"))
                        }
                    } else {
                        issues.append(RowIssue(row: rowIndex + 1, message: "Unreadable frame data — kept score only"))
                    }
                }
                games.append(ImportedGame(finalScore: score, frames: frames, frameMasks: frameMasks))
            }

            if games.isEmpty {
                issues.append(RowIssue(row: rowIndex + 1, message: "No game scores — row skipped"))
                continue
            }

            let rawRow = row.joined(separator: "\u{1F}")
            sessions.append(ImportedSession(
                date: date,
                locationName: field(locationCol),
                leagueName: field(leagueCol),
                patternName: field(patternCol),
                ballName: field(ballCol),
                notes: field(notesCol),
                games: games,
                sourceHash: fnv1aHash(rawRow)
            ))
        }

        guard !sessions.isEmpty else { throw ImportError.noSessions }
        return ParseResult(sessions: sessions, issues: issues)
    }

    public static func preview(_ sessions: [ImportedSession]) -> Preview {
        let dates = sessions.map { $0.date }
        var range: ClosedRange<Date>?
        if let lo = dates.min(), let hi = dates.max() {
            range = lo...hi
        }
        let balls = Set(sessions.compactMap { $0.ballName }).sorted()
        let patterns = Set(sessions.compactMap { $0.patternName }).sorted()
        let locations = Set(sessions.compactMap { $0.locationName }).sorted()
        let allGames = sessions.flatMap { $0.games }
        return Preview(
            sessionCount: sessions.count,
            gameCount: allGames.count,
            dateRange: range,
            ballNames: balls,
            patternNames: patterns,
            locationNames: locations,
            gamesWithoutFrameData: allGames.filter { $0.frames == nil }.count
        )
    }

    // MARK: - Pieces

    /// Frame string format: frames separated by `|`, balls separated by `,`.
    /// Example: `10|9,1|7,2|10|0,8|8,2|0,6|10|10|10,8,2`
    static func parseFrames(_ raw: String) -> [[Int]]? {
        let frameParts = raw.split(separator: "|", omittingEmptySubsequences: false)
        guard frameParts.count == 10 else { return nil }
        var frames: [[Int]] = []
        for part in frameParts {
            let balls = part.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard !balls.isEmpty, balls.allSatisfy({ (0...10).contains($0) }) else { return nil }
            frames.append(balls)
        }
        guard ScoringEngine.isGameComplete(frames: frames) else { return nil }
        return frames
    }

    /// Richer frame string carrying pin identity: each ball is `count:mask`, where
    /// mask is the standing-pin bitset after the ball (PocketPro PinSet bits).
    /// Example: `8:6,2:0|10:0|9:512,1:0|...`. Returns the counts and the parallel
    /// masks, or nil if the string isn't in this format / isn't a complete game.
    static func parseFramesAndMasks(_ raw: String) -> (counts: [[Int]], masks: [[Int]])? {
        guard raw.contains(":") else { return nil }
        let frameParts = raw.split(separator: "|", omittingEmptySubsequences: false)
        guard frameParts.count == 10 else { return nil }
        var counts: [[Int]] = []
        var masks: [[Int]] = []
        for part in frameParts {
            let ballTokens = part.split(separator: ",")
            guard !ballTokens.isEmpty else { return nil }
            var frameCounts: [Int] = []
            var frameMasks: [Int] = []
            for token in ballTokens {
                let pair = token.split(separator: ":")
                guard pair.count == 2,
                      let c = Int(pair[0].trimmingCharacters(in: .whitespaces)),
                      let m = Int(pair[1].trimmingCharacters(in: .whitespaces)),
                      (0...10).contains(c), (0...0x3FF).contains(m) else { return nil }
                frameCounts.append(c)
                frameMasks.append(m)
            }
            counts.append(frameCounts)
            masks.append(frameMasks)
        }
        guard ScoringEngine.isGameComplete(frames: counts) else { return nil }
        return (counts, masks)
    }

    static func parseDate(_ raw: String) -> Date? {
        let formats = ["yyyy-MM-dd", "M/d/yyyy", "M/d/yy", "MM/dd/yyyy"]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) {
                return date
            }
        }
        return nil
    }

    static func normalizeHeader(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Minimal RFC-4180 CSV tokenizer: quoted fields, escaped quotes, CRLF/LF rows.
    static func tokenize(csv: String) -> [[String]] {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var currentField = ""
        var inQuotes = false
        var iterator = csv.makeIterator()
        var pending: Character?

        func nextChar() -> Character? {
            if let p = pending {
                pending = nil
                return p
            }
            return iterator.next()
        }

        while let ch = nextChar() {
            if inQuotes {
                if ch == "\"" {
                    if let peek = nextChar() {
                        if peek == "\"" {
                            currentField.append("\"")
                        } else {
                            inQuotes = false
                            pending = peek
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    currentField.append(ch)
                }
            } else {
                switch ch {
                case "\"":
                    inQuotes = true
                case ",":
                    currentRow.append(currentField)
                    currentField = ""
                case "\r":
                    break
                case "\n":
                    currentRow.append(currentField)
                    currentField = ""
                    rows.append(currentRow)
                    currentRow = []
                default:
                    currentField.append(ch)
                }
            }
        }
        if !currentField.isEmpty || !currentRow.isEmpty {
            currentRow.append(currentField)
            rows.append(currentRow)
        }
        return rows
    }

    /// FNV-1a 64-bit content hash — deterministic, dependency-free (used instead of
    /// CryptoKit so the hash is portable to the Android implementation).
    static func fnv1aHash(_ input: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in input.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
