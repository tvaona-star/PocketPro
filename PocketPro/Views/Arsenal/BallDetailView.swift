import SwiftUI
import SwiftData
import PocketProCore

/// Ball detail (PRD 5.4.4 / 7.2): Tier 1 header + collapsible section cards.
/// Default state: Manufacturer Specs expanded, everything else collapsed (configurable).
struct BallDetailView: View {
    @Bindable var ball: Ball
    @Environment(\.modelContext) private var context
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @Query private var allBalls: [Ball]
    @AppStorage(SettingsKeys.ballDetailDefaultExpanded) private var defaultExpanded = "manufacturer"

    @State private var expandSpecs = true
    @State private var expandDetails = false
    @State private var expandLayout = false
    @State private var expandHistory = false
    @State private var expandSurface = false
    @State private var expandNotes = false
    @State private var expandSessions = false

    @State private var showingLayoutAssign = false
    @State private var showingSurfaceLog = false
    @State private var showingCompare = false
    @State private var showingCompleteShell = false

    private var ballSessions: [Session] {
        ArsenalActions.sessions(using: ball, in: sessions)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                if ball.importedShell {
                    shellBanner
                }

                manufacturerSpecsSection
                myDetailsSection
                layoutSection
                layoutHistorySection
                surfaceSection
                performanceNotesSection
                sessionHistorySection

                Button {
                    showingCompare = true
                } label: {
                    Label("Compare with another ball", systemImage: "rectangle.on.rectangle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.bgCard)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding()
        }
        .background(Theme.bgPrimary)
        .navigationTitle(ball.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: applyDefaultExpansion)
        .sheet(isPresented: $showingLayoutAssign) {
            LayoutAssignSheet(ball: ball)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingSurfaceLog) {
            SurfaceLogSheet(ball: ball, sessions: sessions)
                .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingCompare) {
            BallCompareView(initialA: ball)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showingCompleteShell) {
            AddBallFlow(shellToComplete: ball)
                .presentationDetents([.large])
        }
    }

    private func applyDefaultExpansion() {
        switch defaultExpanded {
        case "all":
            expandSpecs = true
            expandDetails = true
            expandLayout = true
            expandHistory = true
            expandSurface = true
            expandNotes = true
            expandSessions = true
        case "none":
            expandSpecs = false
        default:
            expandSpecs = true
        }
    }

    // MARK: Tier 1 header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if ball.imageURLString != nil {
                BallThumbnail(urlString: ball.imageURLString, coverstock: ball.coverstockType, size: 120)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            HStack {
                CoverstockBadge(type: ball.coverstockType)
                ThumbBadge(type: ball.thumbType)
                if !ball.active {
                    Badge(text: "Retired", color: Theme.textMuted)
                }
                Spacer()
                Text("\(ball.weight) lb")
                    .font(.system(size: 16, weight: .bold).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
            if let surface = ball.latestSurfaceLog {
                Text("Surface: \(surface.displayString) · prepped \(surface.date.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(Theme.cardSubtitle)
                    .foregroundStyle(Theme.textSecondary)
            }
            Toggle("In active arsenal", isOn: $ball.active)
                .font(.system(size: 14))
                .tint(Theme.accent)
        }
        .card()
    }

    private var shellBanner: some View {
        Button {
            showingCompleteShell = true
        } label: {
            HStack {
                Image(systemName: "square.and.arrow.down.on.square")
                    .foregroundStyle(Theme.warning)
                Text("Imported from PinPal — tap to search and add specs")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
            .card(padding: 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

    private var manufacturerSpecsSection: some View {
        SectionCard(title: "Manufacturer Specs", isExpanded: $expandSpecs) {
            Text([ball.coverstockName, ball.coreName].compactMap { $0 }.joined(separator: " · "))
        } content: {
            VStack(spacing: 2) {
                SpecRow(label: "Coverstock", value: ball.coverstockName ?? ball.coverstockType?.displayName ?? "—")
                SpecRow(label: "Core", value: ball.coreName ?? "—")
                SpecRow(label: "RG", value: ball.rg.map { String(format: "%.2f", $0) } ?? "—")
                SpecRow(label: "Differential", value: ball.diff.map { String(format: "%.3f", $0) } ?? "—")
                if ball.asymmetric {
                    SpecRow(label: "Int. Differential", value: ball.intDiff.map { String(format: "%.3f", $0) } ?? "—")
                }
                SpecRow(label: "Symmetry", value: ball.asymmetric ? "Asymmetric" : "Symmetric")
                SpecRow(label: "Factory Finish", value: ball.factoryFinish ?? "—")
                if ball.specIsFallback {
                    Text("Specs shown at 15 lb — \(ball.weight) lb not yet in database (PRD 9.4 fallback).")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
            }
        }
    }

    private var myDetailsSection: some View {
        SectionCard(title: "My Details", isExpanded: $expandDetails) {
            Text("\(ball.weight) lb\(ball.purchaseDate != nil ? " · purchased \(ball.purchaseDate!.formatted(.dateTime.month(.abbreviated).year()))" : "")")
        } content: {
            VStack(spacing: 2) {
                SpecRow(label: "Weight", value: "\(ball.weight) lb")
                SpecRow(label: "Purchased", value: ball.purchaseDate?.formatted(.dateTime.month().day().year()) ?? "—")
                SpecRow(label: "Thumb", value: ball.thumbType.displayName)
                if ball.thumbType == .slug {
                    SpecRow(label: "Slug Brand", value: ball.thumbSlugBrand ?? "—")
                    SpecRow(label: "Slug Material", value: ball.thumbSlugMaterial?.displayName ?? "—")
                }
                if ball.thumbType == .interchangeable {
                    SpecRow(label: "System", value: ball.thumbSystemBrand?.displayName ?? "—")
                    SpecRow(label: "Hole Size", value: ball.thumbHoleSize ?? "—")
                    SpecRow(label: "Hole Pitch", value: ball.thumbHolePitch ?? "—")
                }
                if !ball.drillingNotes.isEmpty {
                    SpecRow(label: "Drilling Notes", value: ball.drillingNotes)
                }
                HStack {
                    Text("Hook (1–10)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    ratingPicker(value: $ball.hookAmount)
                }
                HStack {
                    Text("Length (1–10)")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    ratingPicker(value: $ball.lengthRating)
                }
            }
        }
    }

    private func ratingPicker(value: Binding<Int?>) -> some View {
        Picker("", selection: value) {
            Text("—").tag(Int?.none)
            ForEach(1...10, id: \.self) { rating in
                Text("\(rating)").tag(Int?.some(rating))
            }
        }
        .labelsHidden()
    }

    private var layoutSection: some View {
        SectionCard(title: "Layout", isExpanded: $expandLayout) {
            Text(ball.activeLayout.map { "\($0.name) · \($0.system.shortName) · \($0.shorthand)" } ?? "No layout assigned")
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if let layout = ball.activeLayout {
                    LayoutSpecTable(layout: layout)
                } else {
                    Text("Assign a layout from your library.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textMuted)
                }
                Button {
                    showingLayoutAssign = true
                } label: {
                    Label(ball.activeLayout == nil ? "Assign Layout" : "Change Layout", systemImage: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var layoutHistorySection: some View {
        SectionCard(title: "Layout History", isExpanded: $expandHistory) {
            Text("\(ball.sortedLayoutHistory.filter { $0.archivedAt != nil }.count) past layout\(ball.sortedLayoutHistory.filter { $0.archivedAt != nil }.count == 1 ? "" : "s")")
        } content: {
            let history = ball.sortedLayoutHistory
            if history.isEmpty {
                Text("Layout changes are archived here with dates and reasons.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textMuted)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(history) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.layoutNameSnapshot)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                if entry.archivedAt == nil {
                                    Badge(text: "Active", color: Theme.success)
                                }
                                Spacer()
                            }
                            Text(entry.layoutSpecSnapshot)
                                .font(.system(size: 13).monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                            HStack(spacing: 4) {
                                Text(entry.becameActiveAt, format: .dateTime.month(.abbreviated).day().year())
                                if let archived = entry.archivedAt {
                                    Text("→")
                                    Text(archived, format: .dateTime.month(.abbreviated).day().year())
                                }
                                if let reason = entry.reason {
                                    Text("· \(reason.displayName)")
                                }
                                if let note = entry.reasonNote, !note.isEmpty {
                                    Text("· \(note)")
                                }
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                        }
                        if entry.id != history.last?.id {
                            Divider().overlay(Theme.separator)
                        }
                    }
                }
            }
        }
    }

    private var surfaceSection: some View {
        SectionCard(title: "Surface", isExpanded: $expandSurface) {
            if let latest = ball.latestSurfaceLog {
                Text("\(latest.displayString) · \(ArsenalActions.gamesSinceLastPrep(ball: ball, sessions: sessions)) games since prep")
            } else {
                Text(ball.factoryFinish.map { "Factory: \($0)" } ?? "No prep logged")
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(ball.sortedSurfaceLogs) { log in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(log.displayString)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(log.date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text("\(log.gamesSincePriorPrep) games on prior surface\(log.notes.isEmpty ? "" : " · \(log.notes)")")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                Button {
                    showingSurfaceLog = true
                } label: {
                    Label("Log Surface Prep", systemImage: "plus.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var performanceNotesSection: some View {
        SectionCard(title: "Performance Notes", isExpanded: $expandNotes) {
            Text("\(ball.performanceNoteCount) of \(PatternBucket.allCases.count) pattern types noted")
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(PatternBucket.allCases) { bucket in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(bucket.displayName.uppercased())
                            .font(Theme.statLabel)
                            .foregroundStyle(Theme.textSecondary)
                        TextField(
                            "How does this ball react?",
                            text: Binding(
                                get: { ball.performanceNote(for: bucket) },
                                set: { ball.setPerformanceNote($0, for: bucket) }
                            ),
                            axis: .vertical
                        )
                        .lineLimit(1...4)
                        .font(.system(size: 14))
                    }
                }
            }
        }
    }

    private var sessionHistorySection: some View {
        SectionCard(title: "Session History", isExpanded: $expandSessions) {
            if let recent = ballSessions.first {
                Text("\(ballSessions.count) sessions · last \(recent.date.formatted(.dateTime.month(.abbreviated).day()))")
            } else {
                Text("Not used in a session yet")
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(ballSessions.prefix(15)) { session in
                    NavigationLink {
                        SessionDetailView(session: session)
                    } label: {
                        HStack {
                            Text(session.date, format: .dateTime.month(.abbreviated).day().year())
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 100, alignment: .leading)
                            Text(session.pattern.map { $0.name.isEmpty ? $0.summary : $0.name } ?? session.title)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer()
                            Text(session.sortedGames.map { "\($0.finalScore)" }.joined(separator: " · "))
                                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Theme.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Full layout field table (used in ball detail and the layout library).
struct LayoutSpecTable: View {
    let layout: Layout

    var body: some View {
        VStack(spacing: 2) {
            SpecRow(label: "System", value: layout.system.displayName)
            if layout.system == .dualAngle {
                SpecRow(label: "Drilling Angle", value: layout.drillingAngle.map { Notation.degrees($0) } ?? "—")
                SpecRow(label: "Pin to PAP", value: layout.pinToPAP.map { Notation.inches($0) } ?? "—")
                SpecRow(label: "VAL Angle", value: layout.valAngle.map { Notation.degrees($0) } ?? "—")
            } else {
                SpecRow(label: "Pin to PAP", value: layout.pinToPAP.map { Notation.inches($0) } ?? "—")
                SpecRow(label: "CG to PAP", value: layout.cgToPAP.map { Notation.inches($0) } ?? "—")
                SpecRow(label: "Pin Buffer", value: layout.pinBuffer.map { Notation.inches($0) } ?? "—")
                SpecRow(label: "MB/PSA Distance", value: layout.mbPsaDistance.map { Notation.inches($0) } ?? "—")
            }
            if layout.hasDrillingSpecs {
                Divider().overlay(Theme.separator).padding(.vertical, 4)
                if let grip = layout.gripType {
                    SpecRow(label: "Grip", value: grip.displayName)
                }
                if let convention = layout.spanConvention {
                    SpecRow(label: "Span Convention", value: convention.displayName)
                }
                SpecRow(label: "Middle Span", value: layout.middleSpan.map { Notation.inches($0) } ?? "—")
                SpecRow(label: "Ring Span", value: layout.ringSpan.map { Notation.inches($0) } ?? "—")
                SpecRow(label: "Bridge Width", value: layout.bridgeWidth.map { Notation.inches($0) } ?? "—")
                SpecRow(label: "Middle Hole", value: layout.middleHoleSize ?? "—")
                SpecRow(label: "Ring Hole", value: layout.ringHoleSize ?? "—")
                SpecRow(label: "Middle Pitch", value: layout.middlePitch ?? "—")
                SpecRow(label: "Ring Pitch", value: layout.ringPitch ?? "—")
                SpecRow(label: "Thumb Hole", value: layout.thumbHoleSize ?? "—")
                SpecRow(label: "Thumb Pitch", value: layout.thumbPitch ?? "—")
            }
            if !layout.notes.isEmpty {
                SpecRow(label: "Notes", value: layout.notes)
            }
        }
    }
}
