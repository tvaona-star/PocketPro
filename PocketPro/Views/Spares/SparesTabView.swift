import SwiftUI
import SwiftData
import PocketProCore

/// Spares tab (PRD 5.5): leave frequency, conversion tracking, corner-pin spotlight,
/// and heatmap. All data flows from frame-level pin entry — no duplicate entry.
struct SparesTabView: View {
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Query(filter: #Predicate<Ball> { $0.active }) private var arsenal: [Ball]
    @Query private var leagueEvents: [LeagueEvent]
    @AppStorage(SettingsKeys.seasonDefinition) private var seasonRaw = SeasonDefinition.usbc.rawValue

    @State private var typeFilter: SessionType?
    @State private var leagueFilter: Set<String> = []
    @State private var showingLeaguePicker = false
    @State private var dateRange: StatDateRange = .thisSeason
    @State private var ballFilter: Set<UUID> = []
    @State private var patternFilter: Set<UUID> = []
    @State private var conditionFilter: PatternCondition = .all
    @State private var showingBallPicker = false
    @State private var showingPatternPicker = false
    @State private var bucketFilter: SpareBucket?
    @State private var heatmapPin: Int?
    @State private var viewMode: ViewMode = .list

    enum ViewMode: String, CaseIterable {
        case list = "List"
        case heatmap = "Heatmap"
    }

    private var season: SeasonDefinition {
        SeasonDefinition(rawValue: seasonRaw) ?? .usbc
    }

    private var rangeStart: Date? {
        let now = Date()
        switch dateRange {
        case .thisWeek: return Calendar.current.date(byAdding: .day, value: -7, to: now)
        case .thisMonth: return Calendar.current.date(byAdding: .month, value: -1, to: now)
        case .thisSeason: return season.seasonStart(now: now)
        case .lastYear: return Calendar.current.date(byAdding: .year, value: -1, to: now)
        case .allTime, .custom: return nil
        }
    }

    /// League/tournament names flagged sport-pattern — drives the House/Sport filter.
    private var sportNames: Set<String> {
        Set(leagueEvents.filter { $0.isSport }.map { $0.name.lowercased() })
    }

    private func sessionMatchesFilters(_ session: Session) -> Bool {
        if session.isActive { return false }
        if let typeFilter, session.type != typeFilter { return false }
        let name = (session.leagueName ?? session.eventName ?? "").lowercased()
        if !leagueFilter.isEmpty, !leagueFilter.contains(name) { return false }
        if conditionFilter != .all {
            let isSport = sportNames.contains(name)
            if (conditionFilter == .sport) != isSport { return false }
        }
        return true
    }

    private func gameMatchesFilters(_ game: GameRecord) -> Bool {
        if !ballFilter.isEmpty && ballFilter.isDisjoint(with: Set(game.ballIDs)) { return false }
        if !patternFilter.isEmpty {
            guard let id = game.patternID, patternFilter.contains(id) else { return false }
        }
        return true
    }

    private var games: [GameRecord] {
        allSessions
            .filter { session in
                sessionMatchesFilters(session) && (rangeStart.map { session.date >= $0 } ?? true)
            }
            .flatMap { $0.gameRecords() }
            .filter { gameMatchesFilters($0) }
    }

    /// Prior-period games for the corner spotlight trend.
    private var priorGames: [GameRecord] {
        guard let start = rangeStart else { return [] }
        let span = Date().timeIntervalSince(start)
        let priorStart = start.addingTimeInterval(-span)
        return allSessions
            .filter { sessionMatchesFilters($0) && $0.date >= priorStart && $0.date < start }
            .flatMap { $0.gameRecords() }
            .filter { gameMatchesFilters($0) }
    }

    private var hasAnyLeaves: Bool {
        games.contains { !$0.leaves.isEmpty }
    }

    /// League/tournament names sorted by most recent event date (newest first).
    private func eventNames(for type: SessionType) -> [String] {
        var display: [String: String] = [:]
        var latest: [String: Date] = [:]
        for s in allSessions where !s.isActive && s.type == type {
            guard let n = s.leagueName ?? s.eventName, !n.isEmpty else { continue }
            let key = n.lowercased()
            if display[key] == nil { display[key] = n }
            if s.date > (latest[key] ?? .distantPast) { latest[key] = s.date }
        }
        for e in leagueEvents where e.kind.sessionType == type && !e.isArchived && !e.name.isEmpty {
            let key = e.name.lowercased()
            if display[key] == nil { display[key] = e.name }
            if latest[key] == nil { latest[key] = e.startDate ?? .distantPast }
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
        for session in allSessions { if let pattern = session.pattern { byID[pattern.id] = pattern } }
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

                    if !hasAnyLeaves {
                        EmptyStateView(
                            icon: "pin",
                            title: "No spare data yet",
                            message: "Bowl a session to start tracking spare conversion."
                        )
                    } else {
                        CornerPinSpotlight(games: games, priorGames: priorGames)

                        Picker("View", selection: $viewMode) {
                            ForEach(ViewMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        switch viewMode {
                        case .list:
                            bucketMenu
                            LeaveFrequencyList(games: games, bucketFilter: bucketFilter, pinFilter: heatmapPin)
                        case .heatmap:
                            PinLeaveHeatmap(games: games, selectedPin: $heatmapPin)
                            if let pin = heatmapPin {
                                Text("Showing leaves containing the \(pin) pin — tap the pin again to clear.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textMuted)
                                LeaveFrequencyList(games: games, bucketFilter: nil, pinFilter: pin)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Spares")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarLink()
                }
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
        }
    }

    // MARK: Filters (PRD 5.5.4)

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("Type", selection: $typeFilter) {
                Text("All").tag(SessionType?.none)
                ForEach(SessionType.allCases) { type in
                    Text(type.displayName).tag(SessionType?.some(type))
                }
            }
            .pickerStyle(.segmented)

            // Same filter set as the Stats tab: league/event, date, ball, pattern.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !leagueNames.isEmpty || !tournamentNames.isEmpty {
                        Button { showingLeaguePicker = true } label: {
                            menuPill(leagueFilterLabel, active: !leagueFilter.isEmpty)
                        }
                        .buttonStyle(.plain)
                    }
                    Menu {
                        ForEach([StatDateRange.thisWeek, .thisMonth, .thisSeason, .lastYear, .allTime]) { range in
                            Button(range.displayName) { dateRange = range }
                        }
                    } label: {
                        menuPill(dateRange.displayName, active: dateRange != .allTime)
                    }
                    Button { showingBallPicker = true } label: {
                        menuPill(ballFilterLabel, active: !ballFilter.isEmpty)
                    }
                    .buttonStyle(.plain)

                    if !patterns.isEmpty {
                        Button { showingPatternPicker = true } label: {
                            menuPill(patternFilterLabel, active: !patternFilter.isEmpty)
                        }
                        .buttonStyle(.plain)
                    }

                    Menu {
                        ForEach(PatternCondition.allCases) { condition in
                            Button(condition.rawValue) { conditionFilter = condition }
                        }
                    } label: {
                        menuPill(conditionFilter == .all ? "House/Sport" : conditionFilter.rawValue, active: conditionFilter != .all)
                    }
                }
            }
        }
    }

    private func menuPill(_ label: String, active: Bool) -> some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(active ? Color.white : Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(active ? Theme.accent : Theme.bgElevated)
            .clipShape(Capsule())
    }

    /// Bucket filter dropdown (PRD 5.5.4): Single Pins / Multi Pins / Splits / Opens.
    private var bucketMenu: some View {
        HStack {
            Menu {
                Button("All leaves") { bucketFilter = nil }
                ForEach(SpareBucket.allCases) { bucket in
                    Button(bucket.rawValue) { bucketFilter = bucket }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(bucketFilter?.rawValue ?? "All leaves")
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .bold))
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(bucketFilter != nil ? Color.white : Theme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(bucketFilter != nil ? Theme.accent : Theme.bgElevated)
                .clipShape(Capsule())
            }
            Spacer()
        }
    }
}

/// Spare leave buckets (PRD 5.5.4) — a UI grouping over the fine-grained
/// LeaveCategory taxonomy. Single/Multi/Splits partition by geometry; Opens is
/// outcome-based (leaves left open), which also replaces the old Miss Log.
enum SpareBucket: String, CaseIterable, Identifiable {
    case singlePins = "Single Pins"
    case multiPins = "Multi Pins"
    case splits = "Splits"
    case opens = "Opens"

