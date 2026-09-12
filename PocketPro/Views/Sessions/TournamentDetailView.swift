import SwiftUI
import SwiftData
import PocketProCore

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
    @State private var showingDeleteConfirm = false
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
        .toolbar { toolbarContent }
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
        .confirmationDialog("Delete \(tournamentName)?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete tournament & all blocks", role: .destructive) { deleteTournament() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently removes \(tournamentName) and every event block and game in it. To keep it for stats but hide it, use Archive from the Sessions list instead.")
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
                    Label("Merge into another tournament", systemImage: "arrow.triangle.merge")
                }
                Divider()
                Button(role: .destructive) {
                    showingDeleteConfirm = true
                } label: {
                    Label("Delete Tournament", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    /// Delete this whole tournament — every block and its games, plus the record —
    /// then pop back to the Sessions list.
    private func deleteTournament() {
        for block in blocks { context.delete(block) }
        if let event { context.delete(event) }
        dismiss()
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
