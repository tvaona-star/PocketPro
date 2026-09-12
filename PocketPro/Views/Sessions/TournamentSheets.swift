import SwiftUI
import SwiftData
import PocketProCore

// MARK: - Create a tournament (PRD 5.2: a container for one or more event blocks)

struct NewTournamentSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var date = Date()
    @State private var isSport = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. City Open)", text: $name)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Toggle("Sport pattern", isOn: $isSport)
                } header: {
                    Text("Tournament")
                } footer: {
                    Text("Then open the tournament and add each event block (e.g. Qualifying, Match Play) as you bowl it.")
                }
            }
            .navigationTitle("New Tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        let event = LeagueEvent()
                        event.name = name.trimmingCharacters(in: .whitespaces)
                        event.kind = .tournament
                        event.startDate = date
                        event.isSport = isSport
                        context.insert(event)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Edit a tournament's sport flag, or convert the whole tournament (every block)
/// to a League or Practice — mirrors LeagueEditSheet.
struct TournamentEditSheet: View {
    let tournamentName: String
    let existing: LeagueEvent?
    /// Called after a conversion empties this tournament, so the detail view can pop.
    var onConverted: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Query private var leagueEvents: [LeagueEvent]

    @State private var type: SessionType = .tournament
    @State private var name = ""
    @State private var isSport = false
    @State private var showingRenameConfirm = false

    /// The tournament's own blocks — what a conversion will re-tag.
    private var blocks: [Session] {
        allSessions.filter {
            $0.type == .tournament
                && ($0.eventName ?? $0.leagueName ?? "").caseInsensitiveCompare(tournamentName) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(SessionType.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    if type != .tournament {
                        Text("Converts all \(blocks.count) block\(blocks.count == 1 ? "" : "s") under \(tournamentName) to \(type.displayName)\(type == .league ? " (as weeks)" : "") and removes the tournament grouping. Scores are kept.")
                    }
                }

                if type == .tournament {
                    Section("Name") {
                        TextField("Tournament name", text: $name)
                    }
                    Section {
                        Toggle("Sport pattern", isOn: $isSport)
                    }
                } else if type == .league {
                    Section {
                        Toggle("Sport pattern league", isOn: $isSport)
                    }
                }
            }
            .navigationTitle(tournamentName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(type == .tournament ? "Save" : "Convert") { save() }
                }
            }
            .onAppear {
                name = tournamentName
                isSport = existing?.isSport ?? false
            }
            .confirmationDialog("Rename tournament?", isPresented: $showingRenameConfirm, titleVisibility: .visible) {
                Button("Rename & update \(blocks.count) block\(blocks.count == 1 ? "" : "s")") { commitTournament() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Renames the tournament everywhere and re-tags all its blocks. You'll return to the Sessions list.")
            }
        }
    }

    private func save() {
        guard type == .tournament else {
            convert(to: type)
            dismiss()
            onConverted?()
            return
        }
        // A rename cascades to every block and pops back to the list — confirm first.
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let newName = trimmed.isEmpty ? tournamentName : trimmed
        if newName.caseInsensitiveCompare(tournamentName) != .orderedSame {
            showingRenameConfirm = true
        } else {
            commitTournament()
        }
    }

    /// Apply the name and sport flag; when the name changed, re-tag every block
    /// (keeping each block's own name), drop the old record, and pop the detail.
    private func commitTournament() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let newName = trimmed.isEmpty ? tournamentName : trimmed
        let renamed = newName.caseInsensitiveCompare(tournamentName) != .orderedSame

        let event = findOrCreateEvent(newName, kind: .tournament)
        event.isSport = isSport

        if renamed {
            for block in blocks {
                block.eventName = newName
                block.leagueName = newName
                block.leagueEvent = event
            }
            if let existing, existing !== event { context.delete(existing) }
        }
        dismiss()
        if renamed { onConverted?() }
    }

    /// Re-tag every block of this tournament to the new type and drop the tournament record.
    private func convert(to newType: SessionType) {
        let event: LeagueEvent? = newType == .league ? findOrCreateEvent(tournamentName, kind: .league) : nil
        event?.isSport = isSport
        for session in blocks {
            session.type = newType
            session.needsTypeReview = false
            session.blockName = nil
            switch newType {
            case .league:
                session.leagueName = tournamentName
                session.eventName = nil
                session.leagueEvent = event
            case .practice:
                session.leagueName = nil
                session.eventName = nil
                session.leagueEvent = nil
            case .tournament:
                break
            }
        }
        if let existing { context.delete(existing) }
    }

    private func findOrCreateEvent(_ name: String, kind: LeagueEventKind) -> LeagueEvent {
        if let match = leagueEvents.first(where: { $0.kind == kind && $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return match
        }
        let event = LeagueEvent()
        event.name = name
        event.kind = kind
        context.insert(event)
        return event
    }
}
