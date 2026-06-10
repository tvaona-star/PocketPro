import SwiftUI
import SwiftData
import PocketProCore

/// Bag builder (PRD 5.4.11): league, tournament, and practice bags with named variations.
struct BagBuilderView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bag.createdAt, order: .reverse) private var bags: [Bag]

    @State private var creating = false

    var body: some View {
        Group {
            if bags.isEmpty {
                EmptyStateView(
                    icon: "bag",
                    title: "Build your first bag",
                    message: "League, tournament, and practice bags with named variations for changing conditions.",
                    actionTitle: "New Bag",
                    action: { creating = true }
                )
            } else {
                List {
                    ForEach(BagType.allCases) { type in
                        let typed = bags.filter { $0.type == type }
                        if !typed.isEmpty {
                            Section(type.displayName + " Bags") {
                                ForEach(typed) { bag in
                                    NavigationLink {
                                        BagDetailView(bag: bag)
                                    } label: {
                                        bagRow(bag)
                                    }
                                    .listRowBackground(Theme.bgCard)
                                }
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.bgPrimary)
        .navigationTitle("Bag Builder")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $creating) {
            BagEditorSheet()
                .presentationDetents([.medium, .large])
        }
    }

    private func bagRow(_ bag: Bag) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(bag.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            HStack(spacing: 6) {
                if let league = bag.leagueName, !league.isEmpty {
                    Text(league)
                }
                if let event = bag.eventName, !event.isEmpty {
                    Text(event)
                }
                if let pattern = bag.pattern {
                    Text(pattern.name.isEmpty ? pattern.summary : pattern.name)
                }
                if let max = bag.maxBalls {
                    Text("\(max)-ball limit")
                }
                Text("\(bag.sortedVariations.count) variation\(bag.sortedVariations.count == 1 ? "" : "s")")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
        }
    }
}

struct BagEditorSheet: View {
    var bag: Bag?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Pattern.createdAt, order: .reverse) private var patterns: [Pattern]

    @State private var type: BagType = .league
    @State private var name = ""
    @State private var leagueName = ""
    @State private var eventName = ""
    @State private var pattern: Pattern?
    @State private var maxBalls: Int?

    var body: some View {
        NavigationStack {
            Form {
                Picker("Bag type", selection: $type) {
                    ForEach(BagType.allCases) { bagType in
                        Text(bagType.displayName).tag(bagType)
                    }
                }
                .pickerStyle(.segmented)

                TextField(namePlaceholder, text: $name)

                switch type {
                case .league:
                    TextField("League (name + day/season)", text: $leagueName)
                case .tournament:
                    TextField("Event name", text: $eventName)
                    Picker("Pattern", selection: $pattern) {
                        Text("None").tag(Pattern?.none)
                        ForEach(patterns) { p in
                            Text(p.name.isEmpty ? p.summary : p.name).tag(Pattern?.some(p))
                        }
                    }
                    Picker("Max balls", selection: $maxBalls) {
                        Text("Unlimited").tag(Int?.none)
                        Text("3-ball league rule").tag(Int?.some(3))
                        Text("6-ball").tag(Int?.some(6))
                        Text("8-ball").tag(Int?.some(8))
                    }
                case .practice:
                    EmptyView()
                }
            }
            .navigationTitle(bag == nil ? "New Bag" : "Edit Bag")
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

    private var namePlaceholder: String {
        switch type {
        case .league: return "Bag name (e.g. Tuesday standard carry)"
        case .tournament: return "Bag name (e.g. US Open 2026)"
        case .practice: return "Intent (e.g. Surface testing)"
        }
    }

    private func populate() {
        guard let bag else { return }
        type = bag.type
        name = bag.name
        leagueName = bag.leagueName ?? ""
        eventName = bag.eventName ?? ""
        pattern = bag.pattern
        maxBalls = bag.maxBalls
    }

    private func save() {
        let target = bag ?? Bag()
        target.type = type
        target.name = name
        target.leagueName = leagueName.isEmpty ? nil : leagueName
        target.eventName = eventName.isEmpty ? nil : eventName
        target.pattern = type == .tournament ? pattern : nil
        target.maxBalls = type == .tournament ? maxBalls : nil
        if bag == nil {
            let defaultVariation = BagVariation()
            defaultVariation.name = "Default"
            defaultVariation.bag = target
            context.insert(target)
            context.insert(defaultVariation)
        }
        dismiss()
    }
}

/// Bag detail: variations with ordered ball slots, role labels, and service status.
struct BagDetailView: View {
    @Bindable var bag: Bag
    @Environment(\.modelContext) private var context
    @Query private var balls: [Ball]
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]

    @State private var editingBag = false
    @State private var newVariationName = ""
    @State private var addingVariation = false

    var body: some View {
        List {
            Section {
                HStack {
                    Badge(text: bag.type.displayName, color: Theme.accent)
                    if let pattern = bag.pattern {
                        Text(pattern.name.isEmpty ? pattern.summary : "\(pattern.name) · \(pattern.summary)")
                            .font(Theme.cardSubtitle)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    if let max = bag.maxBalls {
                        Text("Max \(max)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowBackground(Theme.bgCard)
            }

            ForEach(bag.sortedVariations) { variation in
                BagVariationSection(bag: bag, variation: variation, balls: balls, sessions: sessions)
            }

            Section {
                if addingVariation {
                    HStack {
                        TextField("Variation name (e.g. If burned)", text: $newVariationName)
                        Button("Add") {
                            let variation = BagVariation()
                            variation.name = newVariationName
                            variation.orderIndex = (bag.sortedVariations.last?.orderIndex ?? -1) + 1
                            variation.bag = bag
                            context.insert(variation)
                            newVariationName = ""
                            addingVariation = false
                        }
                        .disabled(newVariationName.isEmpty)
                    }
                    .listRowBackground(Theme.bgCard)
                } else {
                    Button {
                        addingVariation = true
                    } label: {
                        Label("Add variation", systemImage: "plus")
                    }
                    .listRowBackground(Theme.bgCard)
                }
            } footer: {
                Text("Variations are named ball orders for different scenarios — e.g. 'Fresh', 'Burned', 'Match play'.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.bgPrimary)
        .navigationTitle(bag.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editingBag = true }
            }
        }
        .sheet(isPresented: $editingBag) {
            BagEditorSheet(bag: bag)
                .presentationDetents([.medium, .large])
        }
    }
}

private struct BagVariationSection: View {
    let bag: Bag
    @Bindable var variation: BagVariation
    let balls: [Ball]
    let sessions: [Session]
    @Environment(\.modelContext) private var context

    @State private var addingBall = false

    private var atLimit: Bool {
        if let max = bag.maxBalls {
            return variation.slots.count >= max
        }
        return false
    }

    var body: some View {
        Section(variation.name) {
            ForEach(variation.sortedSlots) { slot in
                slotRow(slot)
                    .listRowBackground(Theme.bgCard)
            }
            .onDelete { offsets in
                let sorted = variation.sortedSlots
                for index in offsets {
                    variation.slots.removeAll { $0.id == sorted[index].id }
                }
            }
            .onMove { source, destination in
                var sorted = variation.sortedSlots
                sorted.move(fromOffsets: source, toOffset: destination)
                for (order, var slot) in sorted.enumerated() {
                    slot.order = order
                    if let idx = variation.slots.firstIndex(where: { $0.id == slot.id }) {
                        variation.slots[idx] = slot
                    }
                }
            }

            if addingBall {
                ballPicker
                    .listRowBackground(Theme.bgCard)
            } else {
                Button {
                    addingBall = true
                } label: {
                    Label(atLimit ? "Ball limit reached" : "Add ball", systemImage: "plus")
                }
                .disabled(atLimit)
                .listRowBackground(Theme.bgCard)
            }
        }
    }

    private func slotRow(_ slot: BagSlot) -> some View {
        let ball = balls.first { $0.id == slot.ballID }
        return HStack(spacing: 10) {
            Text("\(slot.order + 1)")
                .font(.system(size: 12, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.textMuted)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(ball?.displayName ?? "Missing ball")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                // Service status at a glance (PRD 5.4.11).
                if let ball {
                    HStack(spacing: 6) {
                        if let layout = ball.activeLayout {
                            Text(layout.name)
                        }
                        if let prep = ball.latestSurfaceLog {
                            Text("\(prep.grit.displayName) · \(prep.date.formatted(.dateTime.month(.abbreviated).day()))")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            if bag.type != .practice {
                Menu {
                    Button("No role") { setRole(slot, role: nil) }
                    ForEach(BallRole.allCases) { role in
                        Button(role.displayName) { setRole(slot, role: role.displayName) }
                    }
                } label: {
                    Badge(text: slot.roleLabel ?? "Role", color: slot.roleLabel == nil ? Theme.textMuted : Theme.accent, filled: slot.roleLabel != nil)
                }
            }
        }
    }

    private var ballPicker: some View {
        Menu("Choose ball…") {
            ForEach(balls.filter { $0.active }) { ball in
                Button(ball.displayName) {
                    let slot = BagSlot(ballID: ball.id, roleLabel: nil, order: (variation.sortedSlots.last?.order ?? -1) + 1)
                    variation.slots.append(slot)
                    addingBall = false
                }
            }
        }
    }

    private func setRole(_ slot: BagSlot, role: String?) {
        if let index = variation.slots.firstIndex(where: { $0.id == slot.id }) {
            variation.slots[index].roleLabel = role
        }
    }
}
