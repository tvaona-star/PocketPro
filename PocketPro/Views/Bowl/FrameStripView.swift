import SwiftUI
import PocketProCore

/// Standard 10-frame scorecard strip with running totals (PRD 5.1).
/// Long-press a frame for the structured frame note (PRD 5.1).
struct FrameStripView: View, Equatable {
    /// Renders from a value snapshot, never from SwiftData: the strip can be skipped by
    /// SwiftUI whenever the snapshot and display inputs are unchanged, so the pin-deck
    /// selection moving on every tap no longer re-renders (and re-decodes) the scorecard.
    let snapshot: GameSnapshot
    var highlightCurrent: Bool = true
    /// When set, this frame is highlighted as the one being edited (PRD 5.1).
    var editingFrameNumber: Int? = nil
    /// 1-based numbers of frames carrying a note or lane-play data (shown as a dot).
    var notedFrames: Set<Int> = []
    /// Callbacks receive the 1-based frame number; callers resolve the model object.
    var onLongPressFrame: ((Int) -> Void)?
    var onTapFrame: ((Int) -> Void)?

    static func == (lhs: FrameStripView, rhs: FrameStripView) -> Bool {
        lhs.snapshot == rhs.snapshot
            && lhs.highlightCurrent == rhs.highlightCurrent
            && lhs.editingFrameNumber == rhs.editingFrameNumber
            && lhs.notedFrames == rhs.notedFrames
    }

    var body: some View {
        let current = snapshot.currentFrameNumber ?? 10
        // All 10 frames visible at once, no scroll: 1–5 on top, 6–10 below (PRD 5.1).
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { number in
                    frameCell(number: number, isCurrent: highlight(number, current: current))
                }
            }
            HStack(spacing: 4) {
                ForEach(6...10, id: \.self) { number in
                    frameCell(number: number, isCurrent: highlight(number, current: current))
                }
            }
        }
    }

    private func highlight(_ number: Int, current: Int) -> Bool {
        if let editing = editingFrameNumber { return number == editing }
        return highlightCurrent && !snapshot.isComplete && number == current
    }

    private func counts(for number: Int) -> [Int] {
        let index = number - 1
        return index < snapshot.frameCounts.count ? snapshot.frameCounts[index] : []
    }

    @ViewBuilder
    private func frameCell(number: Int, isCurrent: Bool) -> some View {
        let symbols = ballSymbols(number: number, counts: counts(for: number))
        // Scoresheet convention: circle the first-ball count when it left a split.
        let split = snapshot.splitFrameNumbers.contains(number)
        let cumulative: Int? = number - 1 < snapshot.cumulative.count ? snapshot.cumulative[number - 1] : nil

        VStack(spacing: 0) {
            Text("\(number)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
                .padding(.bottom, 2)

            HStack(spacing: 1) {
                ForEach(Array(symbols.enumerated()), id: \.offset) { index, symbol in
                    Text(symbol)
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(Theme.textPrimary)
                        .frame(width: 15, height: 18)
                        .background(Theme.bgElevated)
                        .overlay {
                            if index == 0 && split {
                                Circle()
                                    .strokeBorder(Theme.destructive, lineWidth: 1.5)
                                    .frame(width: 17, height: 17)
                            }
                        }
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
            if notedFrames.contains(number) {
                Circle()
                    .fill(Theme.warning)
                    .frame(width: 6, height: 6)
                    .offset(x: -2, y: 2)
            }
        }
        .onTapGesture { onTapFrame?(number) }
        .onLongPressGesture { onLongPressFrame?(number) }
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
