import Foundation
import SQLite3
import PocketProCore

/// Reads a real PinPal ".pinpal" backup directly (PRD §13).
///
/// A .pinpal file is a small settings plist, zero-padded to offset 4096, followed
/// by an embedded SQLite database (tables: league / week / game / frame, plus
/// ball / house / pattern lookups). This reads that database with the system
/// SQLite library — no CSV step — and decodes each frame's packed standing-pin
/// bitmask into ball counts AND pin identity, so leaves/spares come across.
///
/// Frame encoding: ball 1 standing in the low 10 bits, ball 2 in the high 10 bits,
/// bit `pin-1` set = pin standing, 0 = strike, 0x3FFFFFFF = unplayed. Verified on a
/// real backup: every complete game re-scores to its stored PinPal score, and the
/// pin identities match a real bowler's leave profile.
enum PinPalBackup {

    enum Failure: Error { case notPinPal, openFailed, noData }

    private static let sentinel = 1_073_741_823   // 0x3FFFFFFF = unplayed frame

    /// True when the data carries an embedded SQLite database (i.e. is a .pinpal backup).
    static func looksLikePinPal(_ data: Data) -> Bool {
        sqliteOffset(in: data) != nil
    }

    static func parse(data: Data) throws -> [PinPalImport.ImportedSession] {
        guard let offset = sqliteOffset(in: data) else { throw Failure.notPinPal }

        // sqlite3 opens a path, and the DB doesn't start at byte 0, so extract it.
        let dbData = data.subdata(in: offset..<data.count)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinpal-\(UUID().uuidString).sqlite")
        try dbData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        var handle: OpaquePointer?
        guard sqlite3_open(tmp.path, &handle) == SQLITE_OK, let db = handle else {
            if handle != nil { sqlite3_close(handle) }
            throw Failure.openFailed
        }
        defer { sqlite3_close(db) }

        let balls = nameMap(db, table: "ball")
        let houses = nameMap(db, table: "house")
        let patterns = nameMap(db, table: "pattern")
        let leagues = nameMap(db, table: "league")

        // frameNum -> pins, grouped by gameFk.
        var framesByGame: [Int: [Int: Int]] = [:]
        forEachRow(db, "SELECT gameFk, frameNum, pins FROM frame;") { stmt in
            let g = Int(sqlite3_column_int64(stmt, 0))
            let fn = Int(sqlite3_column_int64(stmt, 1))
            let pins = Int(sqlite3_column_int64(stmt, 2))
            framesByGame[g, default: [:]][fn] = pins
        }

        // games grouped by week (in play order).
        var gamesByWeek: [Int: [(pk: Int, score: Int)]] = [:]
        forEachRow(db, "SELECT pk, weekFk, score FROM game WHERE score > 0 ORDER BY weekFk, pk;") { stmt in
            let pk = Int(sqlite3_column_int64(stmt, 0))
            let wk = Int(sqlite3_column_int64(stmt, 1))
            let score = Int(sqlite3_column_int64(stmt, 2))
            gamesByWeek[wk, default: []].append((pk, score))
        }

        // weeks = sessions, oldest first.
        var sessions: [PinPalImport.ImportedSession] = []
        forEachRow(db, "SELECT pk, date, leagueFk, houseFk, patternFk, ballFk, notes FROM week ORDER BY date;") { stmt in
            let pk = Int(sqlite3_column_int64(stmt, 0))
            guard let wkGames = gamesByWeek[pk], !wkGames.isEmpty else { return }
            let date = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let leagueFk = Int(sqlite3_column_int64(stmt, 2))
            let houseFk = Int(sqlite3_column_int64(stmt, 3))
            let patternFk = Int(sqlite3_column_int64(stmt, 4))
            let ballFk = Int(sqlite3_column_int64(stmt, 5))
            let notes = columnText(stmt, 6)

            var games: [PinPalImport.ImportedGame] = []
            for gr in wkGames {
                if let decoded = decodeFrames(framesByGame[gr.pk]),
                   ScoringEngine.score(frames: decoded.counts).final == gr.score {
                    games.append(PinPalImport.ImportedGame(finalScore: gr.score, frames: decoded.counts, frameMasks: decoded.masks))
                } else {
                    games.append(PinPalImport.ImportedGame(finalScore: gr.score, frames: nil, frameMasks: nil))
                }
            }

            let scores = wkGames.map { $0.score }
            let hash = fnv1a("\(pk)|\(date.timeIntervalSince1970)|\(scores)")
            sessions.append(PinPalImport.ImportedSession(
                date: date,
                locationName: houses[houseFk],
                leagueName: leagues[leagueFk],
                patternName: patterns[patternFk],
                ballName: balls[ballFk],
                notes: (notes?.isEmpty == false) ? notes : nil,
                games: games,
                sourceHash: hash
            ))
        }

        guard !sessions.isEmpty else { throw Failure.noData }
        return sessions
    }

