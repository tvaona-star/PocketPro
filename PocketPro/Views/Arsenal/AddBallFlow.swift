import SwiftUI
import SwiftData
import PocketProCore

/// Add-ball flow (PRD 5.4.2): search the database, auto-populate read-only specs,
/// add personal fields. Manual entry fallback when the ball isn't found.
struct AddBallFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(BallDatabaseService.self) private var ballDB
    @Query private var profiles: [BowlerProfile]

    /// When set, this flow completes an imported shell record instead of creating a new ball.
    var shellToComplete: Ball?

    @State private var query = ""
    @State private var brandFilter: String?
    @State private var selectedRecord: BallDBRecord?
    @State private var manualEntry = false

    private var defaultWeight: Int {
        profiles.first?.defaultBallWeight ?? 15
    }

    private var results: [BallDBRecord] {
        var found = ballDB.search(query)
        if let brandFilter {
            found = found.filter { $0.brand == brandFilter }
        }
        return found.sorted {
            ($0.year ?? 0, $0.model) > ($1.year ?? 0, $1.model)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let record = selectedRecord {
                    BallPersonalFieldsForm(
                        record: record,
                        shellToComplete: shellToComplete,
                        defaultWeight: defaultWeight,
                        onSaved: { dismiss() }
                    )
                } else if manualEntry {
                    ManualBallForm(
                        shellToComplete: shellToComplete,
                        prefillName: query,
                        defaultWeight: defaultWeight,
                        onSaved: { dismiss() }
                    )
                } else {
                    searchView
                }
            }
            .navigationTitle(shellToComplete != nil ? "Complete Ball Record" : "Add Ball")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if selectedRecord != nil || manualEntry {
                        Button("Back") {
                            selectedRecord = nil
                            manualEntry = false
                        }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }

    private var searchView: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                TextField("Search by brand or model", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(label: "All brands", isActive: brandFilter == nil) {
                            brandFilter = nil
                        }
                        ForEach(ballDB.brands, id: \.self) { brand in
                            FilterChip(label: brand, isActive: brandFilter == brand) {
                                brandFilter = brandFilter == brand ? nil : brand
                            }
                        }
                    }
                }
            }
            .padding()

            List {
                ForEach(results) { record in
                    Button {
                        selectedRecord = record
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.displayName)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                HStack(spacing: 6) {
                                    Text(record.coreName ?? "")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Theme.textSecondary)
                                    if let year = record.year {
                                        Text(String(year))
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.textMuted)
                                    }
                                    if record.brandStatus == "retired" {
                                        Badge(text: "Retired brand", color: Theme.textMuted)
                                    }
                                }
                            }
                            Spacer()
                            CoverstockBadge(type: record.coverstockType)
                        }
                    }
                    .listRowBackground(Theme.bgCard)
                }

                Section {
                    Button {
                        manualEntry = true
                    } label: {
                        Label("Ball not listed — enter manually", systemImage: "square.and.pencil")
                            .foregroundStyle(Theme.accent)
                    }
                    .listRowBackground(Theme.bgCard)
                } footer: {
                    Text("Manual entries can be reported so the ball gets added to the database for everyone (PRD 9.3 QA queue).")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(Theme.bgPrimary)
    }
}

/// Step 2 after DB selection: read-only manufacturer specs + bowler's personal fields.
struct BallPersonalFieldsForm: View {
    let record: BallDBRecord
    var shellToComplete: Ball?
    let defaultWeight: Int
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(BallDatabaseService.self) private var ballDB

    @State private var weight: Int = 15
    @State private var rgText = ""
    @State private var diffText = ""
    @State private var intDiffText = ""
    @State private var specIsFallback = false
    @State private var purchaseDate = Date()
    @State private var hasPurchaseDate = false
    @State private var thumbType: ThumbType = .noThumb
    @State private var slugBrand = ""
    @State private var slugMaterial: SlugMaterial = .urethane
    @State private var systemBrand: ThumbSystemBrand = .viseIT
    @State private var holeSize = ""
    @State private var holePitch = ""
    @State private var notes = ""

