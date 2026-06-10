import SwiftUI
import SwiftData
import PocketProCore

// MARK: - Mid-game ball swap (PRD 5.1: ball chip → swap with optional reason)

struct BallSwapSheet: View {
    let session: Session
    let game: Game?
    let arsenal: [Ball]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var reason = ""

    /// Balls picked at session setup float to the top of the picker.
    private var orderedBalls: [Ball] {
        let bagSet = Set(session.todaysBallIDs)
        return arsenal.sorted { a, b in
            let aInBag = bagSet.contains(a.id)
            let bInBag = bagSet.contains(b.id)
            if aInBag != bInBag { return aInBag }
            return a.displayName < b.displayName
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Switch to") {
                    ForEach(orderedBalls) { ball in
                        Button {
                            swap(to: ball)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ball.displayName)
                                        .foregroundStyle(Theme.textPrimary)
                                    if let layout = ball.activeLayout {
                                        Text(layout.shorthand)
                                            .font(Theme.cardSubtitle)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                Spacer()
                                if session.todaysBallIDs.contains(ball.id) {
                                    Image(systemName: "bag.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.accent)
                                }
                                CoverstockBadge(type: ball.coverstockType)
                            }
                        }
                    }
                }
                Section("Reason (optional)") {
                    TextField("e.g. Lanes transitioned, moved in", text: $reason)
                }
            }
            .navigationTitle("Ball Swap")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func swap(to ball: Ball) {
        guard let game else {
            dismiss()
            return
        }
        if let current = game.sortedFrames.first(where: {
            !ScoringEngine.isFrameComplete(balls: $0.counts, frameIndex: $0.number - 1)
        }) {
            current.ballID = ball.id
            current.ballSwapReason = reason.isEmpty ? nil : reason
        } else if !game.isComplete {
            // Next frame hasn't started — create it carrying the swap.
            let frame = Frame()
            frame.number = min(10, game.sortedFrames.count + 1)
            frame.game = game
            frame.ballID = ball.id
            frame.ballSwapReason = reason.isEmpty ? nil : reason
            context.insert(frame)
        }
        if game.ballID == nil && game.sortedFrames.allSatisfy({ $0.balls.isEmpty }) {
            game.ballID = ball.id
        }
        dismiss()
    }
}

// MARK: - Structured frame note (PRD 5.1: board / breakpoint fields + free text)

struct FrameNoteSheet: View {
    @Bindable var frame: Frame
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Lane Play") {
                    boardPicker("Target Board", value: $frame.targetBoard)
                    boardPicker("Board Hit", value: $frame.boardHit)
                    boardPicker("Breakpoint Board", value: $frame.breakpointBoard)
                    HStack {
                        Text("Breakpoint Distance")
                        Spacer()
                        OptionalNumberField(placeholder: "ft", value: $frame.breakpointDistanceFt)
                            .frame(width: 80)
                    }
                }
                Section("Note") {
                    TextField(
                        "Miss reason or lane observation",
                        text: Binding(
                            get: { frame.note ?? "" },
                            set: { frame.note = $0.isEmpty ? nil : $0 }
                        ),
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                }
                if frame.ballSwapReason != nil {
                    Section("Ball Swap") {
                        Text(frame.ballSwapReason ?? "")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .navigationTitle("Frame \(frame.number) Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func boardPicker(_ label: String, value: Binding<Int?>) -> some View {
        Picker(label, selection: value) {
            Text("—").tag(Int?.none)
            ForEach(1...39, id: \.self) { board in
                Text("\(board)").tag(Int?.some(board))
            }
        }
    }
}

// MARK: - End-of-game card (PRD 5.1)

struct EndOfGameCard: View {
    let session: Session
    let game: Game
    var onAnotherGame: () -> Void
    var onDone: () -> Void

    @FocusState private var noteFocused: Bool
    @State private var noteText = ""

    private var summary: ScoringEngine.GameSummary {
        ScoringEngine.summary(frames: game.frameCounts)
    }

    private var splitCount: Int {
        game.derivedLeaves().filter { $0.categories.contains(.split) }.count
    }

    private var singlePinRate: Double? {
        let singles = game.derivedLeaves().filter { $0.categories.contains(.singlePin) && $0.hadOpportunity }
        guard !singles.isEmpty else { return nil }
        return Double(singles.filter { $0.converted }.count) / Double(singles.count) * 100
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("Game \(game.orderIndex + 1)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 24)

            Text("\(game.finalScore)")
                .font(Theme.statNumber(76))
                .foregroundStyle(Theme.textPrimary)

            Text(summaryLine)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            if let rate = singlePinRate {
                HStack(spacing: 6) {
                    Text("Single-pin spares")
                        .font(Theme.cardSubtitle)
                        .foregroundStyle(Theme.textSecondary)
                    Text(Notation.percent(rate))
                        .font(.system(size: 15, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.conversionColor(rate))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("SESSION NOTE")
                    .font(Theme.statLabel)
                    .foregroundStyle(Theme.textSecondary)
                TextField("How did it go?", text: $noteText, axis: .vertical)
                    .lineLimit(2...5)
                    .textFieldStyle(.roundedBorder)
                    .focused($noteFocused)
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    saveNote()
                    onAnotherGame()
                } label: {
                    Text("Bowl another game")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button {
                    saveNote()
                    onDone()
                } label: {
                    Text("Done")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Theme.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding([.horizontal, .bottom])
        }
        .background(Theme.bgPrimary)
        .onAppear {
            noteText = session.notes
            // Keyboard immediately active per PRD 5.1.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                noteFocused = true
            }
        }
    }

    private var summaryLine: String {
        var parts = [
            "\(summary.strikes) strike\(summary.strikes == 1 ? "" : "s")",
            "\(summary.spares) spare\(summary.spares == 1 ? "" : "s")",
            "\(summary.opens) open\(summary.opens == 1 ? "" : "s")",
        ]
        if splitCount > 0 {
            parts.append("\(splitCount) split\(splitCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: "  |  ")
    }

    private func saveNote() {
        session.notes = noteText
    }
}
