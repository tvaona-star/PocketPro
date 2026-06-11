import SwiftUI
import PocketProCore

/// Standard 10-frame scorecard strip with running totals (PRD 5.1).
/// Long-press a frame for the structured frame note (PRD 5.1).
struct FrameStripView: View {
    let game: Game
    var highlightCurrent: Bool = true
    var onLongPressFrame: ((Frame) -> Void)?
    var onTapFrame: ((Frame) -> Void)?

    /// When set, this frame is highlighted as the one being edited (PRD 5.1).
    var editingFrameNumber: Int? = nil

    var body: some View {
        // Compute the score and frame list once per render (not per cell).
        let frames = game.sortedFrames
        let cumulative = game.liveScore.cumulative
        let complete = game.isComplete
        let current = currentNumber(frames: frames)
        // All 10 frames visible at once, no scroll: 1–5 on top, 6–10 below (PRD 5.1).
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { number in
                    frameCell(number: number, frame: frames.first { $0.number == number },
                              cumulative: cumulative[number - 1],
                              isCurrent: highlight(number, current: current, complete: complete))
                }
            }
            HStack(spacing: 4) {
                ForEach(6...10, id: \.self) { number in
                    frameCell(number: number, frame: frames.first { $0.number == number },
                              cumulative: cumulative[number - 1],
                              isCurrent: highlight(number, current: current, complete: complete))
                }
            }
        }
    }

    private func currentNumber(frames: [Frame]) -> Int {
        for f in frames where !ScoringEngine.isFrameComplete(balls: f.counts, frameIndex: f.number - 1) {
            return f.number
        }
        return min(10, frames.count + 1)
    }

    private func highlight(_ number: Int, current: Int, complete: Bool) -> Bool {
        if let editing = editingFrameNumber { return number == editing }
        return highlightCurrent && !complete && number == current
    }

    @ViewBuilder
    private func frameCell(number: Int, frame: Frame?, cumulative: Int?, isCurrent: Bool) -> some View {
        let symbols = ballSymbols(number: number, counts: frame?.counts ?? [])

        VStack(spacing: 0) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .padding(.bottom, 2)

            HStack(spacing: 1) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 15, height: 18)
                        .background(Theme.bgElevated)
                }
            }

            Text(cumulative.map(String.init) ?? " ")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .frame(height: 22)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Theme.bgCard)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isCurrent ? Theme.accent : Theme.separator, lineWidth: isCurrent ? 2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if frame?.hasNote == true {
                Circle()
                    .fill(Theme.warning)
                    .frame(width: 6, height: 6)
                    .offset(x: -2, y: 2)
            }
        }
        .onTapGesture {
            if let frame { onTapFrame?(frame) }
        }
        .onLongPressGesture {
            if let frame {
                onLongPressFrame?(frame)
            }
        }
    }

    /// Scorecard symbols. Frames 1-9: two cells; tenth: three cells.
    private func ballSymbols(number: Int, counts: [Int]) -> [String] {
        let cellCount = number == 10 ? 3 : 2
        var symbols = [String](repeating: " ", count: cellCount)
        guard !counts.isEmpty else { return symbols }

        if number < 10 {
            symbols[0] = counts[0] == 10 ? "X" : (counts[0] == 0 ? "–" : "\(counts[0])")
            if counts.count >= 2 {
                if counts[0] != 10 && counts[0] + counts[1] == 10 {
                    symbols[1] = "/"
                } else {
                    symbols[1] = counts[1] == 0 ? "–" : "\(counts[1])"
                }
            }
            if counts[0] == 10 { symbols[1] = " " }
            return symbols
        }

        // Tenth frame: rack-aware symbols.
        symbols[0] = counts[0] == 10 ? "X" : (counts[0] == 0 ? "–" : "\(counts[0])")
        if counts.count >= 2 {
            if counts[0] == 10 {
                symbols[1] = counts[1] == 10 ? "X" : (counts[1] == 0 ? "–" : "\(counts[1])")
            } else if counts[0] + counts[1] == 10 {
                symbols[1] = "/"
            } else {
                symbols[1] = counts[1] == 0 ? "–" : "\(counts[1])"
            }
        }
        if counts.count >= 3 {
            if counts[0] == 10 && counts[1] != 10 && counts[1] + counts[2] == 10 {
                symbols[2] = "/"
            } else {
                symbols[2] = counts[2] == 10 ? "X" : (counts[2] == 0 ? "–" : "\(counts[2])")
            }
        }
        return symbols
    }
}
