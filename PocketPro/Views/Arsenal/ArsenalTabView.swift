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

    private var activeBalls: [Ball] {
        balls.filter { $0.active }
    }

    private var retiredBalls: [Ball] {
        balls.filter { !$0.active }
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
                        Section {
                            toolsGrid
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 6, trailing: 16))
                        }

                        Section {
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
                ToolbarItem(placement: .topBarLeading) {
                    SettingsToolbarLink()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddBall = true
                    } label: {
                        Image(systemName: "plus")
                    }
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
        }
    }

    private func ballRow(_ ball: Ball) -> some View {
        ZStack {
            NavigationLink {
                BallDetailView(ball: ball)
            } label: {
                EmptyView()
            }
            .opacity(0)
            BallCard(ball: ball, gamesSincePrep: ArsenalActions.gamesSinceLastPrep(ball: ball, sessions: sessions))
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // PRD 7.3: swipe quick actions — Edit, Surface Log, Compare.
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

/// Ball card (PRD 5.4.3) — Tier 1: decision-relevant data, never truncated.
struct BallCard: View {
    let ball: Ball
    var gamesSincePrep: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(ball.displayName)
                        .font(Theme.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
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
            }

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
        }
        .card()
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
