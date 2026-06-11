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
                Menu {
                    Picker("Session Type", selection: typeBinding) {
                        ForEach(SessionType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    DatePicker("Date", selection: $session.date, displayedComponents: .date)
                    if session.needsTypeReview {
                        Button("Mark type as reviewed") {
                            session.needsTypeReview = false
                        }
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

    private var typeBinding: Binding<SessionType> {
        Binding(
            get: { session.type },
            set: { newValue in
                session.type = newValue
                session.needsTypeReview = false
            }
        )
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
            if let location = session.location?.name {
                Text(location)
                    .font(Theme.cardSubtitle)
                    .foregroundStyle(Theme.textSecondary)
            }

            let scores = session.sortedGames.map { $0.finalScore }
            if !scores.isEmpty {
                HStack(spacing: 10) {
                    ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                        VStack(spacing: 2) {
                            Text("\(score)")
                                .font(Theme.statNumber(26))
                                .foregroundStyle(Theme.textPrimary)
                            Text("G\(index + 1)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    Spacer()
                    if scores.count > 1 {
                        VStack(spacing: 2) {
                            Text(Notation.oneDecimal(Double(scores.reduce(0, +)) / Double(scores.count)))
                                .font(Theme.statNumber(26))
                                .foregroundStyle(Theme.accent)
                            Text("AVG")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                }
                .padding(.top, 4)
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
            for frame in game.sortedFrames where frame.ballID != nil && frame.ballID != game.ballID {
                if let name = ballName(frame.ballID) {
                    rows.append(("G\(game.orderIndex + 1) · F\(frame.number)", name, frame.ballSwapReason))
                }
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
