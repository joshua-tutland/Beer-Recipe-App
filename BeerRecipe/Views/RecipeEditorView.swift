import SwiftUI
import BrewCore

enum EditorSheet: Identifiable, Hashable {
    case style
    case addFermentable, addHop, addYeast, addMisc
    case fermentable(UUID), hop(UUID), yeast(UUID), misc(UUID), mashStep(UUID)
    case scale, brewSession(UUID)

    var id: Self { self }
}

struct RecipeEditorView: View {
    @Binding var recipe: Recipe
    @Environment(RecipeStore.self) private var store
    @Environment(BrewTimers.self) private var timers
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial

    @State private var sheet: EditorSheet?
    @State private var shareItem: ShareItem?
    @State private var exportError: String?
    @State private var showAdvancedEquipment = false
    @State private var notice: String?

    var body: some View {
        let stats = recipe.stats
        Group {
            if horizontalSizeClass == .regular {
                HStack(spacing: 0) {
                    form(stats: stats, showSummary: false)
                    Divider()
                    ScrollView {
                        StatsPanel(recipe: recipe, stats: stats, units: units)
                            .padding()
                    }
                    .frame(width: 360)
                    .background(Color(.systemGroupedBackground))
                }
            } else {
                form(stats: stats, showSummary: true)
            }
        }
        .navigationTitle(recipe.name.isEmpty ? "Untitled" : recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button("Start Brew Day", systemImage: "flame") { startBrewDay() }
                    Button("Scale Recipe…", systemImage: "arrow.up.left.and.arrow.down.right") { sheet = .scale }
                } label: {
                    Label("Brew", systemImage: "mug")
                }
                Menu {
                    Button("PDF Document", systemImage: "doc.richtext") { export(.pdf) }
                    Button("Word Document (.docx)", systemImage: "doc.text") { export(.word) }
                    Button("BeerXML", systemImage: "chevron.left.forwardslash.chevron.right") { export(.beerXML) }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            NavigationStack { sheetContent(sheet) }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(items: [item.url])
        }
        .alert("Recipe Scaled", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(notice ?? "")
        }
        .alert("Export Failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .keyboardDoneButton()
    }

    // MARK: - Form

    private func form(stats: RecipeStats, showSummary: Bool) -> some View {
        Form {
            if showSummary {
                Section {
                    StatsSummaryGrid(stats: stats)
                    NavigationLink {
                        ScrollView {
                            StatsPanel(recipe: recipe, stats: stats, units: units).padding()
                        }
                        .background(Color(.systemGroupedBackground))
                        .navigationTitle("Analysis")
                    } label: {
                        Label("Full Analysis & Brew Day Numbers", systemImage: "chart.bar.doc.horizontal")
                    }
                }
            }

            generalSection
            batchSection
            fermentablesSection(stats: stats)
            hopsSection(stats: stats)
            yeastSection
            miscSection
            if recipe.type != .extract || recipe.fermentables.contains(where: { $0.fermentable.type.isMashed }) {
                mashSection
            }
            fermentationSection
            brewLogSection

            Section("Notes") {
                TextField("Tasting notes, process reminders…", text: $recipe.notes, axis: .vertical)
                    .lineLimit(4...12)
            }
        }
    }

    private var generalSection: some View {
        Section("Recipe") {
            TextField("Name", text: $recipe.name)
                .font(.headline)
            TextField("Brewer", text: $recipe.author)
            Picker("Type", selection: $recipe.type) {
                ForEach(RecipeType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Button {
                sheet = .style
            } label: {
                HStack {
                    Text("Style").foregroundStyle(.primary)
                    Spacer()
                    Text(recipe.style?.displayName ?? "None")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var batchSection: some View {
        Section {
            NumberField(label: "Batch Size",
                        value: $recipe.equipment.batchSizeL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                        unit: units.volumeUnit)
            NumberField(label: "Boil Time", value: $recipe.equipment.boilTimeMinutes, unit: "min", digits: 0)
            if recipe.type != .extract {
                NumberField(label: "Brewhouse Efficiency", value: $recipe.equipment.efficiency, unit: "%", digits: 0)
            }
            Picker("IBU Formula", selection: $recipe.ibuFormula) {
                ForEach(IBUFormula.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            DisclosureGroup("Equipment & Losses", isExpanded: $showAdvancedEquipment) {
                NumberField(label: "Boil-off Rate",
                            value: $recipe.equipment.boilOffLPerHour.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                            unit: "\(units.volumeUnit)/hr")
                NumberField(label: "Kettle Trub Loss",
                            value: $recipe.equipment.trubLossL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                            unit: units.volumeUnit)
                if recipe.type != .extract {
                    NumberField(label: "Mash Tun Deadspace",
                                value: $recipe.equipment.mashTunDeadspaceL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                                unit: units.volumeUnit)
                    NumberField(label: "Mash Thickness",
                                value: $recipe.equipment.mashThicknessLPerKg.converted(
                                    { units == .metric ? $0 : $0 * BrewMath.poundsPerKilogram.reciprocal * 1.056_688 },
                                    { units == .metric ? $0 : $0 / (BrewMath.poundsPerKilogram.reciprocal * 1.056_688) }),
                                unit: units == .metric ? "L/kg" : "qt/lb")
                    NumberField(label: "Grain Absorption",
                                value: $recipe.equipment.grainAbsorptionLPerKg.converted(
                                    { units == .metric ? $0 : $0 * BrewMath.gallonsPerLiter / BrewMath.poundsPerKilogram },
                                    { units == .metric ? $0 : $0 / (BrewMath.gallonsPerLiter / BrewMath.poundsPerKilogram) }),
                                unit: units == .metric ? "L/kg" : "gal/lb", digits: 3)
                    NumberField(label: "Grain Temperature",
                                value: $recipe.equipment.grainTempC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                                unit: units.temperatureUnit, digits: 0)
                }
            }
        } header: {
            Text("Batch")
        }
    }

    private func fermentablesSection(stats: RecipeStats) -> some View {
        let percentById = Dictionary(uniqueKeysWithValues: stats.fermentableShares.map { ($0.id, $0.percent) })
        return Section {
            ForEach(recipe.fermentables) { addition in
                Button { sheet = .fermentable(addition.id) } label: {
                    HStack {
                        BeerSwatch(srm: BrewMath.lovibondToSRM(addition.fermentable.colorLovibond), size: 22)
                        VStack(alignment: .leading) {
                            Text(addition.fermentable.name).foregroundStyle(.primary)
                            Text("\(addition.fermentable.type.displayName) · \(Int(addition.fermentable.colorLovibond.rounded()))°L · \(percentById[addition.id] ?? 0, specifier: "%.1f")%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(units.formatLargeWeight(kg: addition.amountKg))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                }
            }
            .onDelete { recipe.fermentables.remove(atOffsets: $0) }
            .onMove { recipe.fermentables.move(fromOffsets: $0, toOffset: $1) }

            Button("Add Fermentable", systemImage: "plus.circle.fill") { sheet = .addFermentable }
        } header: {
            Text("Fermentables")
        } footer: {
            if !recipe.fermentables.isEmpty {
                Text("Total \(units.formatLargeWeight(kg: stats.totalGrainKg))")
            }
        }
    }

    private func hopsSection(stats: RecipeStats) -> some View {
        let ibuById = Dictionary(uniqueKeysWithValues: stats.hopBitterness.map { ($0.id, $0.ibu) })
        return Section {
            ForEach(recipe.hops) { addition in
                Button { sheet = .hop(addition.id) } label: {
                    HStack {
                        Image(systemName: addition.use == .dryHop ? "leaf" : "flame")
                            .foregroundStyle(.green)
                            .frame(width: 22)
                        VStack(alignment: .leading) {
                            Text(addition.hop.name).foregroundStyle(.primary)
                            Text("\(addition.use.displayName) \(Int(addition.time.rounded())) \(addition.use.timeUnit) · \(addition.alphaAcid, specifier: "%.1f")% AA")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(units.formatSmallWeight(grams: addition.amountGrams))
                                .monospacedDigit()
                                .foregroundStyle(.primary)
                            if let ibu = ibuById[addition.id], ibu > 0 {
                                Text("\(ibu, specifier: "%.1f") IBU")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .onDelete { recipe.hops.remove(atOffsets: $0) }
            .onMove { recipe.hops.move(fromOffsets: $0, toOffset: $1) }

            Button("Add Hop", systemImage: "plus.circle.fill") { sheet = .addHop }
            if recipe.hops.count > 1 {
                Button("Sort by Brew Order", systemImage: "arrow.up.arrow.down") {
                    recipe.hops = recipe.hopsInBrewOrder
                }
            }
        } header: {
            Text("Hops")
        } footer: {
            if !recipe.hops.isEmpty {
                Text("Total \(units.formatSmallWeight(grams: recipe.hops.reduce(0) { $0 + $1.amountGrams })) · \(stats.ibu, specifier: "%.0f") IBU (\(recipe.ibuFormula.displayName))")
            }
        }
    }

    private var yeastSection: some View {
        Section("Yeast") {
            ForEach(recipe.yeasts) { addition in
                Button { sheet = .yeast(addition.id) } label: {
                    HStack {
                        Image(systemName: "allergens")
                            .foregroundStyle(.orange)
                            .frame(width: 22)
                        VStack(alignment: .leading) {
                            Text(addition.yeast.displayName).foregroundStyle(.primary)
                            Text("\(addition.yeast.form.displayName) · \(addition.attenuation, specifier: "%.0f")% attenuation · \(units.formatTemperature(celsius: addition.yeast.tempMinC))–\(units.formatTemperature(celsius: addition.yeast.tempMaxC))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { recipe.yeasts.remove(atOffsets: $0) }

            Button("Add Yeast", systemImage: "plus.circle.fill") { sheet = .addYeast }
        }
    }

    private var miscSection: some View {
        Section("Other Ingredients") {
            ForEach(recipe.miscs) { addition in
                Button { sheet = .misc(addition.id) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(addition.misc.name).foregroundStyle(.primary)
                            Text("\(addition.use.displayName)\(addition.timeMinutes > 0 ? " · \(Int(addition.timeMinutes)) min" : "")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(UnitSystem.number(addition.amount, digits: addition.amount < 10 ? 1 : 0)) \(addition.unit)")
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                }
            }
            .onDelete { recipe.miscs.remove(atOffsets: $0) }

            Button("Add Ingredient", systemImage: "plus.circle.fill") { sheet = .addMisc }
        }
    }

    private var mashSection: some View {
        Section(recipe.type == .extract ? "Steeping" : "Mash Schedule") {
            ForEach(recipe.mashSteps) { step in
                Button { sheet = .mashStep(step.id) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(step.name).foregroundStyle(.primary)
                            Text(step.type.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(units.formatTemperature(celsius: step.tempC)) · \(Int(step.minutes)) min")
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                }
            }
            .onDelete { recipe.mashSteps.remove(atOffsets: $0) }
            .onMove { recipe.mashSteps.move(fromOffsets: $0, toOffset: $1) }

            Button("Add Step", systemImage: "plus.circle.fill") {
                let last = recipe.mashSteps.last
                let step = MashStep(name: last == nil ? "Saccharification" : "Mash Out",
                                    type: last == nil ? .infusion : .temperature,
                                    tempC: last == nil ? 66 : 76,
                                    minutes: last == nil ? 60 : 10)
                recipe.mashSteps.append(step)
                sheet = .mashStep(step.id)
            }
        }
    }

    private var fermentationSection: some View {
        Section("Fermentation & Packaging") {
            NumberField(label: "Primary Temp",
                        value: $recipe.fermentation.primaryTempC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                        unit: units.temperatureUnit, digits: 0)
            NumberField(label: "Primary", value: $recipe.fermentation.primaryDays, unit: "days", digits: 0)
            NumberField(label: "Secondary", value: $recipe.fermentation.secondaryDays, unit: "days", digits: 0)
            NumberField(label: "Carbonation", value: $recipe.fermentation.carbonationVolumes, unit: "vols", digits: 1)
            NumberField(label: "Beer Temp at Bottling",
                        value: $recipe.fermentation.bottlingTempC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                        unit: units.temperatureUnit, digits: 0)
        }
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: EditorSheet) -> some View {
        switch sheet {
        case .style:
            StylePickerView(selection: $recipe.styleId)
        case .addFermentable:
            FermentablePickerView { fermentable in
                let amount = recipe.fermentables.isEmpty ? (recipe.type == .extract ? 3.0 : 4.5) : 0.25
                let addition = FermentableAddition(fermentable: fermentable, amountKg: amount)
                recipe.fermentables.append(addition)
                self.sheet = .fermentable(addition.id)
            }
        case .addHop:
            HopPickerView { hop in
                let addition = HopAddition(hop: hop, amountGrams: 28, use: .boil,
                                           time: recipe.hops.isEmpty ? recipe.equipment.boilTimeMinutes : 10)
                recipe.hops.append(addition)
                self.sheet = .hop(addition.id)
            }
        case .addYeast:
            YeastPickerView { yeast in
                let addition = YeastAddition(yeast: yeast)
                recipe.yeasts.append(addition)
                recipe.fermentation.primaryTempC = (yeast.tempMinC + yeast.tempMaxC) / 2
                self.sheet = nil
            }
        case .addMisc:
            MiscPickerView { misc in
                let addition = MiscAddition(misc: misc, amount: 1)
                recipe.miscs.append(addition)
                self.sheet = .misc(addition.id)
            }
        case .fermentable(let id):
            if let binding = element(\.fermentables, id: id) {
                FermentableAdditionEditor(addition: binding, units: units)
            }
        case .hop(let id):
            if let binding = element(\.hops, id: id) {
                HopAdditionEditor(addition: binding, units: units)
            }
        case .yeast(let id):
            if let binding = element(\.yeasts, id: id) {
                YeastAdditionEditor(addition: binding, units: units)
            }
        case .misc(let id):
            if let binding = element(\.miscs, id: id) {
                MiscAdditionEditor(addition: binding)
            }
        case .mashStep(let id):
            if let binding = element(\.mashSteps, id: id) {
                MashStepEditor(step: binding, units: units)
            }
        case .scale:
            ScaleRecipeView(recipe: recipe, units: units) { scaled, asCopy in
                if asCopy {
                    var copy = scaled
                    copy.id = UUID()
                    copy.sessions = []
                    copy.createdAt = Date()
                    copy.name = RecipeScaler.scaledName(recipe.name, batchSizeL: scaled.equipment.batchSizeL, units: units)
                    store.add(copy)
                    // Wait for the sheet to finish dismissing before showing the alert.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        notice = "Saved \"\(copy.name)\" to your recipe list."
                    }
                } else {
                    recipe = scaled
                }
            }
        case .brewSession(let id):
            if let binding = element(\.sessions, id: id) {
                BrewSessionView(session: binding, recipe: $recipe, units: units)
            }
        }
    }

    // MARK: - Brew log

    private var brewLogSection: some View {
        Section {
            ForEach(recipe.sessions) { session in
                Button { sheet = .brewSession(session.id) } label: {
                    BrewSessionRow(session: session)
                }
            }
            .onDelete { offsets in
                offsets.forEach { timers.resetAll(session: recipe.sessions[$0].id) }
                recipe.sessions.remove(atOffsets: offsets)
            }

            Button("Start Brew Day", systemImage: "flame.fill") { startBrewDay() }
        } header: {
            Text("Brew Log")
        } footer: {
            if recipe.sessions.isEmpty {
                Text("Log each brew's measured gravities and volumes to see your real efficiency and ABV.")
            }
        }
    }

    private func startBrewDay() {
        let session = BrewSession(recipe: recipe)
        recipe.sessions.insert(session, at: 0)
        sheet = .brewSession(session.id)
    }

    /// A binding to one element of one of the recipe's ingredient lists.
    private func element<T: Identifiable>(_ keyPath: WritableKeyPath<Recipe, [T]>, id: UUID) -> Binding<T>? where T.ID == UUID {
        guard let current = recipe[keyPath: keyPath].first(where: { $0.id == id }) else { return nil }
        let recipeBinding = $recipe
        return Binding(
            get: { recipeBinding.wrappedValue[keyPath: keyPath].first { $0.id == id } ?? current },
            set: { newValue in
                if let index = recipeBinding.wrappedValue[keyPath: keyPath].firstIndex(where: { $0.id == id }) {
                    recipeBinding.wrappedValue[keyPath: keyPath][index] = newValue
                }
            }
        )
    }

    // MARK: - Export

    private func export(_ format: RecipeExporter.Format) {
        do {
            shareItem = ShareItem(url: try RecipeExporter.file(for: recipe, format: format, units: units))
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private extension Double {
    var reciprocal: Double { 1 / self }
}
