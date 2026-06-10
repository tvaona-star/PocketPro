import SwiftUI
import SwiftData
import PocketProCore

struct SettingsView: View {
    @Environment(BallDatabaseService.self) private var ballDB
    @AppStorage(SettingsKeys.scoreEntryMode) private var scoreEntryMode = ScoreEntryMode.pinDeck.rawValue
    @AppStorage(SettingsKeys.seasonDefinition) private var seasonDefinition = SeasonDefinition.usbc.rawValue
    @AppStorage(SettingsKeys.ballDetailDefaultExpanded) private var ballDetailExpanded = "manufacturer"

    var body: some View {
        Form {
            Section("Bowler") {
                NavigationLink("Bowler Profile") {
                    BowlerProfileView()
                }
            }

            Section {
                Picker("Score entry", selection: $scoreEntryMode) {
                    ForEach(ScoreEntryMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                Picker("Season", selection: $seasonDefinition) {
                    ForEach(SeasonDefinition.allCases) { season in
                        Text(season.displayName).tag(season.rawValue)
                    }
                }
                Picker("Ball detail sections", selection: $ballDetailExpanded) {
                    Text("Manufacturer specs expanded").tag("manufacturer")
                    Text("All expanded").tag("all")
                    Text("All collapsed").tag("none")
                }
            } header: {
                Text("Preferences")
            } footer: {
                Text("Season controls the 'This Season' stats range — USBC seasons run August through July.")
            }

            Section("Data") {
                NavigationLink("Import from PinPal") {
                    PinPalImportView()
                }
                NavigationLink("Import Review") {
                    ImportReviewView()
                }
            }

            Section {
                LabeledContent("Ball database", value: "v\(ballDB.version) · \(ballDB.balls.count) balls")
                LabeledContent("Database status", value: ballDB.balls.first?.dbStatus == "seed" ? "Seed data" : "Synced")
            } header: {
                Text("Ball Database")
            } footer: {
                Text("Specs are stored locally — no network needed at the lanes. Updates arrive over the air.")
            }

            Section {
                LabeledContent("Version", value: "1.0 (PRD v4.5)")
            } header: {
                Text("About")
            } footer: {
                Text("No subscription. No paywall surprises.")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