    var id: String { rawValue }

    func contains(_ entry: LeaveFrequencyEntry) -> Bool {
        let isSplit = entry.classification.isSplit
        switch self {
        case .singlePins: return !isSplit && entry.pins.count == 1
        case .multiPins:  return !isSplit && entry.pins.count >= 2
        case .splits:     return isSplit
        case .opens:      return entry.aggregate.opportunities > entry.aggregate.timesConverted
        }
    }
}

// MARK: - Corner pin spotlight (PRD 5.5.4: 7 and 10 always visible, no scrolling)

struct CornerPinSpotlight: View {
    let games: [GameRecord]
    let priorGames: [GameRecord]

    var body: some View {
        HStack(spacing: 10) {
            spotlightCard(pin: 7)
            spotlightCard(pin: 10)
        }
    }

    private func spotlightCard(pin: Int) -> some View {
        let aggregate = StatsEngine.pinAggregate(games: games, pins: PinSet(pins: [pin]))
        let prior = StatsEngine.pinAggregate(games: priorGames, pins: PinSet(pins: [pin]))
        let delta: Double? = {
            guard let current = aggregate.conversionPercent, let previous = prior.conversionPercent else { return nil }
            return current - previous
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(pin) PIN")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                PinDiagram(standing: PinSet(pins: [pin]), size: 26)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Notation.percent(aggregate.conversionPercent))
                    .font(Theme.statNumber(28))
                    .foregroundStyle(Theme.conversionColor(aggregate.conversionPercent))
                if let delta, delta != 0 {
                    TrendArrow(delta: delta)
                }
            }
            Text("Left \(aggregate.timesLeft) · made \(aggregate.timesConverted)")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
        }
        .card()
    }
}

