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
                            Label("Compare Stats", systemImage: "chart.bar.xaxis")
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

        // 2×4 grid (row-major): left column Strike/SinglePin/Makeable/Clean,
        // right column Average/Double/Split/Open.
        return LazyVGrid(columns: columns, spacing: 10) {
            StatTile(label: "Strike %", value: display(stats.strikePercent))
            StatTile(label: "Average", value: display(stats.average, suffix: ""))
            StatTile(label: "Single Pin Spare %", value: display(stats.singleSparePercent))
            StatTile(label: "Double %", value: display(stats.doublesPercent))
            StatTile(label: "Makeable Spare %", value: display(stats.makeableSparePercent))
            StatTile(label: "Split %", value: display(stats.splitPercent))
            StatTile(label: "Clean Game %", value: display(stats.cleanGamePercent))
            StatTile(label: "Open Frame %", value: display(stats.openFramePercent))
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

// MARK: - Stat comparison (PRD 5.3: two configurable columns, the 8 dashboard cards)

/// One selectable comparable for a compare column — a league, tournament, or season.
struct CompareItem: Identifiable {
    let token: String       // "L:name" / "T:name" / "S:label"
    let label: String
    let category: String    // "Leagues" / "Tournaments" / "Seasons"
    var id: String { token }
}

/// Two columns, each aggregating a chosen set of leagues / tournaments / seasons,
/// shown as the eight main-dashboard stat cards for side-by-side comparison.
struct StatsCompareView: View {
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Environment(\.dismiss) private var dismiss

    @State private var leftSelection: Set<String> = []
    @State private var rightSelection: Set<String> = []
    @State private var editing: Side?

    enum Side: Int, Identifiable { case left, right; var id: Int { rawValue } }

    private static let statOrder = [
        "Average", "Strike %", "Single Pin Spare %", "Makeable Spare %",
        "Double %", "Split %", "Clean Game %", "Open Frame %",
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                HStack(alignment: .top, spacing: 10) {
                    column($leftSelection, side: .left)
                    column($rightSelection, side: .right)
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Compare Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editing) { side in
                ComparePickerSheet(
                    items: comparables,
                    selection: side == .left ? $leftSelection : $rightSelection
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func column(_ selection: Binding<Set<String>>, side: Side) -> some View {
        let empty = selection.wrappedValue.isEmpty
        let stats = StatsEngine.dashboard(games: gameRecords(for: selection.wrappedValue))
        return VStack(spacing: 8) {
            Button { editing = side } label: {
                VStack(spacing: 3) {
                    Text(selectionLabel(selection.wrappedValue))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(empty ? Theme.accent : Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(empty ? "Tap to choose" : "\(stats.gamesCount) game\(stats.gamesCount == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .padding(.vertical, 8)
                .background(Theme.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            ForEach(Self.statOrder, id: \.self) { label in
                VStack(spacing: 2) {
                    Text(empty ? "--" : value(label, stats))
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.bgCard)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func value(_ label: String, _ s: DashboardStats) -> String {
        func pct(_ v: Double?) -> String { v.map { String(format: "%.1f%%", $0) } ?? "--" }
        switch label {
        case "Average": return s.average.map { Notation.oneDecimal($0) } ?? "--"
        case "Strike %": return pct(s.strikePercent)
        case "Single Pin Spare %": return pct(s.singleSparePercent)
        case "Makeable Spare %": return pct(s.makeableSparePercent)
        case "Double %": return pct(s.doublesPercent)
        case "Split %": return pct(s.splitPercent)
        case "Clean Game %": return pct(s.cleanGamePercent)
        case "Open Frame %": return pct(s.openFramePercent)
        default: return "--"
        }
    }

    private func selectionLabel(_ selection: Set<String>) -> String {
        if selection.isEmpty { return "Select…" }
        let labels = comparables.filter { selection.contains($0.token) }.map { $0.label }
        if labels.count == 1 { return labels[0] }
        return "\(labels.count) selected"
    }

    // MARK: Data

    private func tokens(for session: Session) -> Set<String> {
        var t: Set<String> = ["S:" + Self.usbcSeasonLabel(for: session.date)]
        if let name = session.leagueName ?? session.eventName, !name.isEmpty {
            t.insert((session.type == .tournament ? "T:" : "L:") + name.lowercased())
        }
        return t
    }

    private func gameRecords(for selection: Set<String>) -> [GameRecord] {
        guard !selection.isEmpty else { return [] }
        return allSessions
            .filter { !$0.isActive && !tokens(for: $0).isDisjoint(with: selection) }
            .flatMap { $0.gameRecords() }
    }

    /// Leagues, tournaments, and seasons available to pick, each newest-first.
    private var comparables: [CompareItem] {
        var display: [String: String] = [:]
        var latest: [String: Date] = [:]
        for session in allSessions where !session.isActive {
            let seasonLabel = Self.usbcSeasonLabel(for: session.date)
            let seasonToken = "S:" + seasonLabel
            if display[seasonToken] == nil { display[seasonToken] = seasonLabel + " season" }
            if session.date > (latest[seasonToken] ?? .distantPast) { latest[seasonToken] = session.date }
            guard let name = session.leagueName ?? session.eventName, !name.isEmpty else { continue }
            let token = (session.type == .tournament ? "T:" : "L:") + name.lowercased()
            if display[token] == nil { display[token] = name }
            if session.date > (latest[token] ?? .distantPast) { latest[token] = session.date }
        }
        func items(prefix: String, category: String) -> [CompareItem] {
            display.keys.filter { $0.hasPrefix(prefix) }
                .sorted { (latest[$0] ?? .distantPast) > (latest[$1] ?? .distantPast) }
                .map { CompareItem(token: $0, label: display[$0] ?? $0, category: category) }
        }
        return items(prefix: "L:", category: "Leagues")
            + items(prefix: "T:", category: "Tournaments")
            + items(prefix: "S:", category: "Seasons")
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

/// Multi-select picker for a compare column (leagues / tournaments / seasons).
struct ComparePickerSheet: View {
    let items: [CompareItem]
    @Binding var selection: Set<String>
    @Environment(\.dismiss) private var dismiss

    private var categories: [String] {
        var seen: [String] = []
        for item in items where !seen.contains(item.category) { seen.append(item.category) }
        return seen
    }

    var body: some View {
        NavigationStack {
            List {
                if !selection.isEmpty {
                    Button("Clear selection", role: .destructive) { selection.removeAll() }
                }
                ForEach(categories, id: \.self) { category in
                    Section(category) {
                        ForEach(items.filter { $0.category == category }) { item in
                            Button {
                                if selection.contains(item.token) {
                                    selection.remove(item.token)
                                } else {
                                    selection.insert(item.token)
                                }
                            } label: {
                                HStack {
                                    Text(item.label).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    if selection.contains(item.token) {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}
