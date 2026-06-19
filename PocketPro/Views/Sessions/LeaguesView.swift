import SwiftUI
import SwiftData
import PocketProCore

// MARK: - Create a league (PRD 5.2: name, start date, games per week)

struct NewLeagueSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var startDate = Date()
    @State private var gamesPerWeek = 3
    @State private var isSport = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Tuesday Classic)", text: $name)
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    Stepper("Games per week: \(gamesPerWeek)", value: $gamesPerWeek, in: 1...12)
                    Toggle("Sport pattern league", isOn: $isSport)
                } header: {
                    Text("League")
                } footer: {
                    Text("Then open the league and add a week each time you bowl. Every week stays grouped under this league.")
                }
            }
            .navigationTitle("New League")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        let league = LeagueEvent()
                        league.name = name.trimmingCharacters(in: .whitespaces)
                        league.kind = .league
                        league.startDate = startDate
                        league.gamesPerWeek = gamesPerWeek
                        league.isSport = isSport
                        context.insert(league)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Edit a league's start date / games per week, or convert the whole league
/// (every week) to a Tournament or Practice — creates the record for an
/// imported league that doesn't have one yet.
struct LeagueEditSheet: View {
    let leagueName: String
    let existing: LeagueEvent?
    /// Called after a conversion empties this league, so the detail view can pop.
    var onConverted: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Query private var leagueEvents: [LeagueEvent]

    @State private var type: SessionType = .league
    @State private var name = ""
    @State private var startDate = Date()
    @State private var hasStartDate = false
    @State private var gamesPerWeek = 3
    @State private var isSport = false

