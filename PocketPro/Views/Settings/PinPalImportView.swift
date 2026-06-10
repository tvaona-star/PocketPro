import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PocketProCore

/// PinPal import flow (PRD 13.3): explainer → file picker → preview → import.
struct PinPalImportView: View {
    @Environment(PinPalImportService.self) private var importer
    @Environment(\.modelContext) private var context

    @State private var showingPicker = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch importer.phase {
                case .idle:
                    explainer
                case .previewing:
                    if let preview = importer.preview {
                        previewView(preview)
                    }
                case .importing:
                    importingView
                case .done:
                    doneView
                case .failed(let message):
                    failedView(message)
                }
            }
            .padding()
        }
        .background(Theme.bgPrimary)
        .navigationTitle("Import from PinPal")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importer.loadFile(at: url)
            }
        }
    }

    // MARK: Step 1 — explainer (one screen: what imports, what doesn't)

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Bring your history with you")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            explainerCard(
                icon: "checkmark.circle.fill",
                color: Theme.success,
                title: "What imports",
                lines: [
                    "Sessions, dates, locations, league names",
                    "Game scores and frame-by-frame pin counts",
                    "Ball names (as records to complete later)",
                    "Oil pattern names and session notes",
                    "Spare conversion history — re-derived from frames",
                ]
            )

            explainerCard(
                icon: "xmark.circle.fill",
                color: Theme.textMuted,
                title: "What doesn't",
                lines: [
                    "Session types — PinPal has no league/tournament split; everything arrives as League, flagged for re-tagging",
                    "Ball specs, layouts, surface data — PinPal never stored them",
                    "Which pins were left — PinPal exports counts only, so imported frames are excluded from leave-type breakdowns",
                ]
            )

            Text("Import is additive — nothing in Pocket Pro gets overwritten, and re-importing the same file never duplicates (PRD 13.4).")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            Button {
                showingPicker = true
            } label: {
                Text("Choose File")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    private func explainerCard(icon: String, color: Color, title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: 6) {
                    Text("·")
                    Text(line)
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .card()
    }

    // MARK: Step 2 — preview before anything is written

    private func previewView(_ preview: PinPalImport.Preview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import preview")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            VStack(spacing: 2) {
                SpecRow(label: "Sessions found", value: "\(preview.sessionCount)")
                SpecRow(label: "Games found", value: "\(preview.gameCount)")
                if let range = preview.dateRange {
                    SpecRow(
                        label: "Date range",
                        value: "\(range.lowerBound.formatted(.dateTime.month(.abbreviated).year())) — \(range.upperBound.formatted(.dateTime.month(.abbreviated).year()))"
                    )
                }
                SpecRow(label: "Balls detected", value: "\(preview.ballNames.count) — will create incomplete arsenal records")
                SpecRow(label: "Patterns detected", value: "\(preview.patternNames.count) — type defaults to House Shot, review recommended")
                SpecRow(label: "Sessions needing re-tag", value: "\(preview.sessionCount) imported as League")
                if preview.gamesWithoutFrameData > 0 {
                    SpecRow(label: "Score-only games", value: "\(preview.gamesWithoutFrameData) — excluded from spare stats")
                }
            }
            .card()

            if !importer.issues.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(importer.issues.count) row issue\(importer.issues.count == 1 ? "" : "s") (skipped or partial)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                    ForEach(Array(importer.issues.prefix(5).enumerated()), id: \.offset) { _, issue in
                        Text("Row \(issue.row): \(issue.message)")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .card()
            }

            HStack(spacing: 10) {
                Button {
                    importer.runImport(context: context)
                } label: {
                    Text("Import")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button {
                    importer.reset()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.bgElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
    }

    private var importingView: some View {
        VStack(spacing: 14) {
            ProgressView(value: importer.progress)
                .tint(Theme.accent)
            Text("Importing… \(Int(importer.progress * 100))%")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 60)
    }

    private var doneView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.success)
            Text("Import complete — \(importer.importedSessionCount) sessions imported")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            VStack(spacing: 2) {
                if importer.skippedAsReimported > 0 {
                    SpecRow(label: "Skipped (already imported)", value: "\(importer.skippedAsReimported)")
                }
                if importer.duplicatesFlagged > 0 {
                    SpecRow(label: "Flagged as possible duplicates", value: "\(importer.duplicatesFlagged)")
                }
                if importer.shellBallsCreated > 0 {
                    SpecRow(label: "Ball records to complete", value: "\(importer.shellBallsCreated)")
                }
            }
            .card()

            NavigationLink {
                ImportReviewView()
            } label: {
                Text("Review imported data")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            Button("Import another file") {
                importer.reset()
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.accent)
        }
        .padding(.top, 40)
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.warning)
            Text(message)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
            Button("Try again") {
                importer.reset()
                showingPicker = true
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.accent)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}

