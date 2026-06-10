import SwiftUI
import SwiftData
import PocketProCore

/// Ball comparison (PRD 5.4.9): any two balls, all specs side by side,
/// differing rows highlighted.
struct BallCompareView: View {
    var initialA: Ball?
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Ball.model) private var balls: [Ball]
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]

    @State private var ballA: Ball?
    @State private var ballB: Ball?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        ballPicker("Ball A", selection: $ballA)
                        ballPicker("Ball B", selection: $ballB)
                    }

                    if let a = ballA, let b = ballB {
                        compareTable(a, b)
                    } else {
                        Text("Pick two balls to compare every spec.")
                            .font(Theme.cardSubtitle)
                            .foregroundStyle(Theme.textMuted)
                            .padding(.top, 40)
                    }
                }
                .padding()
            }
            .background(Theme.bgPrimary)
            .navigationTitle("Compare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if ballA == nil { ballA = initialA }
            }
        }
    }

    private func ballPicker(_ label: String, selection: Binding<Ball?>) -> some View {
        Menu {
            ForEach(balls) { ball in
                Button(ball.displayName) { selection.wrappedValue = ball }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(Theme.statLabel)
                    .foregroundStyle(Theme.textMuted)
                Text(selection.wrappedValue?.displayName ?? "Select…")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(padding: 10)
        }
    }

    private func compareTable(_ a: Ball, _ b: Ball) -> some View {
        let rows = compareRows(a, b)
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.label)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 110, alignment: .leading)
                    Text(row.a)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(row.differs ? Theme.warning : Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.b)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                        .foregroundStyle(row.differs ? Theme.warning : Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(index.isMultiple(of: 2) ? Theme.bgCard : Theme.bgElevated.opacity(0.5))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCornerRadius, style: .continuous))
    }

    private struct CompareRow {
        let label: String
        let a: String
        let b: String
        var differs: Bool { a != b && a != "—" && b != "—" }
    }

    /// Full spec list per PRD 5.4.9 comparison table.
    private func compareRows(_ a: Ball, _ b: Ball) -> [CompareRow] {
        func row(_ label: String, _ va: String?, _ vb: String?) -> CompareRow {
            CompareRow(label: label, a: va ?? "—", b: vb ?? "—")
        }
        func inches(_ v: Double?) -> String? { v.map { Notation.inches($0) } }
        func degrees(_ v: Double?) -> String? { v.map { Notation.degrees($0) } }

        let layoutA = a.activeLayout
        let layoutB = b.activeLayout
        let prepA = a.latestSurfaceLog
        let prepB = b.latestSurfaceLog

        return [
            row("Brand / Model", a.displayName, b.displayName),
            row("Manufacturer", a.manufacturer.isEmpty ? nil : a.manufacturer, b.manufacturer.isEmpty ? nil : b.manufacturer),
            row("Coverstock Type", a.coverstockType?.displayName, b.coverstockType?.displayName),
            row("Coverstock Name", a.coverstockName, b.coverstockName),
            row("Core Name", a.coreName, b.coreName),
            row("Symmetry", a.asymmetric ? "Asymmetric" : "Symmetric", b.asymmetric ? "Asymmetric" : "Symmetric"),
            row("RG", a.rg.map { String(format: "%.2f", $0) }, b.rg.map { String(format: "%.2f", $0) }),
            row("Differential", a.diff.map { String(format: "%.3f", $0) }, b.diff.map { String(format: "%.3f", $0) }),
            row("Int. Differential", a.intDiff.map { String(format: "%.3f", $0) }, b.intDiff.map { String(format: "%.3f", $0) }),
            row("Weight", "\(a.weight) lb", "\(b.weight) lb"),
            row("Thumb Type", a.thumbType.displayName, b.thumbType.displayName),
            row("Thumb System", a.thumbSystemBrand?.displayName ?? a.thumbSlugBrand, b.thumbSystemBrand?.displayName ?? b.thumbSlugBrand),
            row("Surface Grit", prepA?.grit.displayName ?? a.factoryFinish, prepB?.grit.displayName ?? b.factoryFinish),
            row("Finish", prepA?.finishType.displayName, prepB?.finishType.displayName),
            row("Last Surface Prep", prepA?.date.formatted(.dateTime.month(.abbreviated).day().year()), prepB?.date.formatted(.dateTime.month(.abbreviated).day().year())),
            row("Games Since Prep", "\(ArsenalActions.gamesSinceLastPrep(ball: a, sessions: sessions))", "\(ArsenalActions.gamesSinceLastPrep(ball: b, sessions: sessions))"),
            row("Layout Name", layoutA?.name, layoutB?.name),
            row("Layout System", layoutA?.system.displayName, layoutB?.system.displayName),
            row("Drill Angle / Buffer", layoutA.flatMap { $0.system == .dualAngle ? degrees($0.drillingAngle) : inches($0.pinBuffer) },
                layoutB.flatMap { $0.system == .dualAngle ? degrees($0.drillingAngle) : inches($0.pinBuffer) }),
            row("Pin to PAP", inches(layoutA?.pinToPAP), inches(layoutB?.pinToPAP)),
            row("VAL Angle / CG-PAP", layoutA.flatMap { $0.system == .dualAngle ? degrees($0.valAngle) : inches($0.cgToPAP) },
                layoutB.flatMap { $0.system == .dualAngle ? degrees($0.valAngle) : inches($0.cgToPAP) }),
            row("Span Convention", layoutA?.spanConvention?.shortName, layoutB?.spanConvention?.shortName),
            row("Middle Span", inches(layoutA?.middleSpan), inches(layoutB?.middleSpan)),
            row("Ring Span", inches(layoutA?.ringSpan), inches(layoutB?.ringSpan)),
            row("Bridge Width", inches(layoutA?.bridgeWidth), inches(layoutB?.bridgeWidth)),
            row("Middle Hole", layoutA?.middleHoleSize, layoutB?.middleHoleSize),
            row("Ring Hole", layoutA?.ringHoleSize, layoutB?.ringHoleSize),
            row("Thumb Hole", layoutA?.thumbHoleSize ?? a.thumbHoleSize, layoutB?.thumbHoleSize ?? b.thumbHoleSize),
        ]
    }
}
