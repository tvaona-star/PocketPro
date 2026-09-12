import Foundation
import Observation
import SwiftData
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

    /// Backfill `imageURLString` for balls added before photos existed, matched to the
    /// database by `dbBallID`. Idempotent — only touches balls missing an image.
    @discardableResult
    func backfillImages(context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Ball>(predicate: #Predicate { $0.imageURLString == nil })
        guard let arsenal = try? context.fetch(descriptor) else { return 0 }
        var filled = 0
        for ball in arsenal {
            // Prefer the direct DB link, but fall back to matching on name: balls added
            // by hand or brought in by the PinPal import have no dbBallID, so they
            // would otherwise never get a photo.
            var match: BallDBRecord?
            if let dbID = ball.dbBallID { match = record(id: dbID) }
            if match == nil { match = matchByName(brand: ball.brand.isEmpty ? ball.manufacturer : ball.brand, model: ball.model) }
            guard let found = match else { continue }
            // Link it while we're here, so specs and shared-core siblings resolve too.
            if ball.dbBallID == nil { ball.dbBallID = found.id }
            guard let url = found.imageURL else { continue }
            ball.imageURLString = url
            filled += 1
        }
        if filled > 0 { try? context.save() }
        return filled
    }

    /// Case/punctuation-insensitive name match. Requires a unique model hit so we never
    /// attach the wrong photo; brand narrows it when the model name is ambiguous.
    func matchByName(brand: String, model: String) -> BallDBRecord? {
        let wantedModel = Self.normalize(model)
        guard !wantedModel.isEmpty else { return nil }
        let byModel = balls.filter { Self.normalize($0.model) == wantedModel }
        if byModel.count == 1 { return byModel.first }
        guard byModel.count > 1 else { return nil }
        let wantedBrand = Self.normalize(brand)
        guard !wantedBrand.isEmpty else { return nil }
        let byBrand = byModel.filter {
            Self.normalize($0.brand) == wantedBrand || Self.normalize($0.manufacturer) == wantedBrand
        }
        return byBrand.count == 1 ? byBrand.first : nil
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    /// Runs the image backfill once per database version (re-runs after an OTA update
    /// that may add new photos). Cheap no-op once everything is filled.
    func backfillImagesIfNeeded(context: ModelContext) {
        guard version > 0 else { return }
        // Bumped when the matching LOGIC changes, so existing installs re-run even
        // though the database version is unchanged.
        let algorithm = 2
        let key = "imageBackfillVersion"
        let stamp = version * 100 + algorithm
        let done = UserDefaults.standard.integer(forKey: key)
        guard done < stamp else { return }
        _ = backfillImages(context: context)
        UserDefaults.standard.set(stamp, forKey: key)
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
