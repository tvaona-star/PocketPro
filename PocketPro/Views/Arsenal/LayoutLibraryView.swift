import SwiftUI
import SwiftData
import PocketProCore

/// Layout library (PRD 5.4.5): a reference card, not a form. Layouts exist
/// independently of balls and are assigned with one tap (PRD 7.5).
struct LayoutLibraryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Layout.createdAt, order: .reverse) private var layouts: [Layout]
    @Query private var balls: [Ball]

    @State private var editingLayout: Layout?
    @State private var creatingLayout = false
    @State private var deleteBlockedMessage: String?

    var body: some View {
        Group {
            if layouts.isEmpty {
                EmptyStateView(
                    icon: "scribble.variable",
                    title: "Create a layout to assign to your balls.",
                    message: "Dual Angle and VLS systems, with full pro-shop drilling specs.",
                    actionTitle: "New Layout",
                    action: { creatingLayout = true }
                )
            } else {
                List {
                    ForEach(layouts) { layout in
                        Button {
                            editingLayout = layout
                        } label: {
                            layoutRow(layout)
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                attemptDelete(layout)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.bgPrimary)
        .navigationTitle("Layout Library")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creatingLayout = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $creatingLayout) {
            LayoutEditorView(layout: nil)
                .presentationDetents([.large])
        }
        .sheet(item: $editingLayout) { layout in
            LayoutEditorView(layout: layout)
                .presentationDetents([.large])
        }
        .alert("Layout in use", isPresented: Binding(
            get: { deleteBlockedMessage != nil },
            set: { if !$0 { deleteBlockedMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteBlockedMessage ?? "")
        }
    }

    private func layoutRow(_ layout: Layout) -> some View {
        let activeOn = balls.filter { $0.activeLayout === layout }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(layout.name)
                    .font(Theme.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Badge(text: layout.system.shortName, color: Theme.accent, filled: false)
                Spacer()
            }
            Text(layout.shorthand)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            if !activeOn.isEmpty {
                Text("Active on: \(activeOn.map { $0.displayName }.joined(separator: ", "))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .card()
    }

    /// PRD 5.4.6: deletable only when not active on any ball.
    private func attemptDelete(_ layout: Layout) {
        if ArsenalActions.canDelete(layout: layout, balls: balls) {
            context.delete(layout)
        } else {
            let names = balls.filter { $0.activeLayout === layout }.map { $0.displayName }
            deleteBlockedMessage = "This layout is active on \(names.joined(separator: ", ")). Assign a different layout to those balls first."
        }
    }
}

/// Layout create/edit form (PRD 5.4.5) — the only time the form appears (PRD 7.5).
struct LayoutEditorView: View {
    let layout: Layout?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var profiles: [BowlerProfile]

    @State private var name = ""
    @State private var system: LayoutSystem = .dualAngle
    @State private var drillingAngle: Double?
    @State private var pinToPAP: Double?
    @State private var valAngle: Double?
    @State private var cgToPAP: Double?
    @State private var pinBuffer: Double?
    @State private var mbPsaDistance: Double?
    @State private var includeDrilling = false
    @State private var gripType: GripType = .fingertip
    @State private var spanConvention: SpanConvention = .edgeToEdge
    @State private var middleSpan: Double?
    @State private var ringSpan: Double?
    @State private var bridgeWidth: Double?
    @State private var middleHoleSize = ""
    @State private var ringHoleSize = ""
    @State private var middlePitch = ""
    @State private var ringPitch = ""
    @State private var thumbHoleSize = ""
    @State private var thumbPitch = ""
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                // PAP surfaced where relevant (PRD 5.4.1: not buried).
                if let profile = profiles.first, profile.papOver != nil {
                    Section {
                        LabeledContent("Your PAP", value: profile.papDisplay)
                    }
                }

                Section("Layout") {
                    TextField("Name (e.g. Strong 50x4 3/4x40)", text: $name)
                    Picker("Drill system", selection: $system) {
                        ForEach(LayoutSystem.allCases) { sys in
                            Text(sys.displayName).tag(sys)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if system == .dualAngle {
                    Section("Dual Angle") {
                        measureField("Drilling angle (°)", value: $drillingAngle)
                        measureField("Pin to PAP (in)", value: $pinToPAP, fraction: true)
                        measureField("VAL angle (°)", value: $valAngle)
                    }
                } else {
                    Section("VLS") {
                        measureField("Pin to PAP (in)", value: $pinToPAP, fraction: true)
                        measureField("CG to PAP (in)", value: $cgToPAP, fraction: true)
                        measureField("Pin buffer (in)", value: $pinBuffer, fraction: true)
                        measureField("MB / PSA distance (in, asym only)", value: $mbPsaDistance, fraction: true)
                    }
                }

                Section {
                    Toggle("Drilling specs (pro shop drill card)", isOn: $includeDrilling)
                    if includeDrilling {
                        Picker("Grip type", selection: $gripType) {
                            ForEach(GripType.allCases) { grip in
                                Text(grip.displayName).tag(grip)
                            }
                        }
                        Picker("Span convention", selection: $spanConvention) {
                            ForEach(SpanConvention.allCases) { convention in
                                Text(convention.displayName).tag(convention)
                            }
                        }
                        .pickerStyle(.segmented)
                        measureField("Middle finger span (in)", value: $middleSpan, fraction: true)
                        measureField("Ring finger span (in)", value: $ringSpan, fraction: true)
                        measureField("Bridge width (in)", value: $bridgeWidth, fraction: true)
                        TextField("Middle hole size (e.g. 31/32\")", text: $middleHoleSize)
                        TextField("Ring hole size (e.g. 31/32\")", text: $ringHoleSize)
                        TextField("Middle pitch (e.g. 1/8\" left, 3/8\" up)", text: $middlePitch)
                        TextField("Ring pitch (e.g. 1/8\" right, 1/4\" down)", text: $ringPitch)
                        TextField("Thumb hole size (e.g. 63/64\" oval)", text: $thumbHoleSize)
                        TextField("Thumb pitch (e.g. 1/8\" reverse)", text: $thumbPitch)
                    }
                } footer: {
                    if includeDrilling {
                        Text("Spans recorded \(spanConvention.displayName) — matches how your driller measures, usable at the pro shop without conversion.")
                    }
                }

                Section("Notes") {
                    TextField("Driller, pro shop, special instructions", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle(layout == nil ? "New Layout" : "Edit Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty)
                }
            }
            .onAppear(perform: populate)
        }
    }

    /// `fraction: true` for inches fields (accepts 4 1/2 / 4½); degrees stay plain decimals.
    private func measureField(_ label: String, value: Binding<Double?>, fraction: Bool = false) -> some View {
        HStack {
            Text(label)
            Spacer()
            OptionalNumberField(placeholder: "—", value: value, allowsFractions: fraction)
                .frame(width: 90)
        }
    }

    private func populate() {
        guard let layout else { return }
        name = layout.name
        system = layout.system
        drillingAngle = layout.drillingAngle
        pinToPAP = layout.pinToPAP
        valAngle = layout.valAngle
        cgToPAP = layout.cgToPAP
        pinBuffer = layout.pinBuffer
        mbPsaDistance = layout.mbPsaDistance
        includeDrilling = layout.hasDrillingSpecs
        gripType = layout.gripType ?? .fingertip
        spanConvention = layout.spanConvention ?? .edgeToEdge
        middleSpan = layout.middleSpan
        ringSpan = layout.ringSpan
        bridgeWidth = layout.bridgeWidth
        middleHoleSize = layout.middleHoleSize ?? ""
        ringHoleSize = layout.ringHoleSize ?? ""
        middlePitch = layout.middlePitch ?? ""
        ringPitch = layout.ringPitch ?? ""
        thumbHoleSize = layout.thumbHoleSize ?? ""
        thumbPitch = layout.thumbPitch ?? ""
        notes = layout.notes
    }

    private func save() {
        let target = layout ?? Layout()
        target.name = name
        target.system = system
        target.drillingAngle = system == .dualAngle ? drillingAngle : nil
        target.valAngle = system == .dualAngle ? valAngle : nil
        target.pinToPAP = pinToPAP
        target.cgToPAP = system == .vls ? cgToPAP : nil
        target.pinBuffer = system == .vls ? pinBuffer : nil
        target.mbPsaDistance = system == .vls ? mbPsaDistance : nil
        if includeDrilling {
            target.gripType = gripType
            target.spanConvention = spanConvention
            target.middleSpan = middleSpan
            target.ringSpan = ringSpan
            target.bridgeWidth = bridgeWidth
            target.middleHoleSize = middleHoleSize.isEmpty ? nil : middleHoleSize
            target.ringHoleSize = ringHoleSize.isEmpty ? nil : ringHoleSize
            target.middlePitch = middlePitch.isEmpty ? nil : middlePitch
            target.ringPitch = ringPitch.isEmpty ? nil : ringPitch
            target.thumbHoleSize = thumbHoleSize.isEmpty ? nil : thumbHoleSize
            target.thumbPitch = thumbPitch.isEmpty ? nil : thumbPitch
        } else {
            target.gripTypeRaw = nil
            target.spanConventionRaw = nil
            target.middleSpan = nil
            target.ringSpan = nil
            target.bridgeWidth = nil
            target.middleHoleSize = nil
            target.ringHoleSize = nil
            target.middlePitch = nil
            target.ringPitch = nil
            target.thumbHoleSize = nil
            target.thumbPitch = nil
        }
        target.notes = notes
        if layout == nil {
            context.insert(target)
        }
        dismiss()
    }
}

/// One-tap layout assignment with automatic archival (PRD 5.4.6).
struct LayoutAssignSheet: View {
    let ball: Ball
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Layout.createdAt, order: .reverse) private var layouts: [Layout]

    @State private var selectedLayout: Layout?
    @State private var reason: LayoutChangeReason = .redrilled
    @State private var reasonNote = ""
    @State private var creatingLayout = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Select layout") {
                    ForEach(layouts) { layout in
                        Button {
                            selectedLayout = layout
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(layout.name)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\(layout.system.shortName) · \(layout.shorthand)")
                                        .font(Theme.cardSubtitle)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if selectedLayout === layout {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                    Button {
                        creatingLayout = true
                    } label: {
                        Label("New Layout", systemImage: "plus")
                            .foregroundStyle(Theme.accent)
                    }
                }

                if ball.activeLayout != nil {
                    Section("Why the change?") {
                        Picker("Reason", selection: $reason) {
                            ForEach(LayoutChangeReason.allCases) { changeReason in
                                Text(changeReason.displayName).tag(changeReason)
                            }
                        }
                        TextField("Note (optional)", text: $reasonNote)
                    }
                }
            }
            .navigationTitle("Assign Layout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Assign") {
                        if let selectedLayout {
                            ArsenalActions.assignLayout(
                                selectedLayout,
                                to: ball,
                                reason: ball.activeLayout == nil ? .newPurchase : reason,
                                reasonNote: reasonNote.isEmpty ? nil : reasonNote,
                                context: context
                            )
                        }
                        dismiss()
                    }
                    .disabled(selectedLayout == nil)
                }
            }
            .sheet(isPresented: $creatingLayout) {
                LayoutEditorView(layout: nil)
                    .presentationDetents([.large])
            }
        }
    }
}

/// Surface prep entry (PRD 5.4.7).
struct SurfaceLogSheet: View {
    let ball: Ball
    let sessions: [Session]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var grit: SurfaceGrit = .grit2000
    @State private var finish: FinishType = .abralon
    @State private var notes = ""

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Picker("Grit applied", selection: $grit) {
                    ForEach(SurfaceGrit.allCases) { gritOption in
                        Text(gritOption.displayName).tag(gritOption)
                    }
                }
                Picker("Finish type", selection: $finish) {
                    ForEach(FinishType.allCases) { finishOption in
                        Text(finishOption.displayName).tag(finishOption)
                    }
                }
                LabeledContent("Games since last prep", value: "\(ArsenalActions.gamesSinceLastPrep(ball: ball, sessions: sessions))")
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }
            .navigationTitle("Surface Prep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let log = SurfaceLog()
                        log.ball = ball
                        log.date = date
                        log.grit = grit
                        log.finishType = finish
                        log.gamesSincePriorPrep = ArsenalActions.gamesSinceLastPrep(ball: ball, sessions: sessions)
                        log.notes = notes
                        context.insert(log)
                        dismiss()
                    }
                }
            }
        }
    }
}
