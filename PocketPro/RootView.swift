import SwiftUI
import SwiftData

/// Five-tab navigation (PRD §4): Bowl, Sessions, Stats, Arsenal, Spares.
/// Settings lives behind the gear in each tab's toolbar.
struct RootView: View {
    var body: some View {
        TabView {
            BowlTabView()
                .tabItem { Label("Bowl", systemImage: "figure.bowling") }

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
