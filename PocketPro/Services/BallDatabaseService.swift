import Foundation
import Observation
import PocketProCore

/// Read-only ball database (PRD §9): bundled seed file, replaceable over the air by
/// dropping a higher-version balldb.json into Application Support. Always local —
/// spec lookups never require network (PRD 9.5).
@Observable
final class BallDatabaseService {

    private(set) var database: BallDatabaseFile?
    private(set) var loadError: String?

    var balls: [BallDBRecord] {
        database?.balls ?? []
    }

    var version: Int {
        database?.version ?? 0
    }

    init() {
        load()
    }

    func load() {
        let decoder = JSONDecoder()
        var best: BallDatabaseFile?

        if let bundleURL = Bundle.main.url(forResource: "balldb", withExtension: "json"),
           let data = try? Data(contentsOf: bundleURL),
           let file = try? decoder.decode(BallDatabaseFile.self, from: data) {
            best = file
        }

        // OTA override: Application Support copy wins when its version is newer.
        if let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let otaURL = supportDir.appendingPathComponent("balldb.json")
            if let data = try? Data(contentsOf: otaURL),
               let file = try? decoder.decode(BallDatabaseFile.self, from: data),
               file.version > (best?.version ?? -1) {
                best = file
            }
        }

        if let best {
            database = best
            loadError = nil
        } else {
            loadError = "Ball database unavailable — manual entry still works."
        }
    }

    func search(_ query: String) -> [BallDBRecord] {
        database?.search(query) ?? []
    }

    func record(id: String) -> BallDBRecord? {
        balls.first { $0.id == id }
    }

    /// All brands present, sorted, for the brand filter.
    var brands: [String] {
        Array(Set(balls.map { $0.brand })).sorted()
    }

    /// Other balls sharing a core across Brunswick sub-brands (PRD 5.4.2).
    func sharedCoreSiblings(of record: BallDBRecord) -> [BallDBRecord] {
        guard let coreID = record.sharedCoreID else { return [] }
        return balls.filter { $0.sharedCoreID == coreID && $0.id != record.id }
    }
}
