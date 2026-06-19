import SwiftUI
import SwiftData

/// Four-tab navigation (PRD §4): Sessions, Stats, Arsenal, Spares. Starting,
/// resuming, and scoring all live in Sessions. Settings lives behind the gear in
/// each tab's toolbar.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(BallDatabaseService.self) private var ballDB

    var body: some View {
        TabView {
            SessionsTabView()
                .tabItem { Label("Sessions", systemImage: "list.bullet.rectangle") }

            StatsTabView()
                .tabItem { Label("Stats", systemImage: "chart.bar.fill") }

            ArsenalTabView()
                .tabItem { Label("Arsenal", systemImage: "circle.grid.3x3.fill") }

            SparesTabView()
                .tabItem { Label("Spares", systemImage: "pin.fill") }
        }
        .background(Theme.bgPrimary)
        .task {
            ballDB.backfillImagesIfNeeded(context: context)
            backfillUntitledSessions()
        }
    }

    /// Self-heal any league/tournament session that lost its name (it would otherwise
    /// be skipped by the Sessions grouping and disappear). Idempotent.
    private func backfillUntitledSessions() {
        guard let sessions = try? context.fetch(FetchDescriptor<Session>()) else { return }
        var changed = false
        for session in sessions {
            switch session.type {
            case .league:
                if (session.leagueName ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    session.leagueName = "Untitled League"
                    changed = true
                }
            case .tournament:
                if (session.eventName ?? session.leagueName ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
                    session.eventName = "Untitled Tournament"
                    session.leagueName = "Untitled Tournament"
                    changed = true
                }
            case .practice:
                break
            }
        }
        if changed { try? context.save() }
    }
}

/// Reusable toolbar item that opens Settings from any tab.
struct SettingsToolbarLink: View {
    var body: some View {
        NavigationLink {
            SettingsView()
        } label: {
            Image(systemName: "gearshape")
        }
    }
}
