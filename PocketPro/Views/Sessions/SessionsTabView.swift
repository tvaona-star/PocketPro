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
    @State private var showingNewTournament = false
    @State private var showArchived = false
    @State private var leaguesExpanded = true
    @State private var tournamentsExpanded = true
    @State private var practiceExpanded = true
    @State private var deleteLeagueCandidate: String?
    @State private var deleteTournamentCandidate: String?

    private var importReviewCount: Int {
        allSessions.filter { $0.importedFromPinPal && $0.needsTypeReview }.count
    }

    /// Lowercased names of leagues the user has archived (hidden from this page,
    /// still counted in Stats).
    private var archivedNames: Set<String> {
        Set(leagueEvents.filter { $0.kind == .league && $0.isArchived }.map { $0.name.lowercased() })
    }

    /// League/event names flagged as sport-pattern — drives the "Sport" pill.
    private var sportNames: Set<String> {
        Set(leagueEvents.filter { $0.isSport }.map { $0.name.lowercased() })
    }
    private func isSport(_ session: Session) -> Bool {
        sportNames.contains((session.leagueName ?? session.eventName ?? "").lowercased())
    }
    private func isSportLeague(_ name: String) -> Bool {
        sportNames.contains(name.lowercased())
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
    /// Sorted by last entry date so the most recently bowled leagues are on top.
    private func groupLeagues(includeArchived: Bool) -> [LeagueGroup] {
        let archived = archivedNames
        var weeksByKey: [String: [Session]] = [:]
        var nameByKey: [String: String] = [:]
        for session in allSessions where !session.isActive && session.type == .league {
            guard let name = session.leagueName, !name.isEmpty else { continue }
            let key = name.lowercased()
            if archived.contains(key) != includeArchived { continue }
            weeksByKey[key, default: []].append(session)
            if nameByKey[key] == nil { nameByKey[key] = name }
        }
        for event in leagueEvents where event.kind == .league && !event.name.isEmpty && event.isArchived == includeArchived {
            let key = event.name.lowercased()
            if weeksByKey[key] == nil { weeksByKey[key] = [] }
            if nameByKey[key] == nil { nameByKey[key] = event.name }
        }
        return weeksByKey.keys
            .map { LeagueGroup(name: nameByKey[$0] ?? $0, weeks: weeksByKey[$0] ?? []) }
            .sorted { $0.latest > $1.latest }
    }

    private var leagues: [LeagueGroup] { groupLeagues(includeArchived: false) }
    private var archivedLeagues: [LeagueGroup] { groupLeagues(includeArchived: true) }

    /// A tournament and its event blocks (parallel to a league and its weeks).
    private struct TournamentGroup: Identifiable {
        let name: String
        let blocks: [Session]
        var id: String { name.lowercased() }
        var latest: Date { blocks.first?.date ?? .distantPast }
        var average: Double? {
            let scores = blocks.flatMap { $0.sortedGames }.map { $0.finalScore }.filter { $0 > 0 }
            guard !scores.isEmpty else { return nil }
            return Double(scores.reduce(0, +)) / Double(scores.count)
        }
    }

    /// One group per tournament name — its event blocks plus created tournament events.
    private func groupTournaments() -> [TournamentGroup] {
        var blocksByKey: [String: [Session]] = [:]
        var nameByKey: [String: String] = [:]
        for session in allSessions where !session.isActive && !session.isArchived && session.type == .tournament {
            let name = session.eventName ?? session.leagueName ?? ""
            guard !name.isEmpty else { continue }
            let key = name.lowercased()
            blocksByKey[key, default: []].append(session)
            if nameByKey[key] == nil { nameByKey[key] = name }
        }
        for event in leagueEvents where event.kind == .tournament && !event.isArchived && !event.name.isEmpty {
            let key = event.name.lowercased()
            if blocksByKey[key] == nil { blocksByKey[key] = [] }
            if nameByKey[key] == nil { nameByKey[key] = event.name }
        }
        return blocksByKey.keys
            .map { TournamentGroup(name: nameByKey[$0] ?? $0, blocks: blocksByKey[$0] ?? []) }
            .sorted { $0.latest > $1.latest }
    }

    private var tournamentGroups: [TournamentGroup] { groupTournaments() }

    /// Non-archived practice sessions, newest first.
    private var practiceSessions: [Session] {
        allSessions.filter { !$0.isActive && !$0.isArchived && $0.type == .practice }
    }

    /// Archived one-off sessions (tournament/practice) — leagues archive by name
    /// in `archivedLeagues`, so they're excluded here.
    private var archivedSessions: [Session] {
        allSessions.filter { !$0.isActive && $0.isArchived && $0.type != .league }
    }

    /// True when there's nothing at all to show — drives the empty state.
    private var hasAnySessions: Bool {
        !leagues.isEmpty || !tournamentGroups.isEmpty || !practiceSessions.isEmpty
            || !archivedLeagues.isEmpty || !archivedSessions.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasAnySessions {
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
                            Section {
                                sectionHeaderRow("Leagues", count: leagues.count, isExpanded: $leaguesExpanded)
                                if leaguesExpanded {
                                    ForEach(leagues) { group in
                                        leagueNavRow(group, archived: false)
                                    }
                                }
                            }
                        }

                        if !tournamentGroups.isEmpty {
                            Section {
                                sectionHeaderRow("Tournaments", count: tournamentGroups.count, isExpanded: $tournamentsExpanded)
                                if tournamentsExpanded {
                                    ForEach(tournamentGroups) { group in
                                        tournamentNavRow(group)
                                    }
                                }
                            }
                        }

                        if !practiceSessions.isEmpty {
                            Section {
                                sectionHeaderRow("Practice", count: practiceSessions.count, isExpanded: $practiceExpanded)
                                if practiceExpanded {
                                    ForEach(practiceSessions) { session in
                                        sessionNavRow(session, archived: false)
                                    }
                                }
                            }
                        }

                        if !archivedLeagues.isEmpty || !archivedSessions.isEmpty {
                            Section {
                                Button {
                                    withAnimation(Theme.sectionSpring) { showArchived.toggle() }
                                } label: {
                                    HStack {
                                        Label("Archived (\(archivedLeagues.count + archivedSessions.count))", systemImage: "archivebox")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(Theme.textSecondary)
                                        Spacer()
                                        Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Theme.textMuted)
                                    }
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

                                if showArchived {
                                    ForEach(archivedLeagues) { group in
                                        leagueNavRow(group, archived: true)
                                    }
                                    ForEach(archivedSessions) { session in
                                        sessionNavRow(session, archived: true)
                                    }
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
                    Menu {
                        Button {
                            showingNewLeague = true
                        } label: {
                            Label("New League", systemImage: "trophy")
                        }
                        Button {
                            showingNewTournament = true
                        } label: {
                            Label("New Tournament", systemImage: "flag.checkered")
                        }
                    } label: {
                        Image(systemName: "plus")
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
            .sheet(isPresented: $showingNewTournament) {
                NewTournamentSheet()
                    .presentationDetents([.medium])
            }
            .confirmationDialog(
                "Delete \(deleteLeagueCandidate ?? "league")?",
                isPresented: Binding(get: { deleteLeagueCandidate != nil }, set: { if !$0 { deleteLeagueCandidate = nil } }),
                titleVisibility: .visible,
                presenting: deleteLeagueCandidate
            ) { name in
                Button("Delete league & all weeks", role: .destructive) {
                    deleteLeague(name)
                    deleteLeagueCandidate = nil
                }
                Button("Cancel", role: .cancel) { deleteLeagueCandidate = nil }
            } message: { name in
                Text("Permanently removes \(name) and every week and game in it. To keep the data for stats but hide it here, use Archive instead.")
            }
            .confirmationDialog(
                "Delete \(deleteTournamentCandidate ?? "tournament")?",
                isPresented: Binding(get: { deleteTournamentCandidate != nil }, set: { if !$0 { deleteTournamentCandidate = nil } }),
                titleVisibility: .visible,
                presenting: deleteTournamentCandidate
            ) { name in
                Button("Delete tournament & all blocks", role: .destructive) {
                    deleteTournament(name)
                    deleteTournamentCandidate = nil
                }
                Button("Cancel", role: .cancel) { deleteTournamentCandidate = nil }
            } message: { name in
                Text("Permanently removes \(name) and every event block and game in it. To keep the data for stats but hide it here, use Archive instead.")
            }
        }
    }

    /// Archive/unarchive a league by name — creates a record for imported leagues
    /// that don't have one yet so the flag has somewhere to live.
    private func setArchived(_ name: String, _ archived: Bool) {
        let key = name.lowercased()
        if let event = leagueEvents.first(where: { $0.kind == .league && $0.name.lowercased() == key }) {
            event.isArchived = archived
        } else if archived {
            let event = LeagueEvent()
            event.name = name
            event.kind = .league
            event.isArchived = true
            context.insert(event)
        }
    }

    private func deleteLeague(_ name: String) {
        let key = name.lowercased()
        for session in allSessions where session.type == .league && (session.leagueName ?? "").lowercased() == key {
            context.delete(session)
        }
        for event in leagueEvents where event.kind == .league && event.name.lowercased() == key {
            context.delete(event)
        }
    }

    /// Archive every event block of a tournament (still counted in Stats).
    private func setTournamentArchived(_ name: String, _ archived: Bool) {
        let key = name.lowercased()
        for session in allSessions where session.type == .tournament
            && (session.eventName ?? session.leagueName ?? "").lowercased() == key {
            session.isArchived = archived
        }
        if let event = leagueEvents.first(where: { $0.kind == .tournament && $0.name.lowercased() == key }) {
            event.isArchived = archived
        }
    }

    private func deleteTournament(_ name: String) {
        let key = name.lowercased()
        for session in allSessions where session.type == .tournament
            && (session.eventName ?? session.leagueName ?? "").lowercased() == key {
            context.delete(session)
        }
        for event in leagueEvents where event.kind == .tournament && event.name.lowercased() == key {
            context.delete(event)
        }
    }

    /// A tournament group row with navigation and archive/delete swipes.
    private func tournamentNavRow(_ group: TournamentGroup) -> some View {
        ZStack {
            NavigationLink {
                TournamentDetailView(tournamentName: group.name)
            } label: { EmptyView() }
            .opacity(0)
            tournamentRow(group)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteTournamentCandidate = group.name
            } label: { Label("Delete", systemImage: "trash") }
            Button {
                setTournamentArchived(group.name, true)
            } label: { Label("Archive", systemImage: "archivebox") }
            .tint(Theme.warning)
        }
    }

    private func tournamentRow(_ group: TournamentGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 16))
                .foregroundStyle(Theme.sessionTypeColor(.tournament))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    if isSportLeague(group.name) {
                        Badge(text: "Sport", color: Theme.warning)
                    }
                }
                Text("\(group.blocks.count) block\(group.blocks.count == 1 ? "" : "s")"
                     + (group.blocks.first.map { " · last \($0.date.formatted(.dateTime.month(.abbreviated).day().year()))" } ?? ""))
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

    /// Tappable section header used by Leagues / Tournaments / Practice.
    private func sectionHeaderRow(_ title: String, count: Int, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(Theme.sectionSpring) { isExpanded.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 6) {
                Text(title.uppercased())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 2, trailing: 16))
    }

    /// A league group row with navigation and archive/delete (or unarchive) swipes.
    private func leagueNavRow(_ group: LeagueGroup, archived: Bool) -> some View {
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
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteLeagueCandidate = group.name
            } label: { Label("Delete", systemImage: "trash") }
            if archived {
                Button {
                    setArchived(group.name, false)
                } label: { Label("Unarchive", systemImage: "arrow.uturn.up") }
                .tint(Theme.accent)
            } else {
                Button {
                    setArchived(group.name, true)
                } label: { Label("Archive", systemImage: "archivebox") }
                .tint(Theme.warning)
            }
        }
    }

    /// A single session row with navigation and archive/delete (or unarchive) swipes.
    private func sessionNavRow(_ session: Session, archived: Bool) -> some View {
        ZStack {
            NavigationLink {
                SessionDetailView(session: session)
            } label: { EmptyView() }
            .opacity(0)
            SessionCard(session: session, arsenal: arsenal, isSport: isSport(session))
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                context.delete(session)
            } label: { Label("Delete", systemImage: "trash") }
            if archived {
                Button {
                    session.isArchived = false
                } label: { Label("Unarchive", systemImage: "arrow.uturn.up") }
                .tint(Theme.accent)
            } else {
                Button {
                    session.isArchived = true
                } label: { Label("Archive", systemImage: "archivebox") }
                .tint(Theme.warning)
            }
        }
    }

    private func leagueRow(_ group: LeagueGroup) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "trophy.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    if isSportLeague(group.name) {
                        Badge(text: "Sport", color: Theme.warning)
                    }
                }
                Text("\(group.weeks.count) week\(group.weeks.count == 1 ? "" : "s")"
                     + (group.weeks.first.map { " · last \($0.date.formatted(.dateTime.month(.abbreviated).day().year()))" } ?? ""))
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
    var isSport: Bool = false

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
                if isSport {
                    Badge(text: "Sport", color: Theme.warning)
                }
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

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(Array(scores.enumerated()), id: \.offset) { _, score in
                    Text("\(score)")
                        .font(.system(size: 18, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
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
