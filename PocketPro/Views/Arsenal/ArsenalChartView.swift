import SwiftUI
import SwiftData
import Charts
import PocketProCore

/// Arsenal chart (PRD 5.4.10): configurable scatter of the active arsenal.
/// Any spec on either axis; dots colored by coverstock; sized by weight when
/// weight is on neither axis. Empty quadrants reveal arsenal gaps.
struct ArsenalChartView: View {
    @Query(filter: #Predicate<Ball> { $0.active }) private var balls: [Ball]

    @State private var xAxis: ChartAxisOption = .rg
    @State private var yAxis: ChartAxisOption = .diff
    @State private var selectedBall: Ball?

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

    private var points: [ChartPoint] {
        balls.compactMap { ball in
            guard let x = xAxis.value(for: ball), let y = yAxis.value(for: ball) else { return nil }
            return ChartPoint(id: ball.id, ball: ball, x: x, y: y)
        }
    }

    private var excludedCount: Int {
        balls.count - points.count
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