    var body: some View {
        Form {
            if record.imageURL != nil {
                Section {
                    BallThumbnail(urlString: record.imageURL, coverstock: record.coverstockType, size: 120)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                }
            }
            Section {
                LabeledContent("Ball", value: record.displayName)
                LabeledContent("Coverstock", value: record.coverstockName ?? record.coverstockType.displayName)
                LabeledContent("Core", value: record.coreName ?? "—")
                LabeledContent("Symmetry", value: record.asymmetric ? "Asymmetric" : "Symmetric")
                specField("RG", text: $rgText)
                specField("Differential", text: $diffText)
                if record.asymmetric {
                    specField("Int. Diff", text: $intDiffText)
                }
                if specIsFallback {
                    Text("No \(weight) lb specs in the database — showing 15 lb. Edit to match your ball.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.warning)
                }
                if let finish = record.factoryFinish {
                    LabeledContent("Factory Finish", value: finish)
                }
                let siblings = ballDB.sharedCoreSiblings(of: record)
                if !siblings.isEmpty {
                    LabeledContent("Shared core", value: siblings.map { $0.displayName }.joined(separator: ", "))
                }
            } header: {
                Text("Specs")
            } footer: {
                Text("Pre-filled from the database — edit RG / differential to match your ball or pro-shop sheet.")
            }

            Section("My Ball") {
                Picker("Weight", selection: $weight) {
                    ForEach(12...16, id: \.self) { lbs in
                        Text("\(lbs) lb").tag(lbs)
                    }
                }
                Toggle("Purchase date", isOn: $hasPurchaseDate)
                if hasPurchaseDate {
                    DatePicker("Purchased", selection: $purchaseDate, displayedComponents: .date)
                }
            }

            thumbSection

            Section("Drilling Intent Notes") {
                TextField("e.g. drill it long and clean for fresh", text: $notes, axis: .vertical)
                    .lineLimit(2...4)
            }

            Button("Add to Arsenal") {
                save()
            }
            .font(.system(size: 16, weight: .semibold))
        }
        .onAppear {
            weight = shellToComplete?.weight ?? defaultWeight
            loadSpec()
        }
        .onChange(of: weight) { _, _ in loadSpec() }
    }

    private func specField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }

    /// Pre-fill the editable spec fields from the database at the chosen weight.
    private func loadSpec() {
        if let (spec, isFallback) = record.spec(atWeight: weight) {
            rgText = Self.trim(spec.rg)
            diffText = Self.trim(spec.diff)
            intDiffText = spec.intDiff.map(Self.trim) ?? ""
            specIsFallback = isFallback
        } else {
            specIsFallback = false
        }
    }

    private static func trim(_ v: Double) -> String {
        String(format: "%g", v)
    }

    @ViewBuilder
    private var thumbSection: some View {
        Section("Thumb Type") {
            Picker("Thumb", selection: $thumbType) {
                ForEach(ThumbType.allCases) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            switch thumbType {
            case .noThumb:
                EmptyView()
            case .slug:
                TextField("Slug brand", text: $slugBrand)
                Picker("Slug material", selection: $slugMaterial) {
                    ForEach(SlugMaterial.allCases) { material in
                        Text(material.displayName).tag(material)
                    }
                }
            case .interchangeable:
                Picker("System brand", selection: $systemBrand) {
                    ForEach(ThumbSystemBrand.allCases) { brand in
                        Text(brand.displayName).tag(brand)
                    }
                }
                TextField("Hole size (shell hole, e.g. 1 1/4\")", text: $holeSize)
                TextField("Hole pitch (e.g. 1/8\" forward)", text: $holePitch)
            }
        }
    }

    private func save() {
        let ball = shellToComplete ?? Ball()
        ArsenalActions.apply(record: record, to: ball, weight: weight)
        // Persist any edits to the specs — the bowler's number wins over the DB default.
        if let rg = Double(rgText) { ball.rg = rg }
        if let diff = Double(diffText) { ball.diff = diff }
        ball.intDiff = record.asymmetric ? Double(intDiffText) : nil
        ball.purchaseDate = hasPurchaseDate ? purchaseDate : nil
        ball.thumbType = thumbType
        ball.thumbSlugBrand = thumbType == .slug && !slugBrand.isEmpty ? slugBrand : nil
        ball.thumbSlugMaterial = thumbType == .slug ? slugMaterial : nil
        ball.thumbSystemBrand = thumbType == .interchangeable ? systemBrand : nil
        ball.thumbHoleSize = thumbType == .interchangeable && !holeSize.isEmpty ? holeSize : nil
        ball.thumbHolePitch = thumbType == .interchangeable && !holePitch.isEmpty ? holePitch : nil
        ball.drillingNotes = notes
        if shellToComplete == nil {
            context.insert(ball)
        }
        onSaved()
    }
}

/// Manual entry fallback (PRD 5.4.2) with "report missing ball" hook.
struct ManualBallForm: View {
    var shellToComplete: Ball?
    var prefillName: String = ""
    let defaultWeight: Int
    var onSaved: () -> Void

