import SwiftUI
import SwiftData
import PocketProCore

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
