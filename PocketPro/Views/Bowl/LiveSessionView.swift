import SwiftUI
import SwiftData
import PocketProCore

/// Live scoring for the active session (PRD 5.1). Entry controls live in the lower
/// two-thirds of the screen for one-handed use at the lanes (PRD 7.5).
struct LiveSessionView: View {
    @Bindable var session: Session
    /// Called when the session ends — lets a presenting flow (e.g. a league week)
    /// dismiss itself. nil on the Bowl tab, where the session just leaves the view.
    var onEnd: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.scoreEntryMode) private var entryModeRaw = ScoreEntryMode.pinDeck.rawValue
    @Query(filter: #Predicate<Ball> { $0.active }) private var arsenal: [Ball]

    @State private var standingSelection = PinSet.empty
    @State private var showingEndOfGame = false
    @State private var showingBallSwap = false
    @State private var showingSessionNote = false
    @State private var noteFrame: Frame?
    @State private var endedGame: Game?
    /// Frame being re-entered directly (tap a frame to edit it). Its existing
    /// balls are replaced only when the first new ball is committed.
    @State private var editingFrameNumber: Int?

    private var entryMode: ScoreEntryMode {
        ScoreEntryMode(rawValue: entryModeRaw) ?? .pinDeck
    }

    private var game: Game? {
        session.sortedGames.last
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sessionHeader

                if let game {
                    FrameStripView(game: game, editingFrameNumber: editingFrameNumber, onLongPressFrame: { frame in
                        noteFrame = frame
                    }, onTapFrame: { frame in
                        beginEditing(frame)
                    })

                    ballChip(game: game)

                    if game.isComplete {
                        completedGamePrompt(game: game)
                    } else {
                        entryArea(game: game)
                    }
                }
            }
            .padding()
        }
        .background(Theme.bgPrimary)
        .sheet(isPresented: $showingEndOfGame, onDismiss: { endedGame = nil }) {
            if let endedGame {
                EndOfGameCard(session: session, game: endedGame, onAnotherGame: startAnotherGame, onDone: endSession)
                    .presentationDetents([.large])
                    .interactiveDismissDisabled()
            }
        }
        .sheet(isPresented: $showingBallSwap) {
            BallSwapSheet(session: session, game: game, arsenal: arsenal)
                .presentationDetents([.medium])
        }
        .sheet(item: $noteFrame) { frame in
            FrameNoteSheet(frame: frame)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingSessionNote) {
            NavigationStack {
                Form {
                    TextField("How are the lanes playing?", text: $session.notes, axis: .vertical)
                        .lineLimit(4...10)
                }
                .navigationTitle("Session Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showingSessionNote = false }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Header

    private var sessionHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Badge(text: session.type.displayName, color: Theme.sessionTypeColor(session.type))
                    if let pattern = session.pattern {
                        Text(pattern.name.isEmpty ? pattern.summary : pattern.name)
                            .font(Theme.cardSubtitle)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Text(session.title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Game \(session.sortedGames.count)")
                    .font(Theme.cardSubtitle)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            // One-tap session note (PRD 7.5).
            Button {
                showingSessionNote = true
            } label: {
                Image(systemName: session.notes.isEmpty ? "square.and.pencil" : "note.text")
                    .font(.system(size: 20))
                    .foregroundStyle(session.notes.isEmpty ? Theme.textSecondary : Theme.warning)
            }
            Menu {
                Button("End Session", role: .destructive) {
                    endSession()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Ball chip (PRD 5.1: tap to log a mid-game ball change)

    private func ballChip(game: Game) -> some View {
        Button {
            showingBallSwap = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.coverstockColor(currentBall(game: game)?.coverstockType))
                Text(currentBall(game: game)?.displayName ?? "Select ball")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(Theme.bgElevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func currentBall(game: Game) -> Ball? {
        let currentID = game.sortedFrames.compactMap { $0.ballID }.last ?? game.ballID
        return arsenal.first { $0.id == currentID }
    }

    // MARK: - Entry

    private struct EntryContext {
        var frameIndex: Int
        var ballIndex: Int
        var rack: PinSet?
    }

    /// Where the next ball goes and what rack it faces. `rack` is nil when pin
    /// identity is unavailable (prior ball entered without pin data).
    private func entryContext(game: Game) -> EntryContext {
        let frames = game.sortedFrames
        // Editing a tapped frame: re-enter it from ball 1 on a full rack.
        if let editing = editingFrameNumber, frames.contains(where: { $0.number == editing }) {
            return EntryContext(frameIndex: editing - 1, ballIndex: 0, rack: .full)
        }
        for frame in frames {
            let index = frame.number - 1
            if !ScoringEngine.isFrameComplete(balls: frame.counts, frameIndex: index) {
                let balls = frame.balls
                if index < 9 {
                    if balls.isEmpty {
                        return EntryContext(frameIndex: index, ballIndex: 0, rack: .full)
                    }
                    let rack = balls[0].standingAfterMask.map { PinSet(mask: $0) }
                    return EntryContext(frameIndex: index, ballIndex: 1, rack: rack)
                }
                // Tenth frame rack walk.
                switch balls.count {
                case 0:
                    return EntryContext(frameIndex: 9, ballIndex: 0, rack: .full)
                case 1:
                    if balls[0].count == 10 {
                        return EntryContext(frameIndex: 9, ballIndex: 1, rack: .full)
                    }
                    return EntryContext(frameIndex: 9, ballIndex: 1, rack: balls[0].standingAfterMask.map { PinSet(mask: $0) })
                default:
                    if balls[0].count == 10 {
                        if balls[1].count == 10 {
                            return EntryContext(frameIndex: 9, ballIndex: 2, rack: .full)
                        }
                        return EntryContext(frameIndex: 9, ballIndex: 2, rack: balls[1].standingAfterMask.map { PinSet(mask: $0) })
                    }
                    // Spare made → fresh rack for the fill ball.
                    return EntryContext(frameIndex: 9, ballIndex: 2, rack: .full)
                }
            }
        }
        return EntryContext(frameIndex: frames.count, ballIndex: 0, rack: .full)
    }

    @ViewBuilder
    private func entryArea(game: Game) -> some View {
        let entry = entryContext(game: game)

        VStack(spacing: 12) {
            HStack {
                Text("Frame \(entry.frameIndex + 1) · Ball \(entry.ballIndex + 1)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                if editingFrameNumber != nil {
                    Button {
                        editingFrameNumber = nil
                        standingSelection = .empty
                    } label: {
                        Label("Cancel edit", systemImage: "xmark")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.warning)
                } else if canUndo(game: game) {
                    Button {
                        undoLastBall(game: game)
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                }
            }

            if entryMode == .pinDeck, let rack = entry.rack {
                PinDeckView(available: rack, standingAfter: $standingSelection)
                    .frame(maxWidth: 340)
                    .frame(maxWidth: .infinity)

                Button {
                    commitPinBall(game: game, entry: entry, rack: rack)
                } label: {
                    Text(pinCommitLabel(entry: entry, rack: rack))
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(standingSelection.isEmpty ? Theme.success : Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            } else {
                DirectEntryPad(maxPins: maxPins(game: game, entry: entry)) { count in
                    commitCountBall(game: game, entry: entry, count: count)
                }
            }
        }
        .card()
    }

    private func pinCommitLabel(entry: EntryContext, rack: PinSet) -> String {
        let knocked = rack.count - standingSelection.count
        if standingSelection.isEmpty {
            if rack.count == 10 { return "Strike  ✕" }
            return entry.ballIndex >= 1 ? "Spare  /" : "All 10 — \(knocked)"
        }
        return "\(knocked) down · \(standingSelection.count) standing"
    }

    private func maxPins(game: Game, entry: EntryContext) -> Int {
        if let rack = entry.rack { return rack.count }
        let frames = game.sortedFrames
        if let frame = frames.first(where: { $0.number - 1 == entry.frameIndex }) {
            return ScoringEngine.maxPinsForNextBall(balls: frame.counts, frameIndex: entry.frameIndex)
        }
        return 10
    }

    // MARK: - Commits

    private func frameForEntry(game: Game, entry: EntryContext) -> Frame {
        if let existing = game.sortedFrames.first(where: { $0.number - 1 == entry.frameIndex }) {
            return existing
        }
        let frame = Frame()
        frame.number = entry.frameIndex + 1
        frame.game = game
        context.insert(frame)
        return frame
    }

    private func commitPinBall(game: Game, entry: EntryContext, rack: PinSet) {
        let standing = standingSelection
        let count = rack.count - standing.count
        let frame = frameForEntry(game: game, entry: entry)
        clearForEditIfNeeded(frame)
        frame.balls.append(BallEntry(count: count, standingAfterMask: standing.mask))
        standingSelection = .empty
        afterCommit(game: game)
    }

    private func commitCountBall(game: Game, entry: EntryContext, count: Int) {
        let frame = frameForEntry(game: game, entry: entry)
        clearForEditIfNeeded(frame)
        frame.balls.append(BallEntry(count: count, standingAfterMask: nil))
        afterCommit(game: game)
    }

    /// Tap a frame to re-enter it; its old balls are wiped only when the first
    /// replacement ball is committed, so tapping by mistake costs nothing.
    private func beginEditing(_ frame: Frame) {
        guard !frame.balls.isEmpty else { return }
        editingFrameNumber = frame.number
        standingSelection = .empty
    }

    private func clearForEditIfNeeded(_ frame: Frame) {
        guard editingFrameNumber == frame.number else { return }
        frame.balls.removeAll()
        editingFrameNumber = nil
    }

    private func afterCommit(game: Game) {
        if game.isComplete {
            endedGame = game
            showingEndOfGame = true
        }
    }

    private func canUndo(game: Game) -> Bool {
        game.sortedFrames.contains { !$0.balls.isEmpty }
    }

    private func undoLastBall(game: Game) {
        guard let lastFrame = game.sortedFrames.last(where: { !$0.balls.isEmpty }) else { return }
        lastFrame.balls.removeLast()
        if lastFrame.balls.isEmpty && lastFrame.number > 1 {
            context.delete(lastFrame)
        }
        standingSelection = .empty
    }

    // MARK: - Game lifecycle

    private func completedGamePrompt(game: Game) -> some View {
        VStack(spacing: 12) {
            Text("Game \(game.orderIndex + 1) complete — \(game.finalScore)")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 12) {
                Button {
                    startAnotherGame()
                } label: {
                    Text("Bowl another game")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Theme.accent)
                        .clipShape(Capsule())
                }
                Button {
                    endSession()
                } label: {
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Theme.bgElevated)
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity)
        .card()
    }

    private func startAnotherGame() {
        guard let last = game else { return }
        let next = Game()
        next.orderIndex = last.orderIndex + 1
        next.session = session
        next.ballID = last.sortedFrames.compactMap { $0.ballID }.last ?? last.ballID
        context.insert(next)
        showingEndOfGame = false
        endedGame = nil
    }

    private func endSession() {
        // Drop a trailing game that never started.
        if let last = session.sortedGames.last, last.sortedFrames.allSatisfy({ $0.balls.isEmpty }) {
            context.delete(last)
        }
        session.isActive = false
        showingEndOfGame = false
        endedGame = nil
        onEnd?()
    }
}

// MARK: - Direct-score entry pad (PRD 5.1 settings toggle)

struct DirectEntryPad: View {
    let maxPins: Int
    let onCommit: (Int) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(0...10, id: \.self) { count in
                Button {
                    onCommit(count)
                } label: {
                    Text(count == 10 ? "X" : "\(count)")
                        .font(.system(size: 19, weight: .bold).monospacedDigit())
                        .foregroundStyle(count <= maxPins ? Theme.textPrimary : Theme.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(count > maxPins)
            }
        }
    }
}