    @Environment(\.modelContext) private var context

    @State private var brand = ""
    @State private var model = ""
    @State private var coverstock: CoverstockType = .solid
    @State private var coverstockName = ""
    @State private var coreName = ""
    @State private var asymmetric = false
    @State private var rgText = ""
    @State private var diffText = ""
    @State private var intDiffText = ""
    @State private var weight: Int = 15
    @State private var reportMissing = true

    var body: some View {
        Form {
            Section("Ball") {
                TextField("Brand", text: $brand)
                TextField("Model", text: $model)
                Picker("Coverstock type", selection: $coverstock) {
                    ForEach(CoverstockType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                TextField("Coverstock name (optional)", text: $coverstockName)
                TextField("Core name (optional)", text: $coreName)
                Toggle("Asymmetric", isOn: $asymmetric)
            }
            Section("Specs at your weight (optional)") {
                Picker("Weight", selection: $weight) {
                    ForEach(12...16, id: \.self) { lbs in
                        Text("\(lbs) lb").tag(lbs)
                    }
                }
                TextField("RG (e.g. 2.48)", text: $rgText)
                    .keyboardType(.decimalPad)
                TextField("Differential (e.g. 0.051)", text: $diffText)
                    .keyboardType(.decimalPad)
                if asymmetric {
                    TextField("Intermediate diff (e.g. 0.016)", text: $intDiffText)
                        .keyboardType(.decimalPad)
                }
            }
            Section {
                Toggle("Report this ball as missing from the database", isOn: $reportMissing)
            } footer: {
                Text("Reported balls go to the admin QA queue (PRD 9.3). Your manual entry works immediately either way.")
            }
            Button("Add to Arsenal") {
                save()
            }
            .font(.system(size: 16, weight: .semibold))
            .disabled(model.isEmpty)
        }
        .onAppear {
            model = shellToComplete?.model ?? prefillName
            weight = shellToComplete?.weight ?? defaultWeight
        }
    }

    private func save() {
        let ball = shellToComplete ?? Ball()
        ball.brand = brand
        ball.model = model
        ball.coverstockType = coverstock
        ball.coverstockName = coverstockName.isEmpty ? nil : coverstockName
        ball.coreName = coreName.isEmpty ? nil : coreName
        ball.asymmetric = asymmetric
        ball.rg = Double(rgText)
        ball.diff = Double(diffText)
        ball.intDiff = Double(intDiffText)
        ball.weight = weight
        ball.specWeightUsed = weight
        ball.importedShell = false
        if reportMissing {
            // v1 stub: queued report — the production pipeline ingests these (PRD 9.3).
            UserDefaults.standard.set(
                ((UserDefaults.standard.stringArray(forKey: "pendingBallReports") ?? []) + ["\(brand) \(model)"]),
                forKey: "pendingBallReports"
            )
        }
        if shellToComplete == nil {
            context.insert(ball)
        }
        onSaved()
    }
}
