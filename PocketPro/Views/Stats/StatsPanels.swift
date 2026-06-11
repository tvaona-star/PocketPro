import SwiftUI
import PocketProCore

// MARK: - Trend strip (PRD 5.3: always visible at top of Stats)

struct TrendStripView: View {
    let games: [GameRecord]
    /// Unfiltered games used for the hot-stat comparison.
    let allGamesForHotStat: [GameRecord]

    private var trend: StatsEngine.Trend {
        StatsEngine.trend(games: games)
    }

    var body: some View {
        let points = trend.recentSessionAverages

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 14) {
                if points.count >= 2 {
                    TrendSparkline(values: points)
                        .frame(width: 120, height: 36)
                } else {
                    Text("Last 5 sessions")
                        .font(Theme.cardSubtitle)
                        .foregroundStyle(Theme.textMuted)
                }

                VStack(alignment: .leading, spacing: 2) {
                    if let last = points.last {
                        Text(Notation.oneDecimal(last))
                            .font(Theme.statNumber(24))
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Text("--")
                            .font(Theme.statNumber(24))
                            .foregroundStyle(Theme.textMuted)
                    }
                    Text("LAST 5 AVG")
                        .font(Theme.statLabel)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                if let delta = trend.deltaVsPrior {
                    TrendArrow(delta: delta)
                }
            }

            if let hot = hotStat {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warning)
                    Text(hot)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .card()
    }

    /// Biggest mover this month vs the prior month (PRD: one highlighted hot stat).
    private var hotStat: String? {
        let calendar = Calendar.current
        let now = Date()
        guard let monthAgo = calendar.date(byAdding: .month, value: -1, to: now),
              let twoMonthsAgo = calendar.date(byAdding: .month, value: -2, to: now) else { return nil }

        let current = allGamesForHotStat.filter { $0.date >= monthAgo }
        let prior = allGamesForHotStat.filter { $0.date >= twoMonthsAgo && $0.date < monthAgo }
        guard current.count >= 3, prior.count >= 3 else { return nil }

        let currentStats = StatsEngine.dashboard(games: current)
        let priorStats = StatsEngine.dashboard(games: prior)

        var candidates: [(String, Double)] = []
        if let c = currentStats.sparePercent, let p = priorStats.sparePercent {
            candidates.append(("Spare %", c - p))
        }
        if let c = currentStats.strikePercent, let p = priorStats.strikePercent {
            candidates.append(("Strike %", c - p))
        }
        if let c = currentStats.average, let p = priorStats.average {
            candidates.append(("Average", c - p))
        }
        guard let best = candidates.max(by: { abs($0.1) < abs($1.1) }), abs(best.1) >= 1 else { return nil }
        let direction = best.1 > 0 ? "up" : "down"
        let amount = best.0 == "Average" ? Notation.oneDecimal(abs(best.1)) : String(format: "%.0f points", abs(best.1))
        return "\(best.0) \(direction) \(amount) this month"
    }
}

/// Five dots on a simple line — no chart framework needed.
struct TrendSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let lo = (values.min() ?? 0) - 2
            let hi = (values.max() ?? 1) + 2
            let span = max(hi - lo, 1)
            let stepX = values.count > 1 ? geo.size.width / CGFloat(values.count - 1) : 0

            let point: (Int) -> CGPoint = { index in
                CGPoint(
                    x: CGFloat(index) * stepX,
                    y: geo.size.height * (1 - CGFloat((values[index] - lo) / span))
                )
            }

            ZStack {
                Path { path in
                    guard values.count > 1 else { return }
                    path.move(to: point(0))
                    for i in 1..<values.count {
                        path.addLine(to: point(i))
                    }
                }
                .stroke(Theme.accent.opacity(0.7), lineWidth: 2)

                ForEach(values.indices, id: \.self) { i in
                    Circle()
                        .fill(i == values.count - 1 ? Theme.accent : Theme.textSecondary)
                        .frame(width: 6, height: 6)
                        .position(point(i))
                }
            }
        }
    }
}

// MARK: - Spare breakdown panel (PRD 5.3, taxonomy per 5.5)

struct SpareBreakdownPanel: View {
    let games: [GameRecord]
    @State private var isExpanded = true
    @State private var singlesExpanded = false
    @State private var otherExpanded = false

    /// Breakdown rows in PRD order; "Splits" row added per DECISIONS.md D10.
    private let categories: [LeaveCategory] = [
        .singlePin, .cornerPin, .sleeper, .cluster, .washout,
        .babySplit, .split, .bigSplit, .bucket, .bigFour, .sevenTen, .other,
    ]

    var body: some View {
        SectionCard(title: "Spare Breakdown", isExpanded: $isExpanded) {
            Text(previewText)
        } content: {
            VStack(spacing: 6) {
                ForEach(categories) { category in
                    let aggregate = StatsEngine.categoryAggregate(games: games, category: category)
                    if aggregate.timesLeft > 0 {
                        breakdownRow(label: category.pluralDisplayName, aggregate: aggregate)
                        if category == .singlePin {
                            singlePinSubRows
                        }
                        if category == .other {
                            otherSubRows
                        }
                    }
                }
            }
        }
    }

