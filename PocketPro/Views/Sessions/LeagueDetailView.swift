import SwiftUI
import SwiftData
import PocketProCore

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
    @State private var showingDeleteConfirm = false
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
        .toolbar { toolbarContent }
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
        .confirmationDialog("Delete \(leagueName)?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete league & all weeks", role: .destructive) { deleteLeague() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently removes \(leagueName) and every week and game in it. To keep it for stats but hide it, use Archive from the Sessions list instead.")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
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
                Divider()
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete League", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    /// Delete this whole league — every week and its games, plus the league record —
    /// then pop back to the Sessions list.
    private func deleteLeague() {
        for week in weeks { context.delete(week) }
        if let event { context.delete(event) }
        dismiss()
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
