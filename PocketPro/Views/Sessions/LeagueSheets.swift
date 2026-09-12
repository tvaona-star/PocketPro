import SwiftUI
import SwiftData
import PocketProCore

// MARK: - Create a league (PRD 5.2: name, start date, games per week)

struct NewLeagueSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var startDate = Date()
    @State private var gamesPerWeek = 3
    @State private var isSport = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Tuesday Classic)", text: $name)
                    DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                    Stepper("Games per week: \(gamesPerWeek)", value: $gamesPerWeek, in: 1...12)
                    Toggle("Sport pattern league", isOn: $isSport)
                } header: {
                    Text("League")
                } footer: {
                    Text("Then open the league and add a week each time you bowl. Every week stays grouped under this league.")
                }
            }
            .navigationTitle("New League")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create") {
                        let league = LeagueEvent()
                        league.name = name.trimmingCharacters(in: .whitespaces)
                        league.kind = .league
                        league.startDate = startDate
                        league.gamesPerWeek = gamesPerWeek
                        league.isSport = isSport
                        context.insert(league)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

/// Edit a league's start date / games per week, or convert the whole league
/// (every week) to a Tournament or Practice — creates the record for an
/// imported league that doesn't have one yet.
struct LeagueEditSheet: View {
    let leagueName: String
    let existing: LeagueEvent?
    /// Called after a conversion empties this league, so the detail view can pop.
    var onConverted: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Session.date, order: .reverse) private var allSessions: [Session]
    @Query private var leagueEvents: [LeagueEvent]

    @State private var type: SessionType = .league
    @State private var name = ""
    @State private var startDate = Date()
    @State private var hasStartDate = false
    @State private var gamesPerWeek = 3
    @State private var isSport = false
    @State private var showingRenameConfirm = false

    /// The league's own sessions (its weeks) — what a conversion will re-tag.
    private var weeks: [Session] {
        allSessions.filter {
            $0.type == .league && ($0.leagueName ?? "").caseInsensitiveCompare(leagueName) == .orderedSame
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
                    if type != .league {
                        Text("Converts all \(weeks.count) week\(weeks.count == 1 ? "" : "s") under \(leagueName) to \(type.displayName) and removes the league grouping. Scores are kept.")
                    }
                }

                if type == .league {
                    Section("Name") {
                        TextField("League name", text: $name)
                    }
                    Section("Season") {
                        Toggle("Set a start date", isOn: $hasStartDate)
                        if hasStartDate {
                            DatePicker("Start date", selection: $startDate, displayedComponents: .date)
                        }
                        Stepper("Games per week: \(gamesPerWeek)", value: $gamesPerWeek, in: 1...12)
                        Toggle("Sport pattern league", isOn: $isSport)
                    }
                } else if type == .tournament {
                    Section {
                        Toggle("Sport pattern", isOn: $isSport)
                    }
                }
            }
            .navigationTitle(leagueName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(type == .league ? "Save" : "Convert") { save() }
                }
            }
            .onAppear {
                name = leagueName
                if let existing {
                    hasStartDate = existing.startDate != nil
                    startDate = existing.startDate ?? Date()
                    gamesPerWeek = existing.gamesPerWeek
                    isSport = existing.isSport
                }
            }
            .confirmationDialog("Rename league?", isPresented: $showingRenameConfirm, titleVisibility: .visible) {
                Button("Rename & update \(weeks.count) week\(weeks.count == 1 ? "" : "s")") { commitLeague() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Renames the league everywhere and re-tags all its weeks. You'll return to the Sessions list.")
            }
        }
    }

    private func save() {
        guard type == .league else {
            convert(to: type)
            dismiss()
            onConverted?()
            return
        }
        // A rename cascades to every week and pops back to the list — confirm first.
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let newName = trimmed.isEmpty ? leagueName : trimmed
        if newName.caseInsensitiveCompare(leagueName) != .orderedSame {
            showingRenameConfirm = true
        } else {
            commitLeague()
        }
    }

    /// Apply the name and settings; when the name changed, re-tag every week, drop
    /// the old record, and pop the (now stale) detail view.
    private func commitLeague() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let newName = trimmed.isEmpty ? leagueName : trimmed
        let renamed = newName.caseInsensitiveCompare(leagueName) != .orderedSame

        let league = findOrCreateEvent(newName, kind: .league)
        league.startDate = hasStartDate ? startDate : nil
        league.gamesPerWeek = gamesPerWeek
        league.isSport = isSport

        if renamed {
            for week in weeks {
                week.leagueName = newName
                week.leagueEvent = league
            }
            if let existing, existing !== league { context.delete(existing) }
        }
        dismiss()
        if renamed { onConverted?() }
    }

    /// Re-tag every week of this league to the new type and drop the league record.
    private func convert(to newType: SessionType) {
        let event: LeagueEvent? = newType == .tournament ? findOrCreateEvent(leagueName, kind: .tournament) : nil
        event?.isSport = isSport
        for session in weeks {
            session.type = newType
            session.needsTypeReview = false
            switch newType {
            case .tournament:
                session.eventName = leagueName
                session.leagueName = leagueName
                session.leagueEvent = event
            case .practice:
                session.eventName = nil
                session.leagueName = nil
                session.leagueEvent = nil
            case .league:
                break
            }
        }
        // Remove the now-orphaned league record so it stops showing as a league.
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