    private var previewText: String {
        let all = StatsEngine.aggregate(games: games) { _ in true }
        return "\(all.timesLeft) leaves · \(Notation.percent(all.conversionPercent)) converted"
    }

    private func breakdownRow(label: String, aggregate: LeaveAggregate, indent: Bool = false) -> some View {
        HStack {
            if indent {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16)
            }
            Text(label)
                .font(.system(size: indent ? 13 : 14, weight: indent ? .regular : .medium))
                .foregroundStyle(indent ? Theme.textSecondary : Theme.textPrimary)
            if label == "Single Pins" {
                expandToggle($singlesExpanded)
            }
            if label == "Other" {
                expandToggle($otherExpanded)
            }
            Spacer()
            Text("\(aggregate.timesConverted)/\(aggregate.timesLeft)")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            Text(Notation.percent(aggregate.conversionPercent))
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.conversionColor(aggregate.conversionPercent))
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 3)
    }

    private func expandToggle(_ binding: Binding<Bool>) -> some View {
        Button {
            withAnimation(Theme.sectionSpring) {
                binding.wrappedValue.toggle()
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.textMuted)
                .rotationEffect(.degrees(binding.wrappedValue ? 180 : 0))
        }
        .buttonStyle(.plain)
    }

    /// Per-pin sub-rows (PRD: 10 sub-rows under Single Pins).
    @ViewBuilder
    private var singlePinSubRows: some View {
        if singlesExpanded {
            ForEach(1...10, id: \.self) { pin in
                let aggregate = StatsEngine.pinAggregate(games: games, pins: PinSet(pins: [pin]))
                if aggregate.timesLeft > 0 {
                    breakdownRow(label: "\(pin) Pin", aggregate: aggregate, indent: true)
                }
            }
        }
    }

    /// Every uncategorized combination — nothing is ever discarded (PRD 5.3).
    @ViewBuilder
    private var otherSubRows: some View {
        if otherExpanded {
            let entries = StatsEngine.leaveFrequency(games: games)
                .filter { $0.classification.primary == .other }
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                breakdownRow(label: entry.pins.displayString, aggregate: entry.aggregate, indent: true)
            }
        }
    }
}

// MARK: - Strike clusters panel (PRD 5.3)

struct StrikeClustersPanel: View {
    let stats: DashboardStats
    let sessions: [Session]
    @State private var isExpanded = true
    @State private var historyExpanded = false

    var body: some View {
        SectionCard(title: "Strike Clusters", isExpanded: $isExpanded) {
            Text("Most in a row \(stats.maxStreakInGame) · 1st ball \(stats.firstBallAverage.map { Notation.oneDecimal($0) } ?? "--")")
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    miniTile("Most in a Row", "\(stats.maxStreakInGame)")
                    miniTile("1st Ball Avg", stats.firstBallAverage.map { Notation.oneDecimal($0) } ?? "--")
                }

                if !stats.streakHistory.isEmpty {
                    Button {
                        withAnimation(Theme.sectionSpring) {
                            historyExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Text("Streak history (\(stats.streakHistory.count))")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.accent)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.accent)
                                .rotationEffect(.degrees(historyExpanded ? 180 : 0))
                        }
                    }
                    .buttonStyle(.plain)

                    if historyExpanded {
                        ForEach(Array(stats.streakHistory.prefix(20).enumerated()), id: \.offset) { _, streak in
                            HStack {
                                Text(streakName(streak.length))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(streak.length) in a row")
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textSecondary)
                                Spacer()
                                Text(streak.date, format: .dateTime.month(.abbreviated).day())
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }

    private func miniTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.statNumber(22))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(Theme.statLabel)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func streakName(_ length: Int) -> String {
        switch length {
        case 3: return "Turkey"
        case 4: return "Four-bagger"
        case 5: return "Five-bagger"
        case 6: return "Six-pack"
        default: return length >= 12 ? "Perfect run" : "\(length)-bagger"
        }
    }
}

// MARK: - Session averages by type (PRD 5.3: clean table, no chart)

struct SessionAveragesTable: View {
    let sessions: [Session]
    let rangeStart: Date?
    let rangeEnd: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Averages by Type")
                .font(Theme.cardTitle)
                .foregroundStyle(Theme.textPrimary)
            Grid(horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    ForEach(SessionType.allCases) { type in
                        Text(type.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                GridRow {
                    ForEach(SessionType.allCases) { type in
                        Text(average(for: type))
                            .font(.system(size: 18, weight: .bold).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .card()
    }

    private func average(for type: SessionType) -> String {
        let games = sessions
            .filter { session in
                if session.isActive || session.type != type { return false }
                if let rangeStart, session.date < rangeStart { return false }
                if let rangeEnd, session.date > rangeEnd { return false }
                return true
            }
            .flatMap { $0.gameRecords() }
        guard !games.isEmpty else { return "--" }
        let avg = Double(games.reduce(0) { $0 + $1.finalScore }) / Double(games.count)
        return Notation.oneDecimal(avg)
    }
}
