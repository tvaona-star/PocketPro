import SwiftUI
import SwiftData
import PocketProCore

/// Bowl tab (PRD 5.1): live session entry. One tap to a new session.
struct BowlTabView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Session> { $0.isActive }) private var activeSessions: [Session]
    @State private var showingSetup = false

    var body: some View {
        NavigationStack {
            Group {
                if let session = activeSessions.first {
                    LiveSessionView(session: session)
                } else {
                    EmptyStateView(
                        icon: "figure.bowling",
                        title: "Ready to bowl?",
                        message: "Start a session to track your game frame by frame.",
                        actionTitle: "New Session",
                        action: { showingSetup = true }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Bowl")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarLink()
                }
            }
            .sheet(isPresented: $showingSetup) {
                SessionSetupSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
    }
}

/// Session setup bottom sheet (PRD 5.1): type required, everything else optional,
/// confirm in one tap.
struct SessionSetupSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Session.date, order: .reverse) private var pastSessions: [Session]
    @Query(filter: #Predicate<Ball> { $0.active }) private var arsenal: [Ball]
    @Query(sort: \Pattern.createdAt, order: .reverse) private var patterns: [Pattern]
    @Query private var locations: [Location]

    @State private var type: SessionType = .league
    @State private var name = ""
    @State private var locationName = ""
    @State private var selectedPattern: Pattern?
    @State private var showingPatternPicker = false
    @State private var selectedBallIDs: Set<UUID> = []

    private var recentNames: [String] {
        var seen: [String] = []
        for session in pastSessions where session.type == type {
            if let league = session.leagueName, !league.isEmpty, !seen.contains(league) {
                seen.append(league)
            }
            if seen.count >= 4 { break }
        }
        return seen
    }

    private var recentLocations: [String] {
        var seen: [String] = []
        for session in pastSessions {
            if let name = session.location?.name, !name.isEmpty, !seen.contains(name) {
                seen.append(name)
            }
            if seen.count >= 4 { break }
        }
        return seen
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SheetHeader(title: "New Session") {
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
                        TextField("Bowling center (optional)", text: $locationName)
                            .textFieldStyle(.roundedBorder)
                        if !recentLocations.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(recentLocations, id: \.self) { recent in
                                        FilterChip(label: recent, isActive: locationName == recent) {
                                            locationName = recent
                                        }
                                    }
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
                            Text("BALLS IN BAG TODAY")
                                .font(Theme.statLabel)
                                .foregroundStyle(Theme.textSecondary)
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
            .sheet(isPresented: $showingPatternPicker) {
                PatternPickerSheet(selected: $selectedPattern)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private func startSession() {
        let session = Session()
        session.type = type
        session.isActive = true
        session.date = Date()
        if type == .league {
            session.leagueName = name.isEmpty ? nil : name
        } else if type == .tournament {
            session.eventName = name.isEmpty ? nil : name
            session.leagueName = name.isEmpty ? nil : name
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

        dismiss()
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
