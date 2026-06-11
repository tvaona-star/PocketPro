import SwiftUI
import SwiftData
import PocketProCore

/// Sessions tab (PRD 5.2): leagues grouped together; tournaments and practice
/// sessions listed separately. Create a league, then add a week each time you bowl.
struct SessionsTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Query private var leagueEvents: [LeagueEvent]
    @Query(filter: #Predicate<Ball> { $0.active }) private var arsenal: [Ball]

    @State private var showingNewLeague = false

    private var importReviewCount: Int {
        allSessions.filter { $0.importedFromPinPal && $0.needsTypeReview }.count
    }

    private struct LeagueGroup: Identifiable {
        let name: String
        let weeks: [Session]
        var id: String { name.lowercased() }
        var latest: Date { weeks.first?.date ?? .distantPast }
        var average: Double? {
            let scores = weeks.flatMap { $0.sortedGames }.map { $0.finalScore }.filter { $0 > 0 }
            guard !scores.isEmpty else { return nil }
            return Double(scores.reduce(0, +)) / Double(scores.count)
        }
    }

    /// One group per league name — from league-type sessions and created leagues.
    /// Single pass (allSessions is already date-desc, so each group stays ordered).
    private var leagues: [LeagueGroup] {
        var weeksByKey: [String: [Session]] = [:]
        var nameByKey: [String: String] = [:]
        for session in allSessions where !session.isActive && session.type == .league {
            guard let name = session.leagueName, !name.isEmpty else { continue }
            let key = name.lowercased()
            weeksByKey[key, default: []].append(session)
            if nameByKey[key] == nil { nameByKey[key] = name }
        }
        for event in leagueEvents where event.kind == .league && !event.isArchived && !event.name.isEmpty {
            let key = event.name.lowercased()
            if weeksByKey[key] == nil { weeksByKey[key] = [] }
            if nameByKey[key] == nil { nameByKey[key] = event.name }
        }
        return weeksByKey.keys
            .map { LeagueGroup(name: nameByKey[$0] ?? $0, weeks: weeksByKey[$0] ?? []) }
            .sorted { $0.latest > $1.latest }
    }

    private var otherSessions: [Session] {
        allSessions.filter { !$0.isActive && $0.type != .league }
    }

    var body: some View {
        NavigationStack {
            Group {
                if leagues.isEmpty && otherSessions.isEmpty {
                    EmptyStateView(
                        icon: "list.bullet.rectangle",
                        title: "No sessions yet",
                        message: "Create a league, or start a session from the Bowl tab.",
                        actionTitle: "New League",
                        action: { showingNewLeague = true }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if importReviewCount > 0 {
                            ImportReviewBanner(count: importReviewCount)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        }

                        if !leagues.isEmpty {
                            Section("Leagues") {
                                ForEach(leagues) { group in
                                    ZStack {
                                        NavigationLink {
                                            LeagueDetailView(leagueName: group.name)
                                        } label: { EmptyView() }
                                        .opacity(0)
                                        leagueRow(group)
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                }
                            }
                        }

                        if !otherSessions.isEmpty {
                            Section("Tournaments & Practice") {
                                ForEach(otherSessions) { session in
                                    ZStack {
                                        NavigationLink {
                                            SessionDetailView(session: session)
                                        } label: { EmptyView() }
                                        .opacity(0)
                                        SessionCard(session: session, arsenal: arsenal)
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                                }
                                .onDelete { offsets in
                                    for index in offsets { context.delete(otherSessions[index]) }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Sessions")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingNewLeague = true
                    } label: {
                        Label("New League", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarLink()
                }
            }
            .sheet(isPresented: $showingNewLeague) {
                NewLeagueSheet()
                    .presentationDetents([.medium])
            }
        }
    }

    private func leagueRow(_ group: LeagueGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("\(group.weeks.count) week\(group.weeks.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if let avg = group.average {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(Notation.oneDecimal(avg))
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                    Text("AVG")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .card()
    }
}

// MARK: - Filters (PRD 5.2: stack, dismissible chips, bottom sheet)

struct SessionFilters {
    var leagueName: String?
    var ballID: UUID?
    var patternID: UUID?
    var locationID: UUID?
    var dateFrom: Date?
    var dateTo: Date?

    var isActive: Bool {
        leagueName != nil || ballID != nil || patternID != nil || locationID != nil || dateFrom != nil || dateTo != nil
    }

    func matches(_ session: Session) -> Bool {
        if let leagueName {
            let name = session.leagueName ?? session.eventName ?? ""
            if name.caseInsensitiveCompare(leagueName) != .orderedSame { return false }
        }
        if let ballID {
            let used = session.sortedGames.flatMap { $0.ballIDsUsed }
            if !used.contains(ballID) { return false }
        }
        if let patternID, session.pattern?.id != patternID { return false }
        if let locationID, session.location?.id != locationID { return false }
        if let dateFrom, session.date < dateFrom { return false }
        if let dateTo, session.date > dateTo { return false }
        return true
    }

    struct Chip {
        let id: String
        let label: String
    }

    func chips(arsenal: [Ball]) -> [Chip] {
        var result: [Chip] = []
        if let leagueName {
            result.append(Chip(id: "league", label: leagueName))
        }
        if let ballID {
            let name = arsenal.first { $0.id == ballID }?.displayName ?? "Ball"
            result.append(Chip(id: "ball", label: name))
        }
        if patternID != nil {
            result.append(Chip(id: "pattern", label: "Pattern"))
        }
        if locationID != nil {
            result.append(Chip(id: "location", label: "Location"))
        }
        if dateFrom != nil || dateTo != nil {
            result.append(Chip(id: "dates", label: "Date range"))
        }
        return result
    }

    mutating func remove(_ id: String) {
        switch id {
        case "league": leagueName = nil
        case "ball": ballID = nil
        case "pattern": patternID = nil
        case "location": locationID = nil
        case "dates": dateFrom = nil; dateTo = nil
        default: break
        }
    }
}

struct SessionFilterSheet: View {
    @Binding var filters: SessionFilters
    let sessions: [Session]
    let arsenal: [Ball]
    @Environment(\.dismiss) private var dismiss

    @State private var useDateRange = false
    @State private var from = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var to = Date()

    private var leagueNames: [String] {
        var seen: [String] = []
        for session in sessions {
            if let name = session.leagueName ?? session.eventName, !name.isEmpty, !seen.contains(name) {
                seen.append(name)
            }
        }
        return seen
    }

    private var patterns: [Pattern] {
        var byID: [UUID: Pattern] = [:]
        for session in sessions {
            if let pattern = session.pattern { byID[pattern.id] = pattern }
        }
        return Array(byID.values).sorted { $0.name < $1.name }
    }

    private var locations: [Location] {
        var byID: [UUID: Location] = [:]
        for session in sessions {
            if let location = session.location { byID[location.id] = location }
        }
        return Array(byID.values).sorted { $0.name < $1.name }
    }

    private func applyDates() {
        if useDateRange {
            filters.dateFrom = Calendar.current.startOfDay(for: from)
            filters.dateTo = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to))
        } else {
            filters.dateFrom = nil
            filters.dateTo = nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("League / Event") {
                    Picker("Name", selection: $filters.leagueName) {
                        Text("Any").tag(String?.none)
                        ForEach(leagueNames, id: \.self) { name in
                            Text(name).tag(String?.some(name))
                        }
                    }
                }
                Section("Ball Used") {
                    Picker("Ball", selection: $filters.ballID) {
                        Text("Any").tag(UUID?.none)
                        ForEach(arsenal) { ball in
                            Text(ball.displayName).tag(UUID?.some(ball.id))
                        }
                    }
                }
                Section("Pattern") {
                    Picker("Pattern", selection: $filters.patternID) {
                        Text("Any").tag(UUID?.none)
                        ForEach(patterns) { pattern in
                            Text(pattern.name.isEmpty ? pattern.summary : pattern.name).tag(UUID?.some(pattern.id))
                        }
                    }
                }
                Section("Location") {
                    Picker("Location", selection: $filters.locationID) {
                        Text("Any").tag(UUID?.none)
                        ForEach(locations) { location in
                            Text(location.name).tag(UUID?.some(location.id))
                        }
                    }
                }
                Section("Date Range") {
                    Toggle("Filter by dates", isOn: $useDateRange)
                    if useDateRange {
                        DatePicker("From", selection: $from, displayedComponents: .date)
                        DatePicker("To", selection: $to, displayedComponents: .date)
                    }
                }
                Section {
                    Button("Clear all filters", role: .destructive) {
                        filters = SessionFilters()
                        useDateRange = false
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            // Every filter applies the instant it's selected — pickers bind to `filters`
            // directly; the date range mirrors that via onChange. "Done" only dismisses.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: useDateRange) { _, _ in applyDates() }
            .onChange(of: from) { _, _ in applyDates() }
            .onChange(of: to) { _, _ in applyDates() }
            .onAppear {
                useDateRange = filters.dateFrom != nil || filters.dateTo != nil
            }
        }
    }
}

// MARK: - Session card (PRD 5.2: everything visible without tapping)

struct SessionCard: View {
    let session: Session
    let arsenal: [Ball]

    private var scores: [Int] {
        session.sortedGames.map { $0.finalScore }
    }

    private var ballNames: [String] {
        var names: [String] = []
        for id in session.sortedGames.flatMap({ $0.ballIDsUsed }) {
            if let ball = arsenal.first(where: { $0.id == id }), !names.contains(ball.displayName) {
                names.append(ball.displayName)
            }
        }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Badge(text: session.type.displayName, color: Theme.sessionTypeColor(session.type))
                if session.flaggedAsPotentialDuplicate {
                    Badge(text: "Possible duplicate", color: Theme.warning)
                }
                Spacer()
                Text(session.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(Theme.cardSubtitle)
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(session.title)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                if let location = session.location?.name, !location.isEmpty {
                    Text(location)
                        .font(Theme.cardSubtitle)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            HStack(spacing: 8) {
                ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                    Text("\(score)")
                        .font(.system(size: 19, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Theme.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }

            if !ballNames.isEmpty || session.pattern != nil {
                HStack(spacing: 6) {
                    ForEach(ballNames.prefix(3), id: \.self) { name in
                        Badge(text: name, color: Theme.accent, filled: false)
                    }
                    if let pattern = session.pattern {
                        Text(pattern.name.isEmpty ? pattern.summary : "\(pattern.name) · \(pattern.lengthFt.map { "\($0) ft" } ?? pattern.type.displayName)")
                            .font(Theme.cardSubtitle)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            if !session.notes.isEmpty {
                Text(session.notes.components(separatedBy: .newlines).first ?? "")
                    .font(Theme.cardSubtitle)
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }

            let stats = session.quickStats
            if stats.strikes + stats.spares + stats.opens > 0 {
                HStack(spacing: 14) {
                    quickStat("\(stats.strikes)", "X")
                    quickStat("\(stats.spares)", "Spares")
                    quickStat("\(stats.opens)", "Opens")
                }
            }
        }
        .card()
    }

    private func quickStat(_ value: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 13, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
        }
    }
}

/// Post-import review banner (PRD 13.3 step 4).
struct ImportReviewBanner: View {
    let count: Int

    var body: some View {
        NavigationLink {
            ImportReviewView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) imported session\(count == 1 ? "" : "s") to review")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Re-tag session types, complete ball records, review patterns")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }
}
