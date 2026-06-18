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
    @State private var showingSessionStats = false
    @State private var noteFrame: Frame?
    @State private var endedGame: Game?
    /// Tapped frame whose individual shots are being chosen for editing. Picking a
    /// shot re-enters from that ball, keeping the earlier balls in the frame.
    @State private var editingFrame: Frame?
    /// Which shot of `editingFrame` is being re-entered (nil = still on the picker).
    @State private var editingBallIndex: Int?
    /// Snapshot of the frame's balls before editing, restored by Back/Cancel.
    @State private var editingBackup: [BallEntry] = []
    /// The ball in hand for forward entry — what the chip shows and new frames inherit.
    /// Editing a past frame's ball doesn't change this.
    @State private var liveBallID: UUID?

    private var entryMode: ScoreEntryMode {
        ScoreEntryMode(rawValue: entryModeRaw) ?? .pinDeck
    }

    private var game: Game? {
        session.sortedGames.last
    }

    /// Completed games in this session/block, for the running series total.
    private var completedGames: [Game] {
        session.sortedGames.filter { $0.isComplete }
    }
    private var seriesTotal: Int {
        completedGames.map { $0.finalScore }.reduce(0, +)
    }

    var body: some View {
        // No ScrollView — the entry deck scales to the device's height so the commit
        // button is always visible without scrolling, on any iPhone (PRD 7.5).
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 10) {
                sessionHeader

                if let game {
                    FrameStripView(game: game, editingFrameNumber: editingFrame?.number, onLongPressFrame: { frame in
                        noteFrame = frame
                    }, onTapFrame: { frame in
                        // Switch which frame you're editing — or return to live entry by
                        // tapping the current frame — without cancelling first.
                        let currentIndex = entryContext(game: game).frameIndex
                        if editingFrame != nil { cancelEdit() }
                        if frame.number - 1 != currentIndex { beginEditing(frame) }
                    })

                    HStack(spacing: 8) {
                        ballChip(game: game)
                        Spacer()
                        if !game.isComplete {
                            Text("Max \(ScoringEngine.maxPossibleScore(frames: game.frameCounts))")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Theme.textMuted)
                        }
                    }

                    Spacer(minLength: 6)

                    if game.isComplete {
                        completedGamePrompt(game: game)
                    } else if let editing = editingFrame, editingBallIndex == nil {
                        editShotPicker(editing)
                    } else {
                        entryArea(game: game, availableHeight: geo.size.height)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Theme.bgPrimary)
        .onAppear { syncLiveBall(game: game) }
        .onChange(of: game?.id) { syncLiveBall(game: game) }
        .sheet(isPresented: $showingEndOfGame, onDismiss: { endedGame = nil }) {
            if let endedGame {
                EndOfGameCard(session: session, game: endedGame, onAnotherGame: startAnotherGame, onDone: endSession)
                    .presentationDetents([.large])
                    .interactiveDismissDisabled()
            }
        }
        .sheet(isPresented: $showingBallSwap) {
            BallSwapSheet(session: session, arsenal: arsenal) { ball, reason in
                applyBallSelection(ball: ball, reason: reason)
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingSessionStats) {
            SessionStatsSheet(session: session)
                .presentationDetents([.large])
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
                HStack(spacing: 8) {
                    Text("Game \(session.sortedGames.count)")
                        .font(Theme.cardSubtitle)
                        .foregroundStyle(Theme.textSecondary)
                    if !completedGames.isEmpty {
                        Text("Series \(seriesTotal)")
                            .font(.system(size: 13, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                        Text("· \(completedGames.count) game\(completedGames.count == 1 ? "" : "s")")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
            Spacer()
            // View this session/block's stats so far.
            Button {
                showingSessionStats = true
            } label: {
                Image(systemName: "chart.bar")
                    .font(.system(size: 19))
                    .foregroundStyle(Theme.textSecondary)
            }
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
                    .foregroundStyle(Theme.coverstockColor(chipBall(game: game)?.coverstockType))
                Text(chipBall(game: game)?.displayName ?? "Select ball")
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

    /// The ball shown on the chip — the one assigned to the frame currently being
    /// entered or edited (each frame carries its own ball).
    private func chipBall(game: Game) -> Ball? {
        let id = chipBallID(game: game)
        return arsenal.first { $0.id == id }
    }

    private func chipBallID(game: Game) -> UUID? {
        if let editing = editingFrame { return editing.ballID ?? liveBallID ?? game.ballID }
        return liveBallID ?? game.ballID
    }

    /// Seed the live ball from the game on appear / when a new game starts: the ball
    /// last used in this game, else the game's starting ball.
    private func syncLiveBall(game: Game?) {
        guard let game else { return }
        liveBallID = game.sortedFrames.last?.ballID ?? game.ballID
    }

    /// Apply a ball pick from the swap sheet. Editing a past frame changes only that
    /// frame; otherwise it becomes the live ball and applies to the current frame.
    private func applyBallSelection(ball: Ball, reason: String) {
        guard let game else { return }
        if let editing = editingFrame {
            editing.ballID = ball.id
            editing.ballSwapReason = reason.isEmpty ? nil : reason
            return
        }
        liveBallID = ball.id
        if game.ballID == nil { game.ballID = ball.id }
        let entry = entryContext(game: game)
        if let frame = game.sortedFrames.first(where: { $0.number - 1 == entry.frameIndex }) {
            frame.ballID = ball.id
            frame.ballSwapReason = reason.isEmpty ? nil : reason
        }
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
    private func entryArea(game: Game, availableHeight: CGFloat) -> some View {
        let entry = entryContext(game: game)
        // Re-seed the deck whenever we move to a new ball (see seedSelection).
        let entryKey = "\(entry.frameIndex):\(entry.ballIndex)"
        // Size the pin deck to whatever vertical space is left after the fixed chrome,
        // so it shrinks on small phones and never pushes the commit button off-screen.
        let deckHeight = max(150, min(240, availableHeight - 400))

        VStack(spacing: 10) {
            HStack {
                Text("\(editingFrame != nil ? "Editing " : "")Frame \(entry.frameIndex + 1) · Ball \(entry.ballIndex + 1)")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(editingFrame != nil ? Theme.accent : Theme.textSecondary)
                Spacer()
                if editingFrame != nil {
                    Button {
                        backToPicker()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    Button {
                        cancelEdit()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
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
                // A partial leave carries over highlighted (tap the pins you knocked down);
                // a full fresh rack behaves like a first ball (tap the pins left standing).
                let knockDown = rack.count < 10

                PinDeckView(available: rack, standingAfter: $standingSelection)
                    .frame(maxWidth: 340, maxHeight: deckHeight)
                    .frame(maxWidth: .infinity)

                Text(knockDown ? "Tap the standing pins you knocked down" : "Tap the pins left standing")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)

                HStack(spacing: 10) {
                    if knockDown {
                        Button {
                            standingSelection = .empty
                            commitPinBall(game: game, entry: entry, rack: rack)
                        } label: {
                            Text(rack.count == 10 ? "Strike  ✕" : "Spare  /")
                                .font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Theme.success)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
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
                }
            } else {
                DirectEntryPad(maxPins: maxPins(game: game, entry: entry)) { count in
                    commitCountBall(game: game, entry: entry, count: count)
                }
            }
        }
        .card()
        .onAppear { seedSelection(entry: entry) }
        .onChange(of: entryKey) { seedSelection(entry: entry) }
    }

    /// A partial leave (rack < 10) starts with those pins standing (highlighted) so the
    /// bowler taps the ones knocked down. A full fresh rack — the 1st ball, or a 10th-frame
    /// reset after a strike/spare — starts empty (unhighlighted), like a brand-new first ball.
    private func seedSelection(entry: EntryContext) {
        if let rack = entry.rack, rack.count < 10 {
            standingSelection = rack
        } else {
            standingSelection = .empty
        }
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
        // Each frame stores its own ball — the live ball in hand.
        frame.ballID = liveBallID ?? game.ballID
        context.insert(frame)
        return frame
    }

    private func commitPinBall(game: Game, entry: EntryContext, rack: PinSet) {
        let standing = standingSelection
        let count = rack.count - standing.count
        let frame = frameForEntry(game: game, entry: entry)
        frame.balls.append(BallEntry(count: count, standingAfterMask: standing.mask))
        standingSelection = .empty
        afterCommit(game: game)
    }

    private func commitCountBall(game: Game, entry: EntryContext, count: Int) {
        let frame = frameForEntry(game: game, entry: entry)
        frame.balls.append(BallEntry(count: count, standingAfterMask: nil))
        afterCommit(game: game)
    }

    /// Tap a frame to choose which shot to edit (the shot picker).
    private func beginEditing(_ frame: Frame) {
        guard !frame.balls.isEmpty else { return }
        editingFrame = frame
        editingBallIndex = nil
        editingBackup = frame.balls
        standingSelection = .empty
    }

    /// Pick which shot to re-enter: snapshot the frame, drop that ball and the ones
    /// after it, then show normal entry for it. Back/Cancel restore the snapshot.
    private func chooseShot(_ frame: Frame, ballIndex: Int) {
        editingBackup = frame.balls
        editingBallIndex = ballIndex
        if frame.balls.count > ballIndex {
            frame.balls.removeLast(frame.balls.count - ballIndex)
        }
        standingSelection = .empty
    }

    /// Restore the frame and return to the shot picker.
    private func backToPicker() {
        if let frame = editingFrame { frame.balls = editingBackup }
        editingBallIndex = nil
        standingSelection = .empty
    }

    /// Restore the frame and leave edit mode entirely.
    private func cancelEdit() {
        if let frame = editingFrame { frame.balls = editingBackup }
        clearEdit()
    }

    /// Leave edit mode, keeping the re-entered shots.
    private func clearEdit() {
        editingFrame = nil
        editingBallIndex = nil
        editingBackup = []
        standingSelection = .empty
    }

    @ViewBuilder
    private func editShotPicker(_ frame: Frame) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text("Frame \(frame.number) — edit which shot?")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Button {
                    cancelEdit()
                } label: {
                    Label("Cancel", systemImage: "xmark")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Theme.warning)
            }
            HStack(spacing: 8) {
                ForEach(Array(frame.balls.enumerated()), id: \.offset) { index, ball in
                    Button {
                        chooseShot(frame, ballIndex: index)
                    } label: {
                        VStack(spacing: 3) {
                            Text("Ball \(index + 1)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textMuted)
                            Text(ball.count == 10 ? "X" : "\(ball.count)")
                                .font(.system(size: 20, weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Re-enter from the shot you pick; earlier shots stay.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textMuted)
        }
        .card()
    }

    private func afterCommit(game: Game) {
        // A committed edit returns to normal entry for the rest of the frame/game.
        if editingFrame != nil { clearEdit() }
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

// MARK: - In-session stats (PRD 5.3: quick dashboard for the current block/session)

/// The current session/block's stats so far — opened from the scoring view.
struct SessionStatsSheet: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss

    private var games: [GameRecord] { session.gameRecords() }

    private var seriesTotal: Int {
        session.sortedGames.filter { $0.isComplete }.map { $0.finalScore }.reduce(0, +)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                let stats = StatsEngine.dashboard(games: games)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 16) {
                        headlineTile("Series", "\(seriesTotal)")
                        headlineTile("Games", "\(stats.gamesCount)")
                        headlineTile("Average", stats.average.map { Notation.oneDecimal($0) } ?? "--")
                    }
                    .card()

                    if stats.gamesCount == 0 {
                        Text("No completed games yet — finish a game to see stats.")
                            .font(Theme.cardSubtitle)
                            .foregroundStyle(Theme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 30)
                    } else {
                        primaryGrid(stats)
                        SpareBreakdownPanel(games: games)
                        StrikeClustersPanel(stats: stats, sessions: [session])
                    }
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle(session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }

    private func headlineTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.statNumber(26))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(Theme.statLabel)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func primaryGrid(_ stats: DashboardStats) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
        func pct(_ value: Double?) -> String { value.map { String(format: "%.1f%%", $0) } ?? "--" }
        return LazyVGrid(columns: columns, spacing: 10) {
            StatTile(label: "Strike %", value: pct(stats.strikePercent))
            StatTile(label: "Makeable Spare %", value: pct(stats.makeableSparePercent))
            StatTile(label: "Split %", value: pct(stats.splitPercent))
            StatTile(label: "Open Frame %", value: pct(stats.openFramePercent))
        }
    }
}