// MARK: - Leave frequency list (PRD 5.5.4 default view)

struct LeaveFrequencyList: View {
    let games: [GameRecord]
    let bucketFilter: SpareBucket?
    let pinFilter: Int?

    private var entries: [LeaveFrequencyEntry] {
        StatsEngine.leaveFrequency(games: games).filter { entry in
            if let bucketFilter, !bucketFilter.contains(entry) { return false }
            if let pinFilter, !entry.pins.contains(pinFilter) { return false }
            return true
        }
    }

    private var totalLeaves: Int {
        entries.reduce(0) { $0 + $1.aggregate.timesLeft }
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.element.pins.mask) { _, entry in
                NavigationLink {
                    LeaveDetailView(pins: entry.pins)
                } label: {
                    leaveRow(entry)
                }
                .buttonStyle(.plain)
            }
            if entries.isEmpty {
                Text("No leaves match this filter.")
                    .font(Theme.cardSubtitle)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.vertical, 20)
            }
        }
    }

    private func leaveRow(_ entry: LeaveFrequencyEntry) -> some View {
        let aggregate = entry.aggregate
        let percentOfFrames = totalLeaves > 0 ? Double(aggregate.timesLeft) / Double(totalLeaves) * 100 : 0

        return HStack(spacing: 12) {
            PinDiagram(standing: entry.pins, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.classification.displayTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Badge(
                        text: entry.classification.primary.displayName,
                        color: entry.classification.isSplit ? Theme.destructive : Theme.accent,
                        filled: false
                    )
                }
                Text("Left \(aggregate.timesLeft)× · \(Notation.percent(percentOfFrames)) of leaves")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Notation.percent(aggregate.conversionPercent))
                    .font(.system(size: 17, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.conversionColor(aggregate.conversionPercent))
                Text("\(aggregate.timesConverted)/\(aggregate.opportunities)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .card(padding: 12)
    }
}

// MARK: - Pin leave heatmap (PRD 5.5.4, pulled into v1 per DECISIONS.md D5)

struct PinLeaveHeatmap: View {
    let games: [GameRecord]
    @Binding var selectedPin: Int?

    var body: some View {
        let counts = StatsEngine.pinLeaveCounts(games: games)
        let maxCount = max(counts.max() ?? 1, 1)

        VStack(spacing: 10) {
            GeometryReader { geo in
                ZStack {
                    ForEach(1...10, id: \.self) { pin in
                        let unit = PinGeometry.unitPoint(pin: pin)
                        let intensity = Double(counts[pin]) / Double(maxCount)
                        Button {
                            selectedPin = selectedPin == pin ? nil : pin
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(heatColor(intensity))
                                Circle()
                                    .strokeBorder(selectedPin == pin ? Theme.textPrimary : Color.clear, lineWidth: 2)
                                VStack(spacing: 0) {
                                    Text("\(pin)")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(.white)
                                    Text("\(counts[pin])")
                                        .font(.system(size: 9, weight: .semibold).monospacedDigit())
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                            }
                            .frame(width: 52, height: 52)
                        }
                        .buttonStyle(.plain)
                        .position(x: unit.x * geo.size.width, y: unit.y * geo.size.height)
                    }
                }
            }
            .aspectRatio(1.45, contentMode: .fit)

            HStack(spacing: 6) {
                Text("Rarely left")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                LinearGradient(
                    colors: [heatColor(0), heatColor(0.5), heatColor(1)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 6)
                .clipShape(Capsule())
                Text("Left often")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .card()
    }

    private func heatColor(_ intensity: Double) -> Color {
        // green (rare) → amber → red (problem pin)
        if intensity < 0.5 {
            return Color(
                .sRGB,
                red: 0.09 + (0.85 - 0.09) * intensity * 2,
                green: 0.64 - (0.64 - 0.47) * intensity * 2,
                blue: 0.29 - 0.26 * intensity * 2,
                opacity: 1
            )
        }
        let t = (intensity - 0.5) * 2
        return Color(
            .sRGB,
            red: 0.85 + (0.86 - 0.85) * t,
            green: 0.47 - (0.47 - 0.15) * t,
            blue: 0.03 + (0.15 - 0.03) * t,
            opacity: 1
        )
    }
}
