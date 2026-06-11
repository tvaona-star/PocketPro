import Foundation
import SwiftData

/// ModelContainer factory. Tries CloudKit-backed storage first (when entitlements are
/// present), falls back to local-only so the project builds and runs with zero signing
/// setup (DECISIONS.md D4). Enable steps: docs/CLOUDKIT.md.
enum PersistenceController {

    static let schema = Schema([
        BowlerProfile.self,
        LeagueEvent.self,
        Session.self,
        Game.self,
        Frame.self,
        Ball.self,
        Layout.self,
        BallLayoutHistory.self,
        SurfaceLog.self,
        Pattern.self,
        Location.self,
        Bag.self,
        BagVariation.self,
    ])

    static func makeContainer(inMemory: Bool = false) -> ModelContainer {
        if inMemory {
            do {
                let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("Failed to create in-memory store: \(error)")
            }
        }

        // CloudKit first — succeeds only when the app is signed with iCloud entitlements.
        do {
            let cloudConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
            return try ModelContainer(for: schema, configurations: [cloudConfig])
        } catch {
            // Expected without entitlements — fall through to local-only.
        }

        do {
            let localConfig = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [localConfig])
        } catch {
            fatalError("Failed to create local store: \(error)")
        }
    }
}

/// Settings keys (used with @AppStorage throughout).
enum SettingsKeys {
    static let scoreEntryMode = "settings.scoreEntryMode"
    static let seasonDefinition = "settings.seasonDefinition"
    static let defaultBallWeight = "settings.defaultBallWeight"
    static let ballDetailDefaultExpanded = "settings.ballDetailDefaultExpanded"
    static let importReviewDismissed = "settings.importReviewDismissed"
}

/// Monetization scaffold (PRD §14, DECISIONS.md D6): one-time unlock, everything
/// free in development builds. StoreKit wiring lands when a product ID exists.
enum FeatureGate {
    /// Arsenal management, layout library, bag builder, advanced stats.
    static var proUnlocked: Bool { true }
}