/// Post-import review actions (PRD 13.3 step 4).
struct ImportReviewView: View {
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @Query private var balls: [Ball]
    @Query private var patterns: [Pattern]

    private var needsRetag: [Session] {
        sessions.filter { $0.needsTypeReview }
    }

    private var shellBalls: [Ball] {
        balls.filter { $0.importedShell }
    }

    private var reviewPatterns: [Pattern] {
        patterns.filter { $0.needsTypeReview }
    }

    private var duplicates: [Session] {
        sessions.filter { $0.flaggedAsPotentialDuplicate }
    }

    var body: some View {
        List {
            if needsRetag.isEmpty && shellBalls.isEmpty && reviewPatterns.isEmpty && duplicates.isEmpty {
                Text("Nothing to review — all imported data is squared away.")
                    .foregroundStyle(Theme.textSecondary)
            }

            if !needsRetag.isEmpty {
                Section {
                    ForEach(needsRetag) { session in
                        SessionRetagRow(session: session)
                    }
                } header: {
                    Text("Re-tag sessions (\(needsRetag.count))")
                } footer: {
                    Text("Imported sessions default to League — tag any tournaments or practice sessions.")
                }
            }

            if !shellBalls.isEmpty {
                Section("Complete ball records (\(shellBalls.count))") {
                    ForEach(shellBalls) { ball in
                        NavigationLink {
                            BallDetailView(ball: ball)
                        } label: {
                            HStack {
                                Text(ball.model)
                                Spacer()
                                Badge(text: "Add specs", color: Theme.warning)
                            }
                        }
                    }
                }
            }

            if !reviewPatterns.isEmpty {
                Section {
                    ForEach(reviewPatterns) { pattern in
                        PatternRetagRow(pattern: pattern)
                    }
                } header: {
                    Text("Review pattern types (\(reviewPatterns.count))")
                } footer: {
                    Text("Imported patterns default to House Shot — update any sport or tournament patterns.")
                }
            }

            if !duplicates.isEmpty {
                Section {
                    ForEach(duplicates) { session in
                        NavigationLink {
                            SessionDetailView(session: session)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.title)
                                Text(session.date, format: .dateTime.month().day().year())
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                } header: {
                    Text("Possible duplicates (\(duplicates.count))")
                } footer: {
                    Text("These match an existing session's date, location, and scores. Keep one or both — delete from the session list.")
                }
            }
        }
        .navigationTitle("Import Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SessionRetagRow: View {
    @Bindable var session: Session

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                Text(session.date, format: .dateTime.month().day().year())
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { session.type },
                set: { newType in
                    session.type = newType
                    session.needsTypeReview = false
                }
            )) {
                ForEach(SessionType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            Button("Keep") {
                session.needsTypeReview = false
            }
            .buttonStyle(.bordered)
            .font(.system(size: 12))
        }
    }
}

private struct PatternRetagRow: View {
    @Bindable var pattern: Pattern

    var body: some View {
        HStack {
            Text(pattern.name.isEmpty ? "Unnamed pattern" : pattern.name)
            Spacer()
            Picker("", selection: Binding(
                get: { pattern.type },
                set: { newType in
                    pattern.type = newType
                    pattern.needsTypeReview = false
                }
            )) {
                ForEach(PatternType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .labelsHidden()
            Button("Keep") {
                pattern.needsTypeReview = false
            }
            .buttonStyle(.bordered)
            .font(.system(size: 12))
        }
    }
}
