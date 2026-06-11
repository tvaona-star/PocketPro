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
