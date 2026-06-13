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
            let league = existing ?? findOrCreateEvent(leagueName, kind: .league)
            league.startDate = hasStartDate ? startDate : nil
            league.gamesPerWeek = gamesPerWeek
            league.isSport = isSport
            dismiss()
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

    private var event: LeagueEvent? {
        leagueEvents.first { $0.kind == .league && $0.name.caseInsensitiveCompare(leagueName) == .orderedSame }
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
                    .onDelete { offsets in
                        for index in offsets { context.delete(weeks[index]) }
                    }
                }
            }
        }
        .navigationTitle(leagueName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            LeagueEditSheet(leagueName: leagueName, existing: event, onConverted: { dismiss() })
                .presentationDetents([.medium])
        }
        .fullScreenCover(item: $bowlingSession) { session in
            NavigationStack {
                LiveSessionView(session: session, onEnd: { bowlingSession = nil })
                    .navigationTitle("Week of \(session.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            // Leave mid-week without ending — resume from the Bowl tab.
                            Button("Done for now") { bowlingSession = nil }
                        }
                    }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                stat(average.map { Notation.oneDecimal($0) } ?? "—", "Average")
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(week.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if week.isActive {
                    Badge(text: "In progress", color: Theme.warning)
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
