import SwiftUI
import SwiftData
import PocketProCore

/// Session setup bottom sheet (PRD 5.1): type required, everything else optional,
/// confirm in one tap. Presented from the Sessions tab; `onStart` hands the new
/// session back so the caller can drop straight into live scoring.
struct SessionSetupSheet: View {
    /// Reports the freshly-created session so the presenter can open live scoring.
    var onStart: (Session) -> Void = { _ in }
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Session.date, order: .reverse) private var pastSessions: [Session]
    @Query(filter: #Predicate<Ball> { $0.active }) private var arsenal: [Ball]
    @Query(sort: \Pattern.createdAt, order: .reverse) private var patterns: [Pattern]
    @Query private var locations: [Location]
    @Query(sort: \LeagueEvent.createdAt, order: .reverse) private var leagueEvents: [LeagueEvent]
    @Query(sort: \Bag.createdAt, order: .reverse) private var bags: [Bag]

    @AppStorage("settings.lastSessionType") private var lastSessionTypeRaw = SessionType.practice.rawValue
    @State private var type: SessionType = .practice
    @State private var name = ""
    @State private var locationName = ""
    @State private var selectedPattern: Pattern?
    @State private var showingPatternPicker = false
    @State private var selectedBallIDs: Set<UUID> = []
    @State private var ballsExpanded = false

    /// The LeagueEvent kind matching the current session type (nil for practice).
    private var selectedKind: LeagueEventKind? {
        switch type {
        case .league: return .league
        case .tournament: return .tournament
        case .practice: return nil
        }
    }

    /// A league/tournament must be named before it can start, so it never goes
    /// nameless and vanishes from the Sessions tab.
    private var canStart: Bool {
        if type == .league || type == .tournament {
            return !name.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return true
    }

    /// Already-created leagues/tournaments of the selected kind, newest first —
    /// tap one to bowl under it.
    private var recentNames: [String] {
        guard let selectedKind else { return [] }
        return leagueEvents
            .filter { $0.kind == selectedKind && !$0.isArchived }
            .map(\.name)
            .filter { !$0.isEmpty }
    }

    /// Locations ordered by how often they've been bowled (most-used first).
    private var locationsByUsage: [String] {
        var counts: [String: Int] = [:]
        for session in pastSessions {
            if let name = session.location?.name, !name.isEmpty { counts[name, default: 0] += 1 }
        }
        return counts.keys.sorted { (counts[$0] ?? 0) > (counts[$1] ?? 0) }
    }

    private func ballIDs(in bag: Bag) -> Set<UUID> {
        Set(bag.defaultVariation?.sortedSlots.map { $0.ballID } ?? [])
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHeader(title: "New Session", trailing: "Start", trailingDisabled: !canStart) {
                        startSession()
                    }

                    Picker("Session Type", selection: $type) {
                        ForEach(SessionType.allCases) { sessionType in
                            Text(sessionType.displayName).tag(sessionType)
                        }
                    }
                    .pickerStyle(.segmented)

                    if type == .league || type == .tournament {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(type == .league ? "LEAGUE NAME" : "EVENT NAME")
                                .font(Theme.statLabel)
                                .foregroundStyle(Theme.textSecondary)
                            TextField(type == .league ? "e.g. Tuesday Classic" : "e.g. City Open", text: $name)
                                .textFieldStyle(.roundedBorder)
                            if name.trimmingCharacters(in: .whitespaces).isEmpty {
                                Text("A \(type == .league ? "league" : "tournament") needs a name to start.")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            if !recentNames.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(recentNames, id: \.self) { recent in
                                            FilterChip(label: recent, isActive: name == recent) {
                                                name = recent
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("LOCATION")
                            .font(Theme.statLabel)
                            .foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 8) {
                            TextField("Bowling center (optional)", text: $locationName)
                                .textFieldStyle(.roundedBorder)
                            if !locationsByUsage.isEmpty {
                                Menu {
                                    ForEach(locationsByUsage, id: \.self) { loc in
                                        Button(loc) { locationName = loc }
                                    }
                                } label: {
                                    Image(systemName: "chevron.down.circle.fill")
                                        .font(.system(size: 24))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("PATTERN")
                            .font(Theme.statLabel)
                            .foregroundStyle(Theme.textSecondary)
                        Button {
                            showingPatternPicker = true
                        } label: {
                            HStack {
                                if let pattern = selectedPattern {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(pattern.name.isEmpty ? pattern.type.displayName : pattern.name)
                                            .foregroundStyle(Theme.textPrimary)
                                        Text(pattern.summary)
                                            .font(Theme.cardSubtitle)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                } else {
                                    Text("Select pattern (optional)")
                                        .foregroundStyle(Theme.textMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Theme.textMuted)
                            }
                            .card()
                        }
                        .buttonStyle(.plain)
                    }

                    if !arsenal.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            // Quick-fill the bag from an already-built bag.
                            if !bags.isEmpty {
                                Text("PICK A BAG")
                                    .font(Theme.statLabel)
                                    .foregroundStyle(Theme.textSecondary)
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(bags) { bag in
                                            let bagIDs = ballIDs(in: bag)
                                            FilterChip(label: bag.name.isEmpty ? bag.type.displayName : bag.name,
                                                       isActive: !bagIDs.isEmpty && bagIDs == selectedBallIDs) {
                                                selectedBallIDs = bagIDs
                                                ballsExpanded = true
                                            }
                                        }
                                    }
                                }
                            }

                            Button {
                                withAnimation(Theme.sectionSpring) { ballsExpanded.toggle() }
                            } label: {
                                HStack {
                                    Text("BALLS IN BAG TODAY\(selectedBallIDs.isEmpty ? "" : " (\(selectedBallIDs.count))")")
                                        .font(Theme.statLabel)
                                        .foregroundStyle(Theme.textSecondary)
                                    Spacer()
                                    Image(systemName: ballsExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }
                            .buttonStyle(.plain)

                            if ballsExpanded {
                                ForEach(arsenal) { ball in
                                    Button {
                                        if selectedBallIDs.contains(ball.id) {
                                            selectedBallIDs.remove(ball.id)
                                        } else {
                                            selectedBallIDs.insert(ball.id)
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: selectedBallIDs.contains(ball.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundStyle(selectedBallIDs.contains(ball.id) ? Theme.accent : Theme.textMuted)
                                            Text(ball.displayName)
                                                .foregroundStyle(Theme.textPrimary)
                                            Spacer()
                                            CoverstockBadge(type: ball.coverstockType)
                                        }
                                        .card(padding: 10)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    Button {
                        startSession()
                    } label: {
                        Text("Start Session")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding()
            }
            .background(Theme.bgElevated)
            .scrollDismissesKeyboard(.interactively)
            .onAppear { type = SessionType(rawValue: lastSessionTypeRaw) ?? .practice }
            .sheet(isPresented: $showingPatternPicker) {
                PatternPickerSheet(selected: $selectedPattern)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func startSession() {
        lastSessionTypeRaw = type.rawValue   // remember for next time
        let session = Session()
        session.type = type
        session.isActive = true
        session.date = Date()

        // Link (or create) the league/tournament record, and mirror its name into
        // the display caches the rest of the UI already reads. A league/tournament is
        // always named (falling back to Untitled) so it never vanishes from Sessions.
        if let kind = selectedKind {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let finalName = trimmed.isEmpty ? (kind == .league ? "Untitled League" : "Untitled Tournament") : trimmed
            let event = leagueEvents.first {
                $0.kind == kind && $0.name.caseInsensitiveCompare(finalName) == .orderedSame
            } ?? newLeagueEvent(name: finalName, kind: kind)
            session.leagueEvent = event
            if kind == .league {
                session.leagueName = finalName
            } else {
                session.eventName = finalName
                session.leagueName = finalName
            }
        }
        if !locationName.isEmpty {
            if let existing = locations.first(where: { $0.name.caseInsensitiveCompare(locationName) == .orderedSame }) {
                session.location = existing
            } else {
                let location = Location()
                location.name = locationName
                context.insert(location)
                session.location = location
            }
        }
        session.pattern = selectedPattern
        session.todaysBallIDs = Array(selectedBallIDs)
        context.insert(session)

        let game = Game()
        game.orderIndex = 0
        game.session = session
        game.ballID = selectedBallIDs.count == 1 ? selectedBallIDs.first : nil
        context.insert(game)

        onStart(session)
        dismiss()
    }

    private func newLeagueEvent(name: String, kind: LeagueEventKind) -> LeagueEvent {
        let event = LeagueEvent()
        event.name = name
        event.kind = kind
        context.insert(event)
        return event
    }
}

/// Pattern picker (PRD 5.1.1): recents surfaced on top, structured creation below.
struct PatternPickerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Pattern?

    @Query(sort: \Pattern.createdAt, order: .reverse) private var patterns: [Pattern]

    @State private var newType: PatternType = .houseShot
    @State private var newName = ""
    @State private var newLength: Int = 40
    @State private var newRatio: OilRatio?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            List {
                if !patterns.isEmpty && !creating {
                    Section("Recent Patterns") {
                        ForEach(patterns.prefix(8)) { pattern in
                            Button {
                                selected = pattern
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(pattern.name.isEmpty ? pattern.type.displayName : pattern.name)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(pattern.summary)
                                        .font(Theme.cardSubtitle)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                }

                Section(creating || patterns.isEmpty ? "New Pattern" : "Or create new") {
                    Picker("Pattern Type", selection: $newType) {
                        ForEach(PatternType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    TextField("Pattern name (optional)", text: $newName)
                        .onChange(of: newName) { _, _ in creating = true }
                    Picker("Length", selection: $newLength) {
                        ForEach(32...47, id: \.self) { feet in
                            Text("\(feet) ft").tag(feet)
                        }
                        Text("47+ ft").tag(48)
                    }
                    Picker("Oil Ratio (optional)", selection: $newRatio) {
                        Text("Not set").tag(OilRatio?.none)
                        ForEach(OilRatio.allCases) { ratio in
                            Text(ratio.displayName).tag(OilRatio?.some(ratio))
                        }
                    }
                    Button("Save & Select") {
                        let pattern = Pattern()
                        pattern.type = newType
                        pattern.name = newName
                        pattern.lengthFt = newLength
                        pattern.ratio = newRatio
                        context.insert(pattern)
                        selected = pattern
                        dismiss()
                    }
                }

                if selected != nil {
                    Section {
                        Button("Clear pattern", role: .destructive) {
                            selected = nil
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("Pattern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