    /// The league's own sessions (its weeks) — what a conversion will re-tag.
    private var weeks: [Session] {
        allSessions.filter {
            $0.type == .league && ($0.leagueName ?? "").caseInsensitiveCompare(leagueName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(SessionType.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if type != .league {
                        Text("Converts all \(weeks.count) week\(weeks.count == 1 ? "" : "s") under \(leagueName) to \(type.displayName) and removes the league grouping. Scores are kept.")
                    }
                }

                if type == .league {
                    Section("Name") {
                        TextField("League name", text: $name)
                    }
                    Section("Season") {
                        Toggle("Set a start date", isOn: $hasStartDate)
                        if hasStartDate {
                            DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                        }
                        Stepper("Games per week: \(gamesPerWeek)", value: $gamesPerWeek, in: 1...12)
                        Toggle("Sport pattern league", isOn: $isSport)
                    }
                } else if type == .tournament {
                    Section {
                        Toggle("Sport pattern", isOn: $isSport)
                    }
                }
            }
            .navigationTitle(leagueName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(type == .league ? "Save" : "Convert") { save() }
                }
            }
            .onAppear {
                name = leagueName
                if let existing {
                    hasStartDate = existing.startDate != nil
                    startDate = existing.startDate ?? Date()
                    gamesPerWeek = existing.gamesPerWeek
                    isSport = existing.isSport
                }
            }
        }
    }

    private func save() {
        if type == .league {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let newName = trimmed.isEmpty ? leagueName : trimmed
            let renamed = newName.caseInsensitiveCompare(leagueName) != .orderedSame

            let league = findOrCreateEvent(newName, kind: .league)
            league.startDate = hasStartDate ? startDate : nil
            league.gamesPerWeek = gamesPerWeek
            league.isSport = isSport

            if renamed {
                // Re-tag every week to the new name and drop the old record.
                for week in weeks {
                    week.leagueName = newName
                    week.leagueEvent = league
                }
                if let existing, existing !== league { context.delete(existing) }
            }
            dismiss()
            if renamed { onConverted?() }   // detail's leagueName is now stale → pop
        } else {
            convert(to: type)
            dismiss()
            onConverted?()
        }
    }

    /// Re-tag every week of this league to the new type and drop the league record.
    private func convert(to newType: SessionType) {
        let event: LeagueEvent? = newType == .tournament ? findOrCreateEvent(leagueName, kind: .tournament) : nil
        event?.isSport = isSport
        for session in weeks {
            session.type = newType
            session.needsTypeReview = false
            switch newType {
            case .tournament:
                session.eventName = leagueName
                session.leagueName = leagueName
                session.leagueEvent = event
            case .practice:
                session.eventName = nil
                session.leagueName = nil
                session.leagueEvent = nil
            case .league:
                break
            }
        }
        // Remove the now-orphaned league record so it stops showing as a league.
        if let existing { context.delete(existing) }
    }

    private func findOrCreateEvent(_ name: String, kind: LeagueEventKind) -> LeagueEvent {
        if let match = leagueEvents.first(where: { $0.kind == kind && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        let event = LeagueEvent()
        event.name = name
        event.kind = kind
        context.insert(event)
        return event
    }
}

// MARK: - League detail: every week grouped under one league

struct LeagueDetailView: View {
    let leagueName: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Query private var leagueEvents: [LeagueEvent]

    @State private var bowlingSession: Session?
    @State private var showingEdit = false
    @State private var showingMerge = false
    @State private var showingStats = false
    @State private var weekToDelete: Session?
    @State private var renameTarget: Session?
    @State private var renameText = ""

    private var event: LeagueEvent? {
        leagueEvents.first { $0.kind == .league && $0.name.caseInsensitiveCompare(leagueName) == .orderedSame }
    }

    /// Other league names this league could merge into.
    private var otherLeagueNames: [String] {
        var names: [String] = []
        var seen = Set<String>()
        for s in allSessions where s.type == .league {
            if let n = s.leagueName, !n.isEmpty,
               n.caseInsensitiveCompare(leagueName) != .orderedSame,
               seen.insert(n.lowercased()).inserted { names.append(n) }
        }
        for e in leagueEvents where e.kind == .league && !e.name.isEmpty
            && e.name.caseInsensitiveCompare(leagueName) != .orderedSame {
            if seen.insert(e.name.lowercased()).inserted { names.append(e.name) }
        }
        return names.sorted()
    }

    private var weeks: [Session] {
        allSessions.filter { session in
            session.type == .league
                && (session.leagueName ?? "").caseInsensitiveCompare(leagueName) == .orderedSame
        }
    }

    private var average: Double? {
        let scores = weeks.filter { !$0.isActive }.flatMap { $0.sortedGames }.map { $0.finalScore }.filter { $0 > 0 }
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    var body: some View {
        List {
            Section {
                headerCard
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))

            Section {
                Button {
                    addWeek()
                } label: {
                    Label("Add Week", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }

            if weeks.isEmpty {
                Section {
                    Text("No weeks yet — add the week you're bowling and score it.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMuted)
                }
            } else {
                Section("Weeks (\(weeks.count))") {
                    ForEach(weeks) { week in
                        Group {
                            if week.isActive {
                                // In-progress week — tap to resume live scoring.
                                Button { bowlingSession = week } label: { weekRow(week) }
                                    .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    SessionDetailView(session: week)
                                } label: {
                                    weekRow(week)
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                renameTarget = week
                                renameText = week.blockName ?? ""
                            } label: { Label("Rename", systemImage: "pencil") }
                            .tint(Theme.accent)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { weekToDelete = week } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(leagueName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingStats = true } label: { Image(systemName: "chart.bar") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingMerge = true
                    } label: {
                        Label("Merge into another league", systemImage: "arrow.triangle.merge")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingStats) {
            SessionStatsSheet(title: leagueName, sessions: weeks)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingEdit) {
            LeagueEditSheet(leagueName: leagueName, existing: event, onConverted: { dismiss() })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingMerge) {
            MergeGroupSheet(noun: "league", sourceName: leagueName, candidates: otherLeagueNames) { target in
                mergeLeague(into: target)
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $bowlingSession) { session in
            NavigationStack {
                LiveSessionView(session: session, onEnd: { bowlingSession = nil })
                    .navigationTitle("Week of \(session.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            // Leave mid-week without ending — resume from the Sessions list.
                            Button("Done for now") { bowlingSession = nil }
                        }
                    }
            }
        }
        .confirmationDialog(
            "Delete this week?",
            isPresented: Binding(get: { weekToDelete != nil }, set: { if !$0 { weekToDelete = nil } }),
            titleVisibility: .visible,
            presenting: weekToDelete
        ) { week in
            Button("Delete week", role: .destructive) {
                context.delete(week)
                weekToDelete = nil
            }
            Button("Cancel", role: .cancel) { weekToDelete = nil }
        } message: { _ in
            Text("Permanently removes this week and its games.")
        }
        .alert("Rename Week", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Week name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                renameTarget?.blockName = trimmed.isEmpty ? nil : trimmed
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                stat(average.map { Notation.oneDecimal($0) } ?? "—", "AVG")
                stat("\(weeks.count)", "Weeks")
                stat("\(event?.gamesPerWeek ?? 3)", "Games/wk")
            }
            if let start = event?.startDate {
                Text("Season started \(start.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.statNumber(24))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(Theme.statLabel)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func weekRow(_ week: Session) -> some View {
        let series = week.sortedGames.map { $0.finalScore }.reduce(0, +)
        let hasScores = week.sortedGames.contains { $0.finalScore > 0 }
        let named = !(week.blockName ?? "").isEmpty
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(named ? week.blockName! : week.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if named {
                    Text(week.date.formatted(.dateTime.month(.abbreviated).day()))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
                if week.isActive {
                    Badge(text: "In progress", color: Theme.warning)
                }
                Spacer()
                if hasScores {
                    Text("Series \(series)")
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(week.sortedGames.enumerated()), id: \.offset) { _, game in
                    Text("\(game.finalScore)")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                if week.sortedGames.isEmpty {
                    Text("No games").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Move every week of this league into `targetName` and drop this league's record.
    private func mergeLeague(into targetName: String) {
        let target = leagueEvents.first {
            $0.kind == .league && $0.name.caseInsensitiveCompare(targetName) == .orderedSame
        } ?? {
            let e = LeagueEvent()
            e.name = targetName
            e.kind = .league
            context.insert(e)
            return e
        }()
        for week in weeks {
            week.leagueName = targetName
            week.leagueEvent = target
        }
        if let event { context.delete(event) }
        dismiss()
    }

    private func addWeek() {
        // Resume an in-progress week instead of starting a duplicate.
        if let active = weeks.first(where: { $0.isActive }) {
            bowlingSession = active
            return
        }
        let session = Session()
        session.type = .league
        session.leagueName = leagueName
        session.leagueEvent = event
        session.date = Date()
        session.isActive = true
        // Carry forward the ball used in the most recent week, if any.
        session.todaysBallIDs = weeks.first?.todaysBallIDs ?? []
        context.insert(session)

        let game = Game()
        game.orderIndex = 0
        game.session = session
        game.ballID = weeks.first?.sortedGames.first?.ballID
        context.insert(game)

        bowlingSession = session
    }
}

// MARK: - Create a tournament (PRD 5.2: a container for one or more event blocks)

struct NewTournamentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Date()
    @State private var isSport = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. City Open)", text: $name)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Sport pattern", isOn: $isSport)
                } header: {
                    Text("Tournament")
                } footer: {
                    Text("Then open the tournament and add each event block (e.g. Qualifying, Match Play) as you bowl it.")
                }
            }
            .navigationTitle("New Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        let event = LeagueEvent()
                        event.name = name.trimmingCharacters(in: .whitespaces)
                        event.kind = .tournament
                        event.startDate = date
                        event.isSport = isSport
                        context.insert(event)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Tournament detail: every event block grouped under one tournament

struct TournamentDetailView: View {
    let tournamentName: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Query private var leagueEvents: [LeagueEvent]

    @State private var bowlingSession: Session?
    @State private var showingAddBlock = false
    @State private var newBlockName = ""
    @State private var showingEdit = false
    @State private var renameTarget: Session?
    @State private var renameText = ""
    @State private var blockToDelete: Session?
    @State private var showingMerge = false
    @State private var showingStats = false

    private var event: LeagueEvent? {
        leagueEvents.first { $0.kind == .tournament && $0.name.caseInsensitiveCompare(tournamentName) == .orderedSame }
    }

    /// Other tournament names this tournament could merge into.
    private var otherTournamentNames: [String] {
        var names: [String] = []
        var seen = Set<String>()
        for s in allSessions where s.type == .tournament {
            if let n = s.eventName ?? s.leagueName, !n.isEmpty,
               n.caseInsensitiveCompare(tournamentName) != .orderedSame,
               seen.insert(n.lowercased()).inserted { names.append(n) }
        }
        for e in leagueEvents where e.kind == .tournament && !e.name.isEmpty
            && e.name.caseInsensitiveCompare(tournamentName) != .orderedSame {
            if seen.insert(e.name.lowercased()).inserted { names.append(e.name) }
        }
        return names.sorted()
    }

    private var blocks: [Session] {
        allSessions.filter { session in
            session.type == .tournament
                && (session.eventName ?? session.leagueName ?? "").caseInsensitiveCompare(tournamentName) == .orderedSame
        }
    }

    private var average: Double? {
        let scores = blocks.filter { !$0.isActive }.flatMap { $0.sortedGames }.map { $0.finalScore }.filter { $0 > 0 }
        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    var body: some View {
        List {
            Section {
                headerCard
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))

            Section {
                Button {
                    showingAddBlock = true
                } label: {
                    Label("Add Event Block", systemImage: "plus.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }

            if blocks.isEmpty {
                Section {
                    Text("No blocks yet — add the event block you're bowling and score it.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textMuted)
                }
            } else {
                Section("Blocks (\(blocks.count))") {
                    ForEach(blocks) { block in
                        Group {
                            if block.isActive {
                                Button { bowlingSession = block } label: { blockRow(block) }
                                    .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    SessionDetailView(session: block)
                                } label: {
                                    blockRow(block)
                                }
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                renameTarget = block
                                renameText = block.blockName ?? ""
                            } label: { Label("Rename", systemImage: "pencil") }
                            .tint(Theme.accent)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { blockToDelete = block } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(tournamentName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingStats = true } label: { Image(systemName: "chart.bar") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingMerge = true
                    } label: {
                        Label("Merge into another tournament", systemImage: "arrow.triangle.merge")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingStats) {
            SessionStatsSheet(title: tournamentName, sessions: blocks)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingEdit) {
            TournamentEditSheet(tournamentName: tournamentName, existing: event, onConverted: { dismiss() })
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingMerge) {
            MergeGroupSheet(noun: "tournament", sourceName: tournamentName, candidates: otherTournamentNames) { target in
                mergeTournament(into: target)
            }
            .presentationDetents([.medium, .large])
        }
        .alert("New Event Block", isPresented: $showingAddBlock) {
            TextField("Block name (e.g. Qualifying)", text: $newBlockName)
            Button("Add & bowl") { addBlock() }
            Button("Cancel", role: .cancel) { newBlockName = "" }
        } message: {
            Text("Name this block, then score its games.")
        }
        .alert("Rename Block", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField("Block name", text: $renameText)
            Button("Save") {
                let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                renameTarget?.blockName = trimmed.isEmpty ? nil : trimmed
                renameTarget = nil
            }
            Button("Cancel", role: .cancel) { renameTarget = nil }
        }
        .confirmationDialog(
            "Delete this block?",
            isPresented: Binding(get: { blockToDelete != nil }, set: { if !$0 { blockToDelete = nil } }),
            titleVisibility: .visible,
            presenting: blockToDelete
        ) { block in
            Button("Delete block", role: .destructive) {
                context.delete(block)
                blockToDelete = nil
            }
            Button("Cancel", role: .cancel) { blockToDelete = nil }
        } message: { _ in
            Text("Permanently removes this block and its games.")
        }
        .fullScreenCover(item: $bowlingSession) { session in
            NavigationStack {
                LiveSessionView(session: session, onEnd: { bowlingSession = nil })
                    .navigationTitle(session.blockName?.isEmpty == false ? session.blockName! : "Event Block")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done for now") { bowlingSession = nil }
                        }
                    }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                stat(average.map { Notation.oneDecimal($0) } ?? "—", "AVG")
                stat("\(blocks.count)", "Blocks")
                stat("\(blocks.flatMap { $0.sortedGames }.count)", "Games")
            }
            if event?.isSport == true {
                Badge(text: "Sport pattern", color: Theme.warning)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.statNumber(24))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(Theme.statLabel)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func blockRow(_ block: Session) -> some View {
        let series = block.sortedGames.map { $0.finalScore }.reduce(0, +)
        let hasScores = block.sortedGames.contains { $0.finalScore > 0 }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(block.blockName?.isEmpty == false ? block.blockName! : "Event block")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(block.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                if block.isActive {
                    Badge(text: "In progress", color: Theme.warning)
                }
                Spacer()
                if hasScores {
                    Text("Series \(series)")
                        .font(.system(size: 14, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                }
            }
            HStack(spacing: 6) {
                ForEach(Array(block.sortedGames.enumerated()), id: \.offset) { _, game in
                    Text("\(game.finalScore)")
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                if block.sortedGames.isEmpty {
                    Text("No games").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Move every block of this tournament into `targetName` and drop this record.
    private func mergeTournament(into targetName: String) {
        let target = leagueEvents.first {
            $0.kind == .tournament && $0.name.caseInsensitiveCompare(targetName) == .orderedSame
        } ?? {
            let e = LeagueEvent()
            e.name = targetName
            e.kind = .tournament
            context.insert(e)
            return e
        }()
        for block in blocks {
            block.eventName = targetName
            block.leagueName = targetName
            block.leagueEvent = target
        }
        if let event { context.delete(event) }
        dismiss()
    }

    private func addBlock() {
        let trimmed = newBlockName.trimmingCharacters(in: .whitespaces)
        newBlockName = ""
        // Resume an in-progress block instead of starting a duplicate.
        if let active = blocks.first(where: { $0.isActive }) {
            bowlingSession = active
            return
        }
        let session = Session()
        session.type = .tournament
        session.eventName = tournamentName
        session.leagueName = tournamentName
        session.blockName = trimmed.isEmpty ? nil : trimmed
        session.leagueEvent = event
        session.date = Date()
        session.isActive = true
        session.todaysBallIDs = blocks.first?.todaysBallIDs ?? []
        context.insert(session)

        let game = Game()
        game.orderIndex = 0
        game.session = session
        game.ballID = blocks.first?.sortedGames.first?.ballID
        context.insert(game)

        bowlingSession = session
    }
}

/// Edit a tournament's sport flag, or convert the whole tournament (every block)
/// to a League or Practice — mirrors LeagueEditSheet.
struct TournamentEditSheet: View {
    let tournamentName: String
    let existing: LeagueEvent?
    /// Called after a conversion empties this tournament, so the detail view can pop.
    var onConverted: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Query private var leagueEvents: [LeagueEvent]

    @State private var type: SessionType = .tournament
    @State private var name = ""
    @State private var isSport = false

    /// The tournament's own blocks — what a conversion will re-tag.
    private var blocks: [Session] {
        allSessions.filter {
            $0.type == .tournament
                && ($0.eventName ?? $0.leagueName ?? "").caseInsensitiveCompare(tournamentName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(SessionType.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if type != .tournament {
                        Text("Converts all \(blocks.count) block\(blocks.count == 1 ? "" : "s") under \(tournamentName) to \(type.displayName)\(type == .league ? " (as weeks)" : "") and removes the tournament grouping. Scores are kept.")
                    }
                }

                if type == .tournament {
                    Section("Name") {
                        TextField("Tournament name", text: $name)
                    }
                    Section {
                        Toggle("Sport pattern", isOn: $isSport)
                    }
                } else if type == .league {
                    Section {
                        Toggle("Sport pattern league", isOn: $isSport)
                    }
                }
            }
            .navigationTitle(tournamentName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(type == .tournament ? "Save" : "Convert") { save() }
                }
            }
            .onAppear {
                name = tournamentName
                isSport = existing?.isSport ?? false
            }
        }
    }

    private func save() {
        if type == .tournament {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let newName = trimmed.isEmpty ? tournamentName : trimmed
            let renamed = newName.caseInsensitiveCompare(tournamentName) != .orderedSame

            let event = findOrCreateEvent(newName, kind: .tournament)
            event.isSport = isSport

            if renamed {
                // Re-tag every block to the new name (keeping each block's own name).
                for block in blocks {
                    block.eventName = newName
                    block.leagueName = newName
                    block.leagueEvent = event
                }
                if let existing, existing !== event { context.delete(existing) }
            }
            dismiss()
            if renamed { onConverted?() }   // detail's tournamentName is now stale → pop
        } else {
            convert(to: type)
            dismiss()
            onConverted?()
        }
    }

    /// Re-tag every block of this tournament to the new type and drop the tournament record.
    private func convert(to newType: SessionType) {
        let event: LeagueEvent? = newType == .league ? findOrCreateEvent(tournamentName, kind: .league) : nil
        event?.isSport = isSport
        for session in blocks {
            session.type = newType
            session.needsTypeReview = false
            session.blockName = nil
            switch newType {
            case .league:
                session.leagueName = tournamentName
                session.eventName = nil
                session.leagueEvent = event
            case .practice:
                session.leagueName = nil
                session.eventName = nil
                session.leagueEvent = nil
            case .tournament:
                break
            }
        }
        if let existing { context.delete(existing) }
    }

    private func findOrCreateEvent(_ name: String, kind: LeagueEventKind) -> LeagueEvent {
        if let match = leagueEvents.first(where: { $0.kind == kind && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        let event = LeagueEvent()
        event.name = name
        event.kind = kind
        context.insert(event)
        return event
    }
}

// MARK: - Merge a whole league / tournament into another (PRD 5.2)

/// Picks a destination league or tournament to absorb the current one.
struct MergeGroupSheet: View {
    let noun: String          // "league" or "tournament"
    let sourceName: String
    let candidates: [String]
    let onMerge: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmTarget: String?

    private var childWord: String { noun == "league" ? "weeks" : "blocks" }
    private var icon: String { noun == "league" ? "trophy.fill" : "flag.checkered" }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    EmptyStateView(
                        icon: "arrow.triangle.merge",
                        title: "No other \(noun)s",
                        message: "You need a second \(noun) to merge into."
                    )
                } else {
                    List {
                        Section {
                            Text("Moves every one of \(sourceName)'s \(childWord) into the \(noun) you pick. \(sourceName) is then removed. Scores are kept.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .listRowBackground(Color.clear)
                        }
                        Section("Merge into") {
                            ForEach(candidates, id: \.self) { name in
                                Button { confirmTarget = name } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: icon)
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.accent)
                                        Text(name).foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Merge \(noun.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog(
                "Merge into \(confirmTarget ?? "")?",
                isPresented: Binding(get: { confirmTarget != nil }, set: { if !$0 { confirmTarget = nil } }),
                titleVisibility: .visible,
                presenting: confirmTarget
            ) { target in
                Button("Merge") {
                    confirmTarget = nil
                    dismiss()
                    onMerge(target)
                }
                Button("Cancel", role: .cancel) { confirmTarget = nil }
            } message: { target in
                Text("\(sourceName)'s \(childWord) move into \(target).")
            }
        }
    }
}
