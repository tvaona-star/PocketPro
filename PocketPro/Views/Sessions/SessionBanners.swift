import SwiftUI
import SwiftData
import PocketProCore

// MARK: - Banners shown at the top of the Sessions list

/// Post-import review banner (PRD 13.3 step 4).
struct ImportReviewBanner: View {
    let count: Int

    var body: some View {
        NavigationLink {
            ImportReviewView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count) imported session\(count == 1 ? "" : "s") to review")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Re-tag session types, complete ball records, review patterns")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textMuted)
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }
}

/// Prominent "get back into your in-progress session" banner — the primary way to
/// resume scoring now that starting and resuming both live in the Sessions tab.
struct ResumeSessionBanner: View {
    let session: Session
    var onResume: () -> Void

    private var subtitle: String {
        let games = session.sortedGames.count
        return "\(session.title) · \(games) game\(games == 1 ? "" : "s") in progress"
    }

    var body: some View {
        Button(action: onResume) {
            HStack(spacing: 12) {
                Image(systemName: "figure.bowling")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume session")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(14)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
