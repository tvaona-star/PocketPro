import SwiftUI
import PocketProCore

// MARK: - Spare breakdown panel (PRD 5.3, taxonomy per 5.5)

struct SpareBreakdownPanel: View {
    let games: [GameRecord]
    @State private var isExpanded = false

    private struct Bucket: Identifiable {
        let label: String
        let indent: Bool
        let predicate: (LeaveRecord) -> Bool
        var id: String { label }
    }

    /// Single Pins (all), with Corner Pins shown as an indented subset; then
    /// Multi Pins (non-split clusters) and Splits (all splits, including 7-10).
    private var buckets: [Bucket] {
        [
            Bucket(label: "Single Pins", indent: false) { $0.pins.count == 1 },
            Bucket(label: "Corner Pins", indent: true) { $0.pins.count == 1 && $0.categories.contains(.cornerPin) },
            Bucket(label: "Multi Pins", indent: false) { $0.pins.count >= 2 && !$0.categories.contains(.split) },
            Bucket(label: "Splits", indent: false) { $0.categories.contains(.split) },
        ]
    }

    var body: some View {
        SectionCard(title: "Spare Breakdown", isExpanded: $isExpanded) {
            Text(previewText)
        } content: {
            VStack(spacing: 6) {
                ForEach(buckets) { bucket in
                    breakdownRow(
                        label: bucket.label,
                        aggregate: StatsEngine.aggregate(games: games, matching: bucket.predicate),
                        indent: bucket.indent
                    )
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
                Color.clear.frame(width: 16)
            }
            Text(label)
                .font(.system(size: indent ? 13 : 14, weight: indent ? .regular : .medium))
                .foregroundStyle(indent ? Theme.textSecondary : Theme.textPrimary)
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
}

// MARK: - Strike clusters panel (PRD 5.3)

struct StrikeClustersPanel: View {
    let stats: DashboardStats
    let sessions: [Session]
    @State private var isExpanded = false

    private var firstBall: String {
        stats.firstBallAverage.map { Notation.oneDecimal($0) } ?? "--"
    }
    private var doublePct: String {
        Notation.percent(stats.doublesPercent)
    }
    private var turkeyPct: String {
        Notation.percent(stats.turkeyPercent)
    }
    private var totalClusters: Int {
        stats.streakCounts.values.reduce(0, +)
    }

    var body: some View {
        SectionCard(title: "Strike Clusters", isExpanded: $isExpanded) {
            Text("1st ball \(firstBall) · \(totalClusters) cluster\(totalClusters == 1 ? "" : "s")")
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    miniTile("1st Ball Avg", firstBall)
                    miniTile("Double %", doublePct)
                    miniTile("Turkey %", turkeyPct)
                }

                let lengths = stats.streakCounts.keys.sorted()
                if lengths.isEmpty {
                    Text("No back-to-back strikes yet.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textMuted)
                } else {
                    ForEach(lengths, id: \.self) { length in
                        HStack {
                            Text(clusterName(length))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text("\(stats.streakCounts[length] ?? 0)")
                                .font(.system(size: 15, weight: .bold).monospacedDigit())
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func miniTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(Theme.statNumber(20))
                .foregroundStyle(Theme.textPrimary)
            Text(label.uppercased())
                .font(Theme.statLabel)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func clusterName(_ length: Int) -> String {
        switch length {
        case 2: return "Doubles"
        case 3: return "Turkeys"
        case 4: return "Four-baggers"
        case 5: return "Five-baggers"
        case 6: return "Six-packs"
        case 12: return "Perfect games"
        default: return "\(length)-baggers"
        }
    }
}

// MARK: - Session averages by type (PRD 5.3: clean table, no chart)

struct SessionAveragesTable: View {
    let sessions: [Session]
    let leagueEvents: [LeagueEvent]
    let rangeStart: Date?
    let rangeEnd: Date?
    @State private var isExpanded = false

    /// Names marked as sport-pattern — matched by name so it covers sessions
    /// linked to a league only by name (e.g. imported PinPal weeks).
    private var sportNames: Set<String> {
        Set(leagueEvents.filter { $0.isSport }.map { $0.name.lowercased() })
    }

    private struct Category: Identifiable {
        let label: String
        let type: SessionType
        let sport: Bool
        var id: String { label }
    }

    /// Row 1: house League / Tournament. Row 2: Sport League / Sport Tournament.
    private let categories: [Category] = [
        Category(label: "League", type: .league, sport: false),
        Category(label: "Tournament", type: .tournament, sport: false),
        Category(label: "Sport League", type: .league, sport: true),
        Category(label: "Sport Tournament", type: .tournament, sport: true),
    ]

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        SectionCard(title: "Averages by Type", isExpanded: $isExpanded) {
            Text(previewText)
        } content: {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(categories) { box($0) }
            }
        }
    }

    private var previewText: String {
        let league = average(for: categories[0])
        return league.games > 0 ? "League avg \(league.value)" : "League · Tournament · Sport"
    }

    private func box(_ category: Category) -> some View {
        let result = average(for: category)
        return VStack(alignment: .leading, spacing: 3) {
            Text(category.label.uppercased())
                .font(Theme.statLabel)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(result.value)
                    .font(Theme.statNumber(22))
                    .foregroundStyle(result.games > 0 ? Theme.textPrimary : Theme.textMuted)
                if result.games > 0 {
                    Text("(\(result.games))")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func average(for category: Category) -> (value: String, games: Int) {
        let sport = sportNames
        let games = sessions
            .filter { session in
                if session.isActive || session.type != category.type { return false }
                let name = (session.leagueName ?? session.eventName ?? "").lowercased()
                if sport.contains(name) != category.sport { return false }
                if let rangeStart, session.date < rangeStart { return false }
                if let rangeEnd, session.date > rangeEnd { return false }
                return true
            }
            .flatMap { $0.gameRecords() }
        guard !games.isEmpty else { return ("--", 0) }
        let avg = Double(games.reduce(0) { $0 + $1.finalScore }) / Double(games.count)
        return (Notation.oneDecimal(avg), games.count)
    }
}
