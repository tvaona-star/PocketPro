import SwiftUI
import SwiftData
import PocketProCore

// MARK: - Session stats sheet (PRD 5.3: the main dashboard for one session/group)

/// The same dashboard as the Stats tab — 8-card grid, spare breakdown, strike
/// clusters — scoped to a session, block, league (its weeks), or tournament (its
/// blocks). Opened from live scoring, a session detail, or a league/tournament.
struct SessionStatsSheet: View {
    let title: String
    let sessions: [Session]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                let records = sessions.flatMap { $0.gameRecords() }
                let stats = StatsEngine.dashboard(games: records)
                VStack(alignment: .leading, spacing: 14) {
                    if stats.gamesCount == 0 {
                        Text("No completed games yet.")
                            .font(Theme.cardSubtitle)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        DashboardStatGrid(stats: stats)

                        Text("Based on \(stats.gamesCount) game\(stats.gamesCount == 1 ? "" : "s") across \(stats.sessionsCount) session\(stats.sessionsCount == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)

                        SpareBreakdownPanel(games: records)
                        StrikeClustersPanel(stats: stats, sessions: sessions)
                    }
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
