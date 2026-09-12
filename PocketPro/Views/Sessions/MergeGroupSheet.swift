import SwiftUI
import SwiftData
import PocketProCore

// MARK: - Merge a whole league / tournament into another (PRD 5.2)

/// Picks a destination league or tournament to absorb the current one.
struct MergeGroupSheet: View {
    let noun: String          // "league" or "tournament"
    let sourceName: String
    let candidates: [String]
    let onMerge: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmTarget: String?

    private var childWord: String { noun == "league" ? "weeks" : "blocks" }
    private var icon: String { noun == "league" ? "trophy.fill" : "flag.checkered" }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    EmptyStateView(
                        icon: "arrow.triangle.merge",
                        title: "No other \(noun)s",
                        message: "You need a second \(noun) to merge into."
                    )
                } else {
                    List {
                        Section {
                            Text("Moves every one of \(sourceName)'s \(childWord) into the \(noun) you pick. \(sourceName) is then removed. Scores are kept.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .listRowBackground(Color.clear)
                        }
                        Section("Merge into") {
                            ForEach(candidates, id: \.self) { name in
                                Button { confirmTarget = name } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: icon)
                                            .font(.system(size: 13))
                                            .foregroundStyle(Theme.accent)
                                        Text(name).foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Merge \(noun.capitalized)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog(
                "Merge into \(confirmTarget ?? "")?",
                isPresented: Binding(get: { confirmTarget != nil }, set: { if !$0 { confirmTarget = nil } }),
                titleVisibility: .visible,
                presenting: confirmTarget
            ) { target in
                Button("Merge") {
                    confirmTarget = nil
                    dismiss()
                    onMerge(target)
                }
                Button("Cancel", role: .cancel) { confirmTarget = nil }
            } message: { target in
                Text("\(sourceName)'s \(childWord) move into \(target).")
            }
        }
    }
}
