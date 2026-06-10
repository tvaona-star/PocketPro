import SwiftUI
import SwiftData
import PocketProCore

/// Leave detail (PRD 5.5.4): every occurrence of one pin combination — date,
/// session, game, frame, note — plus manual category override (PRD 5.5.3).
struct LeaveDetailView: View {
    let pins: PinSet
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]

    private var classification: LeaveClassification {
        LeaveClassifier.classify(pins)
    }

    private struct Occurrence: Identifiable {
        let id = UUID()
        let session: Session
        let game: Game
        let frame: Frame
        let leave: LeaveRecord
    }

    private var occurrences: [Occurrence] {
        var found: [Occurrence] = []
        for session in sessions where !session.isActive {
            for game in session.sortedGames {
                let leaves = game.derivedLeaves().filter { $0.pins == pins }
                for leave in leaves {
                    if let frame = game.sortedFrames.first(where: { $0.number - 1 == leave.frame }) {
                        found.append(Occurrence(session: session, game: game, frame: frame, leave: leave))
                    }
                }
            }
        }
        return found
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header

                ForEach(occurrences) { occurrence in
                    NavigationLink {
                        SessionDetailView(session: occurrence.session)
                    } label: {
                        occurrenceRow(occurrence)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .background(Theme.bgPrimary)
        .navigationTitle(classification.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        let aggregate = StatsEngine.pinAggregate(
            games: sessions.filter { !$0.isActive }.flatMap { $0.gameRecords() },
            pins: pins
        )
        return HStack(spacing: 16) {
            PinDiagram(standing: pins, size: 72)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    ForEach(classification.categories) { category in
                        Badge(text: category.displayName, color: category == .split || category == .bigSplit ? Theme.destructive : Theme.accent, filled: false)
                    }
                }
                Text("Left \(aggregate.timesLeft)× · converted \(aggregate.timesConverted) of \(aggregate.opportunities)")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                Text(Notation.percent(aggregate.conversionPercent))
                    .font(Theme.statNumber(30))
                    .foregroundStyle(Theme.conversionColor(aggregate.conversionPercent))
            }
            Spacer()
        }
        .card()
    }

    private func occurrenceRow(_ occurrence: Occurrence) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Badge(text: occurrence.session.type.displayName, color: Theme.sessionTypeColor(occurrence.session.type))
                    Text(occurrence.session.date, format: .dateTime.month(.abbreviated).day().year())
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text("Game \(occurrence.game.orderIndex + 1) · Frame \(occurrence.frame.number)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                if let note = occurrence.frame.note, !note.isEmpty {
                    Text(note)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(2)
                }
            }
            Spacer()
            if occurrence.leave.hadOpportunity {
                Image(systemName: occurrence.leave.converted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(occurrence.leave.converted ? Theme.success : Theme.destructive)
            } else {
                Text("fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .card(padding: 12)
    }
}

/// Miss log (PRD 5.5.4): chronological unconverted spare attempts; tap opens the session.
struct MissLogView: View {
    let sessions: [Session]
    let typeFilter: SessionType?
    let rangeStart: Date?
    let ballFilter: UUID?

    private struct Miss: Identifiable {
        let id = UUID()
        let session: Session
        let game: Game
        let leave: LeaveRecord
    }

    private var misses: [Miss] {
        var found: [Miss] = []
        for session in sessions {
            if session.isActive { continue }
            if let typeFilter, session.type != typeFilter { continue }
            if let rangeStart, session.date < rangeStart { continue }
            for game in session.sortedGames {
                if let ballFilter, !game.ballIDsUsed.contains(ballFilter) { continue }
                for leave in game.derivedLeaves() where leave.hadOpportunity && !leave.converted {
                    found.append(Miss(session: session, game: game, leave: leave))
                }
            }
        }
        return found
    }

    var body: some View {
        VStack(spacing: 8) {
            if misses.isEmpty {
                Text("No missed spares in this range. Clean bowling.")
                    .font(Theme.cardSubtitle)
                    .foregroundStyle(Theme.textMuted)
                    .padding(.vertical, 20)
            }
            ForEach(misses) { miss in
                NavigationLink {
                    SessionDetailView(session: miss.session)
                } label: {
                    HStack(spacing: 12) {
                        PinDiagram(standing: miss.leave.pins, size: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(miss.leave.classification.displayTitle)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("\(miss.session.date.formatted(.dateTime.month(.abbreviated).day())) · \(miss.session.type.displayName) · G\(miss.game.orderIndex + 1) F\(miss.leave.frame + 1)")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                    .card(padding: 12)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