    // MARK: - Frame decode (mirror of tools/pinpal/convert_pinpal.ps1, verified)

    private static func decodeFrames(_ rows: [Int: Int]?) -> (counts: [[Int]], masks: [[Int]])? {
        guard let r = rows else { return nil }
        func pc(_ m: Int) -> Int { (0..<10).reduce(0) { $0 + ((m >> $1) & 1) } }

        var counts: [[Int]] = []
        var masks: [[Int]] = []
        for f in 0...8 {
            guard let p = r[f], p != sentinel else { return nil }
            let low = p & 1023, high = (p >> 10) & 1023
            if low == 0 { counts.append([10]); masks.append([0]) }
            else { counts.append([10 - pc(low), pc(low) - pc(high)]); masks.append([low, high]) }
        }
        guard let p9 = r[9], p9 != sentinel else { return nil }
        let low9 = p9 & 1023, high9 = (p9 >> 10) & 1023
        var tCounts: [Int] = []
        var tMasks: [Int] = []
        let c1 = 10 - pc(low9); tCounts.append(c1); tMasks.append(low9)
        if low9 != 0 {
            let c2 = pc(low9) - pc(high9); tCounts.append(c2); tMasks.append(high9)
            if c1 + c2 == 10, let p10 = r[10], p10 != sentinel {
                let low10 = p10 & 1023; tCounts.append(10 - pc(low10)); tMasks.append(low10)
            }
        } else if let p10 = r[10], p10 != sentinel {
            let low10 = p10 & 1023, high10 = (p10 >> 10) & 1023
            tCounts.append(10 - pc(low10)); tMasks.append(low10)
            if low10 == 0 {
                if let p11 = r[11], p11 != sentinel {
                    let low11 = p11 & 1023; tCounts.append(10 - pc(low11)); tMasks.append(low11)
                } else { tCounts.append(10 - pc(high10)); tMasks.append(high10) }
            } else { tCounts.append(pc(low10) - pc(high10)); tMasks.append(high10) }
        }
        counts.append(tCounts); masks.append(tMasks)
        return (counts, masks)
    }

    // MARK: - SQLite + bytes helpers

    private static func sqliteOffset(in data: Data) -> Int? {
        let marker = Array("SQLite format 3".utf8)
        guard data.count > marker.count else { return nil }
        let limit = min(data.count - marker.count, 65_536)
        let bytes = [UInt8](data.prefix(limit + marker.count))
        var i = 0
        while i <= limit {
            var matched = true
            for j in 0..<marker.count where bytes[i + j] != marker[j] { matched = false; break }
            if matched { return i }
            i += 1
        }
        return nil
    }

    private static func nameMap(_ db: OpaquePointer, table: String) -> [Int: String] {
        var map: [Int: String] = [:]
        forEachRow(db, "SELECT pk, name FROM \(table);") { stmt in
            let pk = Int(sqlite3_column_int64(stmt, 0))
            if let name = columnText(stmt, 1)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                map[pk] = name
            }
        }
        return map
    }

    private static func columnText(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    private static func forEachRow(_ db: OpaquePointer, _ sql: String, _ body: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { body(stmt) }
    }

    private static func fnv1a(_ s: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in s.utf8 { hash ^= UInt64(byte); hash = hash &* 0x100_0000_01b3 }
        return String(format: "%016llx", hash)
    }
}
