import SwiftUI
import SwiftData
import PocketProCore

/// Stats tab (PRD 5.3): PBA-broadcast dashboard. All stats filter by session type,
/// date range, and optionally ball + pattern (condition compare).
struct StatsTabView: View {
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Query(filter: #Predicate<Ball> { $0.active }) private var arsenal: [Ball]
    @Query(sort: \LeagueEvent.createdAt, order: .reverse) private var leagueEvents: [LeagueEvent]
    @AppStorage(SettingsKeys.seasonDefinition) private var seasonRaw = SeasonDefinition.usbc.rawValue

    @State private var typeFilter: SessionType?
    /// Names of leagues/tournaments to scope stats to (empty = all). Multi-select,
    /// keyed by lowercased name so it also covers imported PinPal leagues.
    @State private var leagueFilter: Set<String> = []
    @State private var showingLeaguePicker = false
    @State private var dateRange: StatDateRange = .thisSeason
    @State private var customFrom = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customTo = Date()
    @State private var showingCustomRange = false
    /// Multi-select ball / pattern condition filters (empty = all).
    @State private var ballFilter: Set<UUID> = []
    @State private var patternFilter: Set<UUID> = []
    @State private var showingBallPicker = false
    @State private var showingPatternPicker = false
    @State private var showingCompare = false
    @State private var conditionFilter: PatternCondition = .all

    enum PatternCondition: String, CaseIterable, Identifiable {
        case all = "All"
        case house = "House"
        case sport = "Sport"
        var id: String { rawValue }
    }

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
        case .lastYear:
            return calendar.date(byAdding: .year, value: -1, to: now)
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

    /// League/tournament names flagged as sport-pattern (matched by name, like the
    /// averages table) — drives the House/Sport condition filter.
    private var sportNames: Set<String> {
        Set(leagueEvents.filter { $0.isSport }.map { $0.name.lowercased() })
    }

    private var games: [GameRecord] {
        let sport = sportNames
        return allSessions
            .filter { session in
                if session.isActive { return false }
                if let typeFilter, session.type != typeFilter { return false }
                if !leagueFilter.isEmpty {
                    let name = (session.leagueName ?? session.eventName ?? "").lowercased()
                    if !leagueFilter.contains(name) { return false }
                }
                if conditionFilter != .all {
                    let name = (session.leagueName ?? session.eventName ?? "").lowercased()
                    let isSport = sport.contains(name)
                    if (conditionFilter == .sport) != isSport { return false }
                }
                if let start = rangeStart, session.date < start { return false }
                if let end = rangeEnd, session.date > end { return false }
                return true
            }
            .flatMap { $0.gameRecords() }
            .filter { game in
                if !ballFilter.isEmpty && ballFilter.isDisjoint(with: Set(game.ballIDs)) { return false }
                if !patternFilter.isEmpty {
                    guard let id = game.patternID, patternFilter.contains(id) else { return false }
                }
                return true
            }
    }

    /// League/tournament names for the filter, sorted by most recent event date
    /// (newest first) rather than alphabetically.
    private func eventNames(for type: SessionType) -> [String] {
        var display: [String: String] = [:]   // key: lowercased name → display name
        var latest: [String: Date] = [:]       // key → most recent date
        for session in allSessions where !session.isActive && session.type == type {
            guard let name = session.leagueName ?? session.eventName, !name.isEmpty else { continue }
            let key = name.lowercased()
            if display[key] == nil { display[key] = name }
            if session.date > (latest[key] ?? .distantPast) { latest[key] = session.date }
        }
        for event in leagueEvents where event.kind.sessionType == type && !event.isArchived && !event.name.isEmpty {
            let key = event.name.lowercased()
            if display[key] == nil { display[key] = event.name }
            if latest[key] == nil { latest[key] = event.startDate ?? .distantPast }
        }
        return display.keys
            .sorted { (latest[$0] ?? .distantPast) > (latest[$1] ?? .distantPast) }
            .compactMap { display[$0] }
    }

    private var leagueNames: [String] { eventNames(for: .league) }
    private var tournamentNames: [String] { eventNames(for: .tournament) }

    private var archivedNames: Set<String> {
        Set(leagueEvents.filter { $0.kind == .league && $0.isArchived }.map { $0.name.lowercased() })
    }
    private var activeLeagueNames: [String] { leagueNames.filter { !archivedNames.contains($0.lowercased()) } }
    private var archivedLeagueNames: [String] { leagueNames.filter { archivedNames.contains($0.lowercased()) } }

    private var leagueFilterLabel: String {
        if leagueFilter.isEmpty { return "League / Event" }
        if leagueFilter.count == 1, let key = leagueFilter.first {
            return (leagueNames + tournamentNames).first { $0.lowercased() == key } ?? "1 selected"
        }
        return "\(leagueFilter.count) selected"
    }

    private var patterns: [Pattern] {
        var byID: [UUID: Pattern] = [:]
        for session in allSessions {
            if let pattern = session.pattern { byID[pattern.id] = pattern }
        }
        return Array(byID.values).sorted { $0.name < $1.name }
    }

    private func patternLabel(_ pattern: Pattern) -> String {
        pattern.name.isEmpty ? pattern.summary : pattern.name
    }

    private var ballFilterLabel: String {
        if ballFilter.isEmpty { return "Ball" }
        if ballFilter.count == 1, let id = ballFilter.first {
            return arsenal.first { $0.id == id }?.displayName ?? "1 ball"
        }
        return "\(ballFilter.count) balls"
    }

    private var patternFilterLabel: String {
        if patternFilter.isEmpty { return "Pattern" }
        if patternFilter.count == 1, let id = patternFilter.first,
           let pattern = patterns.first(where: { $0.id == id }) {
            return patternLabel(pattern)
        }
        return "\(patternFilter.count) patterns"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    filterBar

                    let stats = StatsEngine.dashboard(games: games)
                    // Stats show from the very first game — only masked when there's no data.
                    let belowThreshold = stats.gamesCount == 0

                    if conditionActive {
                        conditionBanner
                    }

                    primaryGrid(stats: stats, masked: belowThreshold)

                    if stats.gamesCount > 0 {
                        Text("Based on \(stats.gamesCount) game\(stats.gamesCount == 1 ? "" : "s") across \(stats.sessionsCount) session\(stats.sessionsCount == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }

                    if belowThreshold {
                        Text("No games match these filters yet.")
                            .font(Theme.cardSubtitle)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        SpareBreakdownPanel(games: games)
                        StrikeClustersPanel(stats: stats, sessions: allSessions)
                        SessionAveragesTable(sessions: allSessions, leagueEvents: leagueEvents, rangeStart: rangeStart, rangeEnd: rangeEnd)

                        Button {
                            showingCompare = true
                        } label: {
                            Label("Compare Averages", systemImage: "chart.bar.xaxis")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(Theme.bgCard)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
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
            .sheet(isPresented: $showingLeaguePicker) {
                LeagueFilterSheet(leagues: activeLeagueNames, tournaments: tournamentNames, archivedLeagues: archivedLeagueNames, selection: $leagueFilter)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingBallPicker) {
                IDFilterSheet(
                    title: "Filter by Ball",
                    options: arsenal.map { FilterOption(id: $0.id, label: $0.displayName) },
                    selection: $ballFilter
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingPatternPicker) {
                IDFilterSheet(
                    title: "Filter by Pattern",
                    options: patterns.map { FilterOption(id: $0.id, label: patternLabel($0)) },
                    selection: $patternFilter
                )
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showingCompare) {
                StatsCompareView()
            }
        }
    }

    private var conditionActive: Bool {
        !ballFilter.isEmpty || !patternFilter.isEmpty
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

            if !leagueNames.isEmpty || !tournamentNames.isEmpty {
                HStack(spacing: 8) {
                    Button {
                        showingLeaguePicker = true
                    } label: {
                        filterPill(icon: "trophy", label: leagueFilterLabel, active: !leagueFilter.isEmpty)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
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

                    Button {
                        showingBallPicker = true
                    } label: {
                        filterPill(icon: "circle.grid.3x3", label: ballFilterLabel, active: !ballFilter.isEmpty)
                    }
                    .buttonStyle(.plain)

                    Menu {
                        ForEach(PatternCondition.allCases) { condition in
                            Button(condition.rawValue) { conditionFilter = condition }
                        }
                    } label: {
                        filterPill(icon: "road.lanes", label: conditionFilter == .all ? "House/Sport" : conditionFilter.rawValue, active: conditionFilter != .all)
                    }

                    Button {
                        showingPatternPicker = true
                    } label: {
                        filterPill(icon: "drop", label: patternFilterLabel, active: !patternFilter.isEmpty)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.trailing, 4)
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
                ballFilter = []
                patternFilter = []
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
        .card(padding: 10)
    }

    private var conditionDescription: String {
        var parts: [String] = []
        if !ballFilter.isEmpty { parts.append(ballFilterLabel) }
        if !patternFilter.isEmpty { parts.append(patternFilterLabel) }
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
            StatTile(label: "Single Spare %", value: display(stats.singleSparePercent))
            StatTile(label: "Split %", value: display(stats.splitPercent))
            StatTile(label: "Open Frame %", value: display(stats.openFramePercent))
            StatTile(label: "Clean Game %", value: display(stats.cleanGamePercent))
            StatTile(label: "Average", value: display(stats.average, suffix: ""))
        }
    }
}

/// Multi-select league/tournament filter shared by the Stats and Spares tabs.
/// Selection is keyed by lowercased name so it spans created and imported leagues.
/// Archived leagues appear in a collapsible section (they're still in the stats).
struct LeagueFilterSheet: View {
    let leagues: [String]
    let tournaments: [String]
    var archivedLeagues: [String] = []
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss
    @State private var showArchived = false

    var body: some View {
        NavigationStack {
            List {
                if !selection.isEmpty {
                    Button("Clear selection", role: .destructive) { selection.removeAll() }
                }
                if !leagues.isEmpty {
                    Section("Leagues") {
                        ForEach(leagues, id: \.self) { row($0) }
                    }
                }
                if !tournaments.isEmpty {
                    Section("Tournaments") {
                        ForEach(tournaments, id: \.self) { row($0) }
                    }
                }
                if !archivedLeagues.isEmpty {
                    Section {
                        Button {
                            withAnimation(Theme.sectionSpring) { showArchived.toggle() }
                        } label: {
                            HStack {
                                Label("Archived (\(archivedLeagues.count))", systemImage: "archivebox")
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                        if showArchived {
                            ForEach(archivedLeagues, id: \.self) { row($0) }
                        }
                    }
                }
            }
            .navigationTitle("Leagues & Tournaments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func row(_ name: String) -> some View {
        Button {
            let key = name.lowercased()
            if selection.contains(key) { selection.remove(key) } else { selection.insert(key) }
        } label: {
            HStack {
                Text(name).foregroundStyle(Theme.textPrimary)
                Spacer()
                if selection.contains(name.lowercased()) {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
        }
    }
}

/// One selectable row for the generic multi-select filter sheet.
struct FilterOption: Identifiable {
    let id: UUID
    let label: String
}

/// Generic multi-select filter sheet keyed by UUID (balls, patterns).
struct IDFilterSheet: View {
    let title: String
    let options: [FilterOption]
    @Binding var selection: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if !selection.isEmpty {
                    Button("Clear selection", role: .destructive) { selection.removeAll() }
                }
                if options.isEmpty {
                    Text("Nothing to filter yet.")
                        .foregroundStyle(Theme.textMuted)
                } else {
                    ForEach(options) { option in
                        Button {
                            if selection.contains(option.id) {
                                selection.remove(option.id)
                            } else {
                                selection.insert(option.id)
                            }
                        } label: {
                            HStack {
                                Text(option.label).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if selection.contains(option.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

// MARK: - Average comparison (PRD 5.3: compare leagues or seasons side by side)

/// Compares averages across leagues/tournaments or across USBC seasons.
struct StatsCompareView: View {
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Environment(\.dismiss) private var dismiss

    enum Dimension: String, CaseIterable, Identifiable {
        case league = "Leagues"
        case season = "Seasons"
        var id: String { rawValue }
    }

    @State private var dimension: Dimension = .league

    private struct Group: Identifiable {
        let id = UUID()
        let label: String
        let average: Double
        let games: Int
        let high: Int
    }

    private var groups: [Group] {
        var buckets: [String: [Int]] = [:]
        var order: [String] = []
        for session in allSessions where !session.isActive {
            let key: String
            switch dimension {
            case .league:
                guard let name = session.leagueName ?? session.eventName, !name.isEmpty else { continue }
                key = name
            case .season:
                key = Self.usbcSeasonLabel(for: session.date)
            }
            // Use the lightweight final scores only — gameRecords() also derives every
            // leave (slow over a large history) and we don't need that here.
            let scores = session.sortedGames.map { $0.finalScore }.filter { $0 > 0 }
            guard !scores.isEmpty else { continue }
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(contentsOf: scores)
        }
        let result = order.compactMap { key -> Group? in
            guard let scores = buckets[key], !scores.isEmpty else { return nil }
            let avg = Double(scores.reduce(0, +)) / Double(scores.count)
            return Group(label: key, average: avg, games: scores.count, high: scores.max() ?? 0)
        }
        return result.sorted { $0.average > $1.average }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // Compute the grouping once per render (it was previously recomputed
                // three times — for the list, the bar scale, and the spread note).
                let groups = self.groups
                let maxAverage = groups.map { $0.average }.max() ?? 1

                VStack(alignment: .leading, spacing: 14) {
                    Picker("Compare", selection: $dimension) {
                        ForEach(Dimension.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if groups.isEmpty {
                        Text("Not enough data to compare yet.")
                            .font(Theme.cardSubtitle)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    } else {
                        ForEach(groups) { group in
                            compareRow(group, maxAverage: maxAverage)
                        }
                        if dimension == .league && groups.count >= 2 {
                            spreadNote(groups)
                        }
                    }
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Compare Averages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func compareRow(_ group: Group, maxAverage: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group.label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(Notation.oneDecimal(group.average))
                    .font(.system(size: 18, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.bgElevated)
                        .frame(height: 8)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * CGFloat(group.average / maxAverage), height: 8)
                }
            }
            .frame(height: 8)
            Text("\(group.games) game\(group.games == 1 ? "" : "s") · high \(group.high)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .card()
    }

    private func spreadNote(_ groups: [Group]) -> some View {
        let avgs = groups.map { $0.average }
        let spread = (avgs.max() ?? 0) - (avgs.min() ?? 0)
        return Text("Spread between highest and lowest average: \(Notation.oneDecimal(spread)) pins.")
            .font(.system(size: 12))
            .foregroundStyle(Theme.textMuted)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    /// USBC season label (Aug–Jul) for a date, e.g. "2024–25".
    static func usbcSeasonLabel(for date: Date, calendar: Calendar = .current) -> String {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let year = comps.year ?? 0
        let month = comps.month ?? 1
        let startYear = month >= 8 ? year : year - 1
        let endTwo = String(format: "%02d", (startYear + 1) % 100)
        return "\(startYear)–\(endTwo)"
    }
}
