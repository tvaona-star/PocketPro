import SwiftUI
import SwiftData
import PocketProCore

/// Arsenal tab (PRD 5.4): the definitive equipment record.
struct ArsenalTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Ball.model) private var balls: [Ball]
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]

    @State private var showingAddBall = false
    @State private var compareBall: Ball?
    @State private var deleteCandidate: Ball?
    @State private var surfaceLogBall: Ball?
    @State private var sortOption: BallSort = .name

    enum BallSort: String, CaseIterable, Identifiable {
        case name = "Name"
        case weight = "Weight"
        case year = "Year (newest)"
        case manufacturer = "Brand"
        case recent = "Recently used"
        var id: String { rawValue }
    }

    private var activeBalls: [Ball] {
        sorted(balls.filter { $0.active })
    }

    private var retiredBalls: [Ball] {
        sorted(balls.filter { !$0.active })
    }

    /// Most recent session date each ball was used in — for the "Recently used" sort.
    private var lastUsed: [UUID: Date] {
        var map: [UUID: Date] = [:]
        for session in sessions {            // sessions is already date-descending
            for game in session.sortedGames {
                for id in game.ballIDsUsed where map[id] == nil {
                    map[id] = session.date
                }
            }
        }
        return map
    }

    private func sorted(_ list: [Ball]) -> [Ball] {
        switch sortOption {
        case .name:
            return list.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .weight:
            return list.sorted { $0.weight > $1.weight }
        case .year:
            return list.sorted { ($0.year ?? 0) > ($1.year ?? 0) }
        case .manufacturer:
            return list.sorted {
                let a = $0.manufacturer.isEmpty ? $0.brand : $0.manufacturer
                let b = $1.manufacturer.isEmpty ? $1.brand : $1.manufacturer
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
        case .recent:
            let used = lastUsed
            return list.sorted { (used[$0.id] ?? .distantPast) > (used[$1.id] ?? .distantPast) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if balls.isEmpty {
                    VStack {
                        EmptyStateView(
                            icon: "circle.grid.3x3",
                            title: "Add your first ball to start tracking equipment.",
                            message: "Search 2,000+ balls from Storm, Brunswick, Motiv and more.",
                            actionTitle: "Add Ball",
                            action: { showingAddBall = true }
                        )
                        toolsGrid
                            .padding(.horizontal)
                    }
                } else {
                    List {
                        Section("Tools") {
                            toolsGrid
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                        }

                        Section("Balls") {
                            ForEach(activeBalls) { ball in
                                ballRow(ball)
                            }
                        }

                        if !retiredBalls.isEmpty {
                            Section("Retired") {
                                ForEach(retiredBalls) { ball in
                                    ballRow(ball)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Arsenal")
            .toolbar {
                // Match every other tab: primary "+" leading, Settings trailing.
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingAddBall = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                if !balls.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Picker("Sort by", selection: $sortOption) {
                                ForEach(BallSort.allCases) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.up.arrow.down")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SettingsToolbarLink()
                }
            }
            .sheet(isPresented: $showingAddBall) {
                AddBallFlow()
                    .presentationDetents([.large])
            }
            .sheet(item: $compareBall) { ball in
                BallCompareView(initialA: ball)
                    .presentationDetents([.large])
            }
            .sheet(item: $surfaceLogBall) { ball in
                SurfaceLogSheet(ball: ball, sessions: sessions)
                    .presentationDetents([.medium, .large])
            }
            .confirmationDialog(
                "Delete \(deleteCandidate?.displayName ?? "this ball")?",
                isPresented: Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } }),
                titleVisibility: .visible,
                presenting: deleteCandidate
            ) { ball in
                Button("Delete", role: .destructive) {
                    context.delete(ball)
                    deleteCandidate = nil
                }
                Button("Cancel", role: .cancel) { deleteCandidate = nil }
            } message: { ball in
                Text("Permanently removes \(ball.displayName) from your arsenal. Past games keep their scores. To keep it but hide it, use Retire instead.")
            }
        }
    }

    private func ballRow(_ ball: Ball) -> some View {
        BallCard(ball: ball, gamesSincePrep: ArsenalActions.gamesSinceLastPrep(ball: ball, sessions: sessions))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            // PRD 7.3: surface prep is a frequent action — keep it one swipe away.
            Button {
                surfaceLogBall = ball
            } label: {
                Label("Surface", systemImage: "circle.dashed")
            }
            .tint(Theme.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button {
                compareBall = ball
            } label: {
                Label("Compare", systemImage: "rectangle.on.rectangle")
            }
            .tint(Theme.accent)
            Button {
                ball.active.toggle()
            } label: {
                Label(ball.active ? "Retire" : "Activate", systemImage: ball.active ? "archivebox" : "arrow.uturn.up")
            }
            .tint(Theme.warning)
            Button(role: .destructive) {
                deleteCandidate = ball
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Equipment tools: layout library, bags, chart, compare, profile — one tap (PRD 7.5).
    private var toolsGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                toolLink("Layouts", icon: "scribble.variable") { LayoutLibraryView() }
                toolLink("Bags", icon: "bag") { BagBuilderView() }
                toolLink("Chart", icon: "chart.dots.scatter") { ArsenalChartView() }
                toolLink("Profile", icon: "person.crop.circle") { BowlerProfileView() }
            }
        }
    }

    private func toolLink<Destination: View>(_ label: String, icon: String, @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Theme.bgElevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Async product photo with a coverstock-colored dot fallback (PRD 5.4).
struct BallThumbnail: View {
    let urlString: String?
    let coverstock: CoverstockType?
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            Circle().fill(Theme.bgElevated)
            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit().padding(size * 0.06)
                    case .empty:
                        ProgressView().controlSize(.mini)
                    default:
                        placeholderDot
                    }
                }
            } else {
                placeholderDot
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholderDot: some View {
        Image(systemName: "circle.fill")
            .font(.system(size: size * 0.22))
            .foregroundStyle(Theme.coverstockColor(coverstock))
    }
}

/// Ball card (PRD 5.4.3) — collapsed by default: photo, name, brand, year, weight.
/// Expand (chevron) to reveal coverstock, specs, layout, and a link to full detail.
struct BallCard: View {
    let ball: Ball
    var gamesSincePrep: Int = 0
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Theme.sectionSpring) { expanded.toggle() }
            } label: {
                header
            }
            .buttonStyle(.plain)

            if expanded {
                expandedDetail
            }
        }
        .card()
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            BallThumbnail(urlString: ball.imageURLString, coverstock: ball.coverstockType, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(ball.displayName)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !ball.manufacturer.isEmpty {
                        Text(ball.manufacturer)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted)
                    }
                    if let year = ball.year {
                        Text(String(year))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
            Spacer()
            Text("\(ball.weight) lb")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
        }
        .contentShape(Rectangle())
    }

    private var expandedDetail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                CoverstockBadge(type: ball.coverstockType)
                ThumbBadge(type: ball.thumbType)
                if ball.importedShell {
                    Badge(text: "Tap to add specs", color: Theme.warning)
                }
            }

            HStack(spacing: 14) {
                if let rg = ball.rg {
                    specPair("RG", String(format: "%.2f", rg))
                }
                if let diff = ball.diff {
                    specPair("DIFF", String(format: "%.3f", diff))
                }
                if let surface = ball.latestSurfaceLog {
                    specPair("SURFACE", surface.grit.displayName)
                    specPair("PREPPED", surface.date.formatted(.dateTime.month(.abbreviated).day()))
                } else if let finish = ball.factoryFinish {
                    specPair("SURFACE", finish)
                }
            }

            if let layout = ball.activeLayout {
                HStack(spacing: 6) {
                    Image(systemName: "scribble.variable")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textMuted)
                    Text("\(layout.name) · \(layout.shorthand) \(layout.system.shortName)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            NavigationLink {
                BallDetailView(ball: ball)
            } label: {
                HStack(spacing: 4) {
                    Text("View full details")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    private func specPair(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.textMuted)
            Text(value)
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
