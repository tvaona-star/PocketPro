import SwiftUI
import SwiftData
import PocketProCore

/// Stats tab (PRD 5.3): PBA-broadcast dashboard. All stats filter by session type,
/// date range, and optionally ball + pattern (condition compare).
struct StatsTabView: View {
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Query(filter: #Predicate<Ball> { $0.active }) private var arsenal: [Ball]
    @AppStorage(SettingsKeys.seasonDefinition) private var seasonRaw = SeasonDefinition.usbc.rawValue

    @State private var typeFilter: SessionType?
    @State private var dateRange: StatDateRange = .thisSeason
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo = Date()
    @State private var showingCustomRange = false
    @State private var ballFilter: UUID?
    @State private var patternFilter: UUID?

    /// Minimum games before stats display (PRD 7.4).
    private let statThreshold = 5

    private var season: SeasonDefinition {
        SeasonDefinition(rawValue: seasonRaw) ?? .usbc
    }

    private var rangeStart: Date? {
        let calendar = Calendar.current
        let now = Date()
        switch dateRange {
        case .thisWeek:
            return calendar.date(byAdding: .day, value: -7, to: now)
        case .thisMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .thisSeason:
            return season.seasonStart(now: now)
        case .allTime:
            return nil
        case .custom:
            return calendar.startOfDay(for: customFrom)
        }
    }

    private var rangeEnd: Date? {
        guard dateRange == .custom else { return nil }
        return Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: customTo))
    }

    private var games: [GameRecord] {
        allSessions
            .filter { session in
                if session.isActive { return false }
                if let typeFilter, session.type != typeFilter { return false }
                if let start = rangeStart, session.date < start { return false }
                if let end = rangeEnd, session.date > end { return false }
                return true
            }
            .flatMap { $0.gameRecords() }
            .filter { game in
                if let ballFilter, !game.ballIDs.contains(ballFilter) { return false }
                if let patternFilter, game.patternID != patternFilter { return false }
                return true
            }
    }

    private var patterns: [Pattern] {
        var byID: [UUID: Pattern] = [:]
        for session in allSessions {
            if let pattern = session.pattern { byID[pattern.id] = pattern }
        }
        return Array(byID.values).sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    filterBar

                    let stats = StatsEngine.dashboard(games: games)
                    let belowThreshold = stats.gamesCount < statThreshold

                    TrendStripView(games: games, allGamesForHotStat: allGamesUnfiltered)

                    if conditionActive {
                        conditionBanner
                    }

                    primaryGrid(stats: stats, masked: belowThreshold)

                    if belowThreshold {
                        Text("Bowl more sessions to populate your stats — \(stats.gamesCount) of \(statThreshold) games.")
                            .font(Theme.cardSubtitle)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        SpareBreakdownPanel(games: games)
                        StrikeClustersPanel(stats: stats, sessions: allSessions)
                        SessionAveragesTable(sessions: allSessions, rangeStart: rangeStart, rangeEnd: rangeEnd)
                    }
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Stats")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarLink()
                }
            }
            .sheet(isPresented: $showingCustomRange) {
                customRangeSheet
                    .presentationDetents([.medium])
            }
        }
    }

    private var allGamesUnfiltered: [GameRecord] {
        allSessions.filter { !$0.isActive }.flatMap { $0.gameRecords() }
    }

    private var conditionActive: Bool {
        ballFilter != nil || patternFilter != nil
    }

    // MARK: - Filters

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("Type", selection: $typeFilter) {
                Text("All").tag(SessionType?.none)
                ForEach(SessionType.allCases) { type in
                    Text(type.displayName).tag(SessionType?.some(type))
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Menu {
                    ForEach(StatDateRange.allCases) { range in
                        Button(range.displayName) {
                            if range == .custom {
                                showingCustomRange = true
                            }
                            dateRange = range
                        }
                    }
                } label: {
                    filterPill(icon: "calendar", label: dateRange.displayName, active: dateRange != .allTime)
                }

                Menu {
                    Button("Any ball") { ballFilter = nil }
                    ForEach(arsenal) { ball in
                        Button(ball.displayName) { ballFilter = ball.id }
                    }
                } label: {
                    filterPill(
                        icon: "circle.grid.3x3",
                        label: ballFilter.flatMap { id in arsenal.first { $0.id == id }?.displayName } ?? "Ball",
                        active: ballFilter != nil
                    )
                }

                Menu {
                    Button("Any pattern") { patternFilter = nil }
                    ForEach(patterns) { pattern in
                        Button(pattern.name.isEmpty ? pattern.summary : pattern.name) {
                            patternFilter = pattern.id
                        }
                    }
                } label: {
                    filterPill(
                        icon: "drop",
                        label: patternFilter != nil ? "Pattern ✓" : "Pattern",
                        active: patternFilter != nil
                    )
                }
                Spacer()
            }
        }
    }

    private func filterPill(icon: String, label: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(active ? Color.white : Theme.textSecondary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(active ? Theme.accent : Theme.bgElevated)
        .clipShape(Capsule())
    }

    private var conditionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope")
                .foregroundStyle(Theme.accent)
            Text(conditionDescription)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Clear") {
                ballFilter = nil
                patternFilter = nil
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
        .card(padding: 10)
    }

    private var conditionDescription: String {
        var parts: [String] = []
        if let ballFilter, let ball = arsenal.first(where: { $0.id == ballFilter }) {
            parts.append(ball.displayName)
        }
        if let patternFilter, let pattern = patterns.first(where: { $0.id == patternFilter }) {
            parts.append(pattern.name.isEmpty ? pattern.summary : pattern.name)
        }
        return "Condition: " + parts.joined(separator: " on ")
    }

    private var customRangeSheet: some View {
        NavigationStack {
            Form {
                DatePicker("From", selection: $customFrom, displayedComponents: .date)
                DatePicker("To", selection: $customTo, displayedComponents: .date)
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showingCustomRange = false }
                }
            }
        }
    }

    // MARK: - Primary 2x3 grid (PRD 5.3)

    private func primaryGrid(stats: DashboardStats, masked: Bool) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

        func display(_ value: Double?, suffix: String = "%") -> String {
            guard !masked, let value else { return "--" }
            return suffix == "%" ? String(format: "%.1f%%", value) : Notation.oneDecimal(value)
        }

        return LazyVGrid(columns: columns, spacing: 10) {
            StatTile(label: "Strike %", value: display(stats.strikePercent))
            StatTile(label: "Spare %", value: display(stats.sparePercent))
            StatTile(label: "Split %", value: display(stats.splitPercent))
            StatTile(label: "Open Frame %", value: display(stats.openFramePercent))
            StatTile(label: "Clean Game %", value: display(stats.cleanGamePercent))
            StatTile(label: "Average", value: display(stats.average, suffix: ""))
        }
    }
}
