import SwiftUI
import SwiftData
import Charts
import PocketProCore

/// Arsenal chart (PRD 5.4.10): configurable scatter of the active arsenal.
/// Any spec on either axis; dots colored by coverstock; sized by weight when
/// weight is on neither axis. Empty quadrants reveal arsenal gaps.
struct ArsenalChartView: View {
    @Query(filter: #Predicate<Ball> { $0.active }) private var balls: [Ball]
    @Query(sort: \Bag.createdAt, order: .reverse) private var bags: [Bag]

    @State private var xAxis: ChartAxisOption = .rg
    @State private var yAxis: ChartAxisOption = .diff
    @State private var selectedBall: Ball?
    /// Empty = show the whole arsenal; otherwise only these ball IDs are plotted.
    @State private var filterBallIDs: Set<UUID> = []
    @State private var showingBallPicker = false

    enum ChartAxisOption: String, CaseIterable, Identifiable {
        case rg = "RG"
        case diff = "Differential"
        case intDiff = "Int. Diff"
        case weight = "Weight"
        case surfaceGrit = "Surface Grit"
        case pinToPAP = "Pin to PAP"
        case valAngle = "VAL Angle"
        case hook = "Hook (1-10)"
        case length = "Length (1-10)"

        var id: String { rawValue }

        func value(for ball: Ball) -> Double? {
            switch self {
            case .rg: return ball.rg
            case .diff: return ball.diff
            case .intDiff: return ball.intDiff
            case .weight: return Double(ball.weight)
            case .surfaceGrit:
                if let log = ball.latestSurfaceLog { return log.grit.numericValue }
                return nil
            case .pinToPAP: return ball.activeLayout?.pinToPAP
            case .valAngle:
                guard ball.activeLayout?.system == .dualAngle else { return nil }
                return ball.activeLayout?.valAngle
            case .hook: return ball.hookAmount.map(Double.init)
            case .length: return ball.lengthRating.map(Double.init)
            }
        }
    }

    private struct ChartPoint: Identifiable {
        let id: UUID
        let ball: Ball
        let x: Double
        let y: Double
    }

    /// Active arsenal narrowed by the ball/bag filter (empty filter = everything).
    private var filteredBalls: [Ball] {
        filterBallIDs.isEmpty ? balls : balls.filter { filterBallIDs.contains($0.id) }
    }

    private var points: [ChartPoint] {
        filteredBalls.compactMap { ball in
            guard let x = xAxis.value(for: ball), let y = yAxis.value(for: ball) else { return nil }
            return ChartPoint(id: ball.id, ball: ball, x: x, y: y)
        }
    }

    private var excludedCount: Int {
        filteredBalls.count - points.count
    }

    private func ballIDs(in bag: Bag) -> Set<UUID> {
        Set(bag.defaultVariation?.sortedSlots.map { $0.ballID } ?? [])
    }

    private var filterLabel: String {
        filterBallIDs.isEmpty ? "All balls" : "\(filterBallIDs.count) selected"
    }

    private var sizeByWeight: Bool {
        xAxis != .weight && yAxis != .weight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                axisMenu("X", selection: $xAxis)
                axisMenu("Y", selection: $yAxis)
                Spacer()
                filterMenu
            }
            .padding(.horizontal)

            if points.isEmpty {
                EmptyStateView(
                    icon: "chart.dots.scatter",
                    title: "Nothing to plot yet",
                    message: balls.isEmpty
                        ? "Add balls to your arsenal to see coverage."
                        : "No balls have both \(xAxis.rawValue) and \(yAxis.rawValue) data."
                )
                Spacer()
            } else {
                chart
                    .padding(.horizontal)

                if excludedCount > 0 {
                    Text("\(excludedCount) ball\(excludedCount == 1 ? "" : "s") not shown — missing axis data")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.horizontal)
                }

                legend
                    .padding(.horizontal)
                Spacer()
            }
        }
        .padding(.top, 8)
        .background(Theme.bgPrimary)
        .navigationTitle("Arsenal Chart")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedBall) { ball in
            BallDetailView(ball: ball)
        }
        .sheet(isPresented: $showingBallPicker) {
            ChartBallPickerSheet(balls: balls, selection: $filterBallIDs)
                .presentationDetents([.medium, .large])
        }
    }

    /// Filter the plotted balls to a bag or a hand-picked set (PRD 5.4.10).
    private var filterMenu: some View {
        Menu {
            Button {
                filterBallIDs = []
            } label: {
                Label("All balls", systemImage: filterBallIDs.isEmpty ? "checkmark" : "circle.grid.3x3")
            }
            if !bags.isEmpty {
                Section("Bags") {
                    ForEach(bags) { bag in
                        Button {
                            filterBallIDs = ballIDs(in: bag)
                        } label: {
                            Text(bag.name.isEmpty ? "Untitled bag" : bag.name)
                        }
                    }
                }
            }
            Divider()
            Button {
                showingBallPicker = true
            } label: {
                Label("Choose balls…", systemImage: "checklist")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 12))
                Text(filterLabel)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(filterBallIDs.isEmpty ? Theme.textPrimary : Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.bgElevated)
            .clipShape(Capsule())
        }
    }

    private func axisMenu(_ label: String, selection: Binding<ChartAxisOption>) -> some View {
        Menu {
            ForEach(ChartAxisOption.allCases) { option in
                Button(option.rawValue) { selection.wrappedValue = option }
            }
        } label: {
            HStack(spacing: 5) {
                Text("\(label):")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
                Text(selection.wrappedValue.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.bgElevated)
            .clipShape(Capsule())
        }
    }

    private var chart: some View {
        Chart(points) { point in
            PointMark(
                x: .value(xAxis.rawValue, point.x),
                y: .value(yAxis.rawValue, point.y)
            )
            .foregroundStyle(Theme.coverstockColor(point.ball.coverstockType))
            .symbolSize(sizeByWeight ? CGFloat(point.ball.weight - 10) * 32 : 130)
            .annotation(position: .top, alignment: .center, spacing: 2) {
                Text(point.ball.model)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .chartXAxisLabel(xAxis.rawValue)
        .chartYAxisLabel(yAxis.rawValue)
        .chartXScale(domain: .automatic(includesZero: false))
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 360)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        selectNearest(at: location, proxy: proxy, geo: geo)
                    }
            }
        }
    }

    /// Tap any dot to open that ball's detail (PRD 5.4.10 interactions).
    private func selectNearest(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geo[plotFrame].origin
        let plotLocation = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        var best: (point: ChartPoint, distance: CGFloat)?
        for point in points {
            guard let pos = proxy.position(for: (x: point.x, y: point.y)) else { continue }
            let distance = hypot(pos.x - plotLocation.x, pos.y - plotLocation.y)
            if best == nil || distance < best!.distance {
                best = (point, distance)
            }
        }
        if let best, best.distance < 44 {
            selectedBall = best.point.ball
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(CoverstockType.allCases) { type in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Theme.coverstockColor(type))
                        .frame(width: 8, height: 8)
                    Text(type.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }
}

/// Multi-select list of balls to plot (PRD 5.4.10 chart filter).
private struct ChartBallPickerSheet: View {
    let balls: [Ball]
    @Binding var selection: Set<UUID>
    @Environment(\.dismiss) private var dismiss

    private var sortedBalls: [Ball] {
        balls.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedBalls) { ball in
                    Button {
                        if selection.contains(ball.id) {
                            selection.remove(ball.id)
                        } else {
                            selection.insert(ball.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.coverstockColor(ball.coverstockType))
                            Text(ball.displayName)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if selection.contains(ball.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Filter Balls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") { selection = [] }
                        .disabled(selection.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
