import SwiftUI
import SwiftData
import PocketProCore

/// Session detail (PRD 5.2): game breakdown, frame review, Lane Play Log,
/// ball log, pattern info, spare summary, inline-editable note.
struct SessionDetailView: View {
    @Bindable var session: Session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var allBalls: [Ball]

    @State private var noteFrame: Frame?
    @State private var showingDeleteConfirm = false
    @State private var showingEdit = false
    @State private var showingMerge = false
    @State private var showingStats = false
    @State private var resumeGame = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                ForEach(session.sortedGames) { game in
                    gameCard(game)
                }

                lanePlayLog
                ballLog
                patternCard
                spareSummary
                noteCard
            }
            .padding()
        }
        .background(Theme.bgPrimary)
        .navigationTitle(session.date.formatted(.dateTime.month(.abbreviated).day()))
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
                        addGame()
                    } label: {
                        Label("Add a game", systemImage: "plus")
                    }
                    if session.needsTypeReview {
                        Button("Mark type as reviewed") {
                            session.needsTypeReview = false
                        }
                    }
                    Button {
                        showingMerge = true
                    } label: {
                        Label("Merge into another session", systemImage: "arrow.triangle.merge")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Session", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingStats) {
            SessionStatsSheet(title: session.title, sessions: [session])
                .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $resumeGame) {
            NavigationStack {
                LiveSessionView(session: session, onEnd: { resumeGame = false })
                    .navigationTitle(session.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done for now") { resumeGame = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingEdit) {
            SessionEditSheet(session: session)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingMerge) {
            MergeSessionSheet(source: session) { target in
                merge(into: target)
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete this session?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete session", role: .destructive) {
                context.delete(session)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Permanently removes this session and its games.")
        }
        .sheet(item: $noteFrame) { frame in
            FrameNoteSheet(frame: frame)
                .presentationDetents([.medium, .large])
        }
    }

    /// Re-open the session for another game (e.g. after accidentally ending it) and
    /// jump into live scoring. Ending the game flips it back to completed.
    private func addGame() {
        session.isActive = true
        let next = Game()
        next.orderIndex = (session.sortedGames.map { $0.orderIndex }.max() ?? -1) + 1
        next.session = session
        next.ballID = session.sortedGames.last?.ballID
        context.insert(next)
        resumeGame = true
    }

    /// Move this session's games into `target` (appended after its games) and remove
    /// this session (PRD 5.2 merge). Games keep their frames via the cascade inverse.
    private func merge(into target: Session) {
        let base = (target.sortedGames.map { $0.orderIndex }.max() ?? -1) + 1
        for (offset, game) in session.sortedGames.enumerated() {
            game.session = target
            game.orderIndex = base + offset
        }
        context.delete(session)
        dismiss()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Badge(text: session.type.displayName, color: Theme.sessionTypeColor(session.type))
                if session.needsTypeReview {
                    Badge(text: "Re-tag?", color: Theme.warning)
                }
                Spacer()
                Text(session.date, format: .dateTime.weekday(.wide).month().day().year())
                    .font(Theme.cardSubtitle)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(session.title)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            if let block = session.blockName, !block.isEmpty {
                Text(block)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            if let location = session.location?.name {
                Text(location)
                    .font(Theme.cardSubtitle)
                    .foregroundStyle(Theme.textSecondary)
            }

            let scores = session.sortedGames.map { $0.finalScore }
            if !scores.isEmpty {
                // Wrap to multiple rows so 7–12 games stay tidy instead of overflowing.
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 12)], alignment: .leading, spacing: 8) {
                    ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                        VStack(spacing: 2) {
                            Text("\(score)")
                                .font(Theme.statNumber(24))
                                .foregroundStyle(Theme.textPrimary)
                            Text("G\(index + 1)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textMuted)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 4)
                if scores.count > 1 {
                    HStack(spacing: 6) {
                        Text("SERIES")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textMuted)
                        Text("\(scores.reduce(0, +))")
                            .font(.system(size: 17, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                        Text("· avg \(Notation.oneDecimal(Double(scores.reduce(0, +)) / Double(scores.count))) · high \(scores.max() ?? 0)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }

    private func gameCard(_ game: Game) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Game \(game.orderIndex + 1)")
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if !game.hasFrameData {
                    Badge(text: "Score only", color: Theme.textMuted)
                }
                Text("\(game.finalScore)")
                    .font(.system(size: 19, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            if game.hasFrameData {
                FrameStripView(game: game, highlightCurrent: false, onLongPressFrame: { frame in
                    noteFrame = frame
                }, onTapFrame: { frame in
                    noteFrame = frame
                })
                Text("Tap a frame to review or edit its note")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .card()
    }

    // MARK: Lane Play Log (PRD 5.2: aggregate of frame board/breakpoint data)

    private var lanePlayEntries: [(game: Game, frame: Frame)] {
        session.sortedGames.flatMap { game in
            game.sortedFrames.filter { $0.hasLanePlayData }.map { (game, $0) }
        }
    }

    @ViewBuilder
    private var lanePlayLog: some View {
        if !lanePlayEntries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Lane Play Log")
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                    GridRow {
                        Text("Frame").gridColumnAlignment(.leading)
                        Text("Target")
                        Text("Hit")
                        Text("Break")
                        Text("Dist")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                    ForEach(Array(lanePlayEntries.enumerated()), id: \.offset) { _, entry in
                        GridRow {
                            Text("G\(entry.game.orderIndex + 1) · F\(entry.frame.number)")
                                .foregroundStyle(Theme.textSecondary)
                            boardText(entry.frame.targetBoard)
                            boardText(entry.frame.boardHit, compare: entry.frame.targetBoard)
                            boardText(entry.frame.breakpointBoard)
                            Text(entry.frame.breakpointDistanceFt.map { "\(Int($0)) ft" } ?? "—")
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .font(.system(size: 13).monospacedDigit())
                    }
                }
            }
            .card()
        }
    }

    private func boardText(_ board: Int?, compare target: Int? = nil) -> some View {
        let missed = board != nil && target != nil && board != target
        return Text(board.map(String.init) ?? "—")
            .foregroundStyle(missed ? Theme.warning : Theme.textPrimary)
    }

    // MARK: Ball log (PRD 5.2: ball per game, swaps with reason)

    @ViewBuilder
    private var ballLog: some View {
        let entries = ballLogEntries
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ball Log")
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    HStack(spacing: 8) {
                        Text(entry.0)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 64, alignment: .leading)
                        Text(entry.1)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        if let reason = entry.2 {
                            Text("— \(reason)")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                    }
                }
            }
            .card()
        }
    }

    private func ballName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return allBalls.first { $0.id == id }?.displayName
    }

    private var ballLogEntries: [(String, String, String?)] {
        var rows: [(String, String, String?)] = []
        for game in session.sortedGames {
            if let name = ballName(game.ballID) {
                rows.append(("G\(game.orderIndex + 1)", name, nil))
            }
            // Each frame carries its own ball; log only the frames where it changed.
            var previous = game.ballID
            for frame in game.sortedFrames {
                guard let ballID = frame.ballID, ballID != previous else { continue }
                if let name = ballName(ballID) {
                    rows.append(("G\(game.orderIndex + 1) · F\(frame.number)", name, frame.ballSwapReason))
                }
                previous = ballID
            }
        }
        return rows
    }

    @ViewBuilder
    private var patternCard: some View {
        if let pattern = session.pattern {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Pattern")
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    if pattern.needsTypeReview {
                        Badge(text: "Review type", color: Theme.warning)
                    }
                    Spacer()
                }
                Text(pattern.name.isEmpty ? pattern.type.displayName : pattern.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(pattern.summary)
                    .font(Theme.cardSubtitle)
                    .foregroundStyle(Theme.textSecondary)
            }
            .card()
        }
    }

    // MARK: Spare summary (PRD 5.2: leaves, conversion %, flagged misses)

    @ViewBuilder
    private var spareSummary: some View {
        let leaves = session.sortedGames.flatMap { $0.derivedLeaves() }
        if !leaves.isEmpty {
            let opportunities = leaves.filter { $0.hadOpportunity }
            let converted = opportunities.filter { $0.converted }
            let percent = opportunities.isEmpty ? nil : Double(converted.count) / Double(opportunities.count) * 100

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Spares")
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(Notation.percent(percent))
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.conversionColor(percent))
                }
                ForEach(Array(leaves.enumerated()), id: \.offset) { _, leave in
                    HStack(spacing: 10) {
                        PinDiagram(standing: leave.pins, size: 34)
                        Text(leave.classification.displayTitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Badge(
                            text: leave.primary.displayName,
                            color: leave.categories.contains(.split) ? Theme.destructive : Theme.textMuted,
                            filled: false
                        )
                        Spacer()
                        if leave.hadOpportunity {
                            Image(systemName: leave.converted ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(leave.converted ? Theme.success : Theme.destructive)
                        } else {
                            Text("fill")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
            }
            .card()
        }
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Session Note")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            TextField("Add a note", text: $session.notes, axis: .vertical)
                .lineLimit(2...8)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .card()
    }
}

/// Edit a session's type, league/tournament name, and date (PRD 5.2).
struct SessionEditSheet: View {
    @Bindable var session: Session
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var leagueEvents: [LeagueEvent]
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]

    @State private var type: SessionType = .league
    @State private var name = ""
    @State private var date = Date()
    @State private var isSport = false
    @State private var blockName = ""

    private var nameSuggestions: [String] {
        guard type == .league || type == .tournament else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for s in allSessions where s.type == type {
            if let n = s.leagueName ?? s.eventName, !n.isEmpty, seen.insert(n.lowercased()).inserted { out.append(n) }
        }
        for e in leagueEvents where e.kind.sessionType == type && !e.name.isEmpty {
            if seen.insert(e.name.lowercased()).inserted { out.append(e.name) }
        }
        return out.sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(SessionType.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                }
                if type == .tournament {
                    Section("Event Block") {
                        TextField("Block name (e.g. Qualifying)", text: $blockName)
                    }
                }
                if type == .league || type == .tournament {
                    Section(type == .league ? "League" : "Tournament") {
                        TextField("Name", text: $name)
                        Toggle("Sport pattern", isOn: $isSport)
                        ForEach(nameSuggestions, id: \.self) { suggestion in
                            Button {
                                name = suggestion
                            } label: {
                                HStack {
                                    Text(suggestion).foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    if name.caseInsensitiveCompare(suggestion) == .orderedSame {
                                        Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Save") { save() } }
            }
            .onAppear {
                type = session.type
                name = session.leagueName ?? session.eventName ?? ""
                date = session.date
                isSport = session.leagueEvent?.isSport ?? false
                blockName = session.blockName ?? ""
            }
        }
    }

    private func save() {
        session.type = type
        session.date = date
        session.needsTypeReview = false
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        switch type {
        case .league:
            session.leagueName = trimmed.isEmpty ? nil : trimmed
            session.eventName = nil
            let event = trimmed.isEmpty ? nil : findOrCreateEvent(trimmed, kind: .league)
            event?.isSport = isSport
            session.leagueEvent = event
            session.blockName = nil
        case .tournament:
            session.eventName = trimmed.isEmpty ? nil : trimmed
            session.leagueName = trimmed.isEmpty ? nil : trimmed
            let event = trimmed.isEmpty ? nil : findOrCreateEvent(trimmed, kind: .tournament)
            event?.isSport = isSport
            session.leagueEvent = event
            let block = blockName.trimmingCharacters(in: .whitespaces)
            session.blockName = block.isEmpty ? nil : block
        case .practice:
            session.leagueName = nil
            session.eventName = nil
            session.leagueEvent = nil
            session.blockName = nil
        }
        dismiss()
    }

    private func findOrCreateEvent(_ name: String, kind: LeagueEventKind) -> LeagueEvent {
        if let existing = leagueEvents.first(where: { $0.kind == kind && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let event = LeagueEvent()
        event.name = name
        event.kind = kind
        context.insert(event)
        return event
    }
}

/// Pick a destination session to merge the current one into (PRD 5.2).
struct MergeSessionSheet: View {
    let source: Session
    let onMerge: (Session) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @State private var confirmTarget: Session?

    private var candidates: [Session] {
        allSessions.filter { !$0.isActive && $0.id != source.id }
    }

    private var gameCount: Int { source.sortedGames.count }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    EmptyStateView(
                        icon: "arrow.triangle.merge",
                        title: "No other sessions",
                        message: "You need a second completed session to merge into."
                    )
                } else {
                    List {
                        Section {
                            Text("Move all \(gameCount) game\(gameCount == 1 ? "" : "s") from this session into the one you pick. This session is then removed.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .listRowBackground(Color.clear)
                        }
                        Section("Merge into") {
                            ForEach(candidates) { target in
                                Button {
                                    confirmTarget = target
                                } label: {
                                    mergeRow(target)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Merge Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog(
                "Merge into \(confirmTarget?.title ?? "session")?",
                isPresented: Binding(get: { confirmTarget != nil }, set: { if !$0 { confirmTarget = nil } }),
                titleVisibility: .visible,
                presenting: confirmTarget
            ) { target in
                Button("Merge \(gameCount) game\(gameCount == 1 ? "" : "s")") {
                    confirmTarget = nil
                    dismiss()
                    onMerge(target)
                }
                Button("Cancel", role: .cancel) { confirmTarget = nil }
            } message: { target in
                Text("Games join \(target.title) and this session is removed. Scores are kept.")
            }
        }
    }

    private func mergeRow(_ target: Session) -> some View {
        HStack(spacing: 10) {
            Badge(text: target.type.displayName, color: Theme.sessionTypeColor(target.type))
            VStack(alignment: .leading, spacing: 2) {
                Text(target.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(target.date.formatted(.dateTime.month(.abbreviated).day().year())) · \(target.sortedGames.count) game\(target.sortedGames.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }
}
