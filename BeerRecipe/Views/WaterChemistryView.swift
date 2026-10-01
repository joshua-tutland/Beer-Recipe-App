import SwiftUI
import BrewCore

/// Plan a recipe's water: starting water, dilution, salts and mash acid, with the resulting
/// ion profile, sulfate:chloride balance and estimated mash pH.
struct WaterChemistryView: View {
    @Binding var recipe: Recipe
    let units: UnitSystem

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var savedMyWater = false

    private var treatment: Binding<WaterTreatment> {
        Binding(get: { recipe.water ?? WaterTreatment() }, set: { recipe.water = $0 })
    }

    var body: some View {
        let water = recipe.water ?? WaterTreatment()
        let report = recipe.waterReport

        Form {
            if let report { resultsSection(water, report) }
            sourceSection(water)
            targetSection(water)
            saltsSection(water, report)
            acidSection(water, report)
            Section {
                Button("Remove Water Plan", role: .destructive) {
                    recipe.water = nil
                    dismiss()
                }
            } footer: {
                Text("Mash pH is estimated from each malt's typical acidity and the water's residual alkalinity; expect ±0.1–0.2. Check with a calibrated pH meter about 15 minutes into the mash, cooled to room temperature.")
            }
        }
        .navigationTitle("Water Chemistry")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
    }

    // MARK: - Results

    private func resultsSection(_ water: WaterTreatment, _ report: WaterReport) -> some View {
        Section {
            if let ph = report.mashPH {
                MashPHGauge(pH: ph.pH)
            } else {
                Text("Add mashed grain to estimate mash pH.").foregroundStyle(.secondary)
            }

            Grid(alignment: .trailing, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("ppm").gridColumnAlignment(.leading)
                    ForEach(Ion.allCases) { Text($0.symbol).fontWeight(.semibold) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Divider()
                GridRow {
                    Text("Water").gridColumnAlignment(.leading)
                    ForEach(Ion.allCases) { ion in
                        Text(UnitSystem.number(report.profile[ion], digits: 0))
                            .foregroundStyle(color(for: ion, value: report.profile[ion], target: water.target))
                    }
                }
                if let target = water.target {
                    GridRow {
                        Text("Target").gridColumnAlignment(.leading).foregroundStyle(.secondary)
                        ForEach(Ion.allCases) { ion in
                            Text(UnitSystem.number(target[ion], digits: 0)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .font(.subheadline.monospacedDigit())

            if let ratio = report.profile.sulfateToChloride, let balance = report.balance {
                LabeledContent("Sulfate : Chloride", value: "\(UnitSystem.number(ratio, digits: 2)) · \(balance.displayName)")
            }
            LabeledContent("Residual Alkalinity",
                           value: "\(UnitSystem.number(report.profile.residualAlkalinityAsCaCO3, digits: 0)) ppm as CaCO₃")
            if report.profile.calcium < 40 {
                Label("Calcium under ~40 ppm can hurt yeast health and clarity; consider gypsum or calcium chloride.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if report.profile.sodium > 150 {
                Label("Sodium above 150 ppm can taste salty or harsh.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Result")
        }
    }

    /// Green when within ~15% (or 10 ppm) of target; orange otherwise.
    private func color(for ion: Ion, value: Double, target: WaterProfile?) -> Color {
        guard let target else { return .primary }
        let goal = target[ion]
        return abs(value - goal) <= max(10, goal * 0.15) ? .green : .orange
    }

    // MARK: - Source

    private func sourceSection(_ water: WaterTreatment) -> some View {
        Section {
            Menu {
                ForEach(store.sourceWaterProfiles) { profile in
                    Button(profile.name) { treatment.wrappedValue.source = profile }
                }
            } label: {
                HStack {
                    Text("Starting Water").foregroundStyle(.primary)
                    Spacer()
                    Text(water.source.name).foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.tertiary)
                }
            }
            ForEach(Ion.allCases) { ion in
                NumberField(label: "\(ion.displayName) (\(ion.symbol))",
                            value: Binding(get: { water.source[ion] },
                                           set: { newValue in
                                               var source = treatment.wrappedValue.source
                                               source[ion] = max(0, newValue)
                                               if source.id != "my-water" {
                                                   source.id = "custom"
                                                   source.name = "Custom"
                                               }
                                               treatment.wrappedValue.source = source
                                           }),
                            unit: "ppm", digits: 0)
            }
            NumberField(label: "Dilute with Distilled/RO", value: treatment.dilutionPercent, unit: "%", digits: 0)
            if water.source.ionBalanceError > 10 {
                Label("These numbers don't balance (\(Int(water.source.ionBalanceError))% error). Double-check your water report.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button(savedMyWater ? "Saved as My Water" : "Save as My Water") {
                store.saveMyWater(water.source)
                savedMyWater = true
            }
            .disabled(savedMyWater)
        } header: {
            Text("Starting Water")
        } footer: {
            Text("Enter your water report (local utility or a lab test such as Ward Labs), or start from distilled/RO water. \"My Water\" becomes the default for new water plans.")
        }
    }

    // MARK: - Target

    private func targetSection(_ water: WaterTreatment) -> some View {
        Section {
            Picker("Target Profile", selection: treatment.targetId) {
                Text("None").tag(String?.none)
                ForEach(WaterProfiles.targets) { Text($0.name).tag(Optional($0.id)) }
            }
            if let target = water.target, let notes = target.notes {
                Text(notes).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Target")
        }
    }

    // MARK: - Salts

    private func saltsSection(_ water: WaterTreatment, _ report: WaterReport?) -> some View {
        let volume = report?.totalWaterL ?? recipe.waterVolumes.total
        return Section {
            if let target = water.target {
                Button("Match Target Automatically", systemImage: "wand.and.stars") {
                    let start = water.source.diluted(by: water.dilutionPercent / 100)
                    treatment.wrappedValue.salts = WaterSolver.salts(from: start, to: target, totalWaterL: volume)
                }
            }
            ForEach(BrewingSalt.allCases) { salt in
                NumberField(label: salt.shortName,
                            value: Binding(get: { water.grams(of: salt) },
                                           set: { treatment.wrappedValue.setGrams(max(0, $0), of: salt) }),
                            unit: "g", digits: 1)
            }
        } header: {
            Text("Salts")
        } footer: {
            Text("Amounts are for all \(units.formatVolume(liters: volume)) of brewing water. Add them in proportion to your mash and sparge water.")
        }
    }

    // MARK: - Acid

    private func acidSection(_ water: WaterTreatment, _ report: WaterReport?) -> some View {
        Section {
            Picker("Acid", selection: treatment.acid) {
                ForEach(MashAcid.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            NumberField(label: "Amount in Mash", value: treatment.acidML, unit: "mL", digits: 1)

            if let report {
                switch water.suggestedPHAdjustment(for: report) {
                case .none:
                    if report.mashPH != nil {
                        Label("Mash pH is on target.", systemImage: "checkmark.circle").foregroundStyle(.green)
                    }
                case .acid(let ml):
                    Button("Set \(water.acid.displayName) to \(UnitSystem.number(ml, digits: 1)) mL for pH 5.4",
                           systemImage: "drop.fill") {
                        treatment.wrappedValue.acidML = ml
                    }
                case .bakingSoda(let grams):
                    Button("Add \(UnitSystem.number(grams, digits: 1)) g Baking Soda for pH 5.4",
                           systemImage: "plus.circle") {
                        var t = treatment.wrappedValue
                        t.acidML = 0
                        t.setGrams(t.grams(of: .bakingSoda) + grams, of: .bakingSoda)
                        treatment.wrappedValue = t
                    }
                }
            }
        } header: {
            Text("Mash pH Adjustment")
        } footer: {
            Text("Most beers mash best around pH 5.2–5.6 (5.4 is a good target). Acidulated malt in the grist is counted automatically.")
        }
    }
}

/// A horizontal pH scale, highlighting the 5.2–5.6 sweet spot.
struct MashPHGauge: View {
    let pH: Double

    private let low = 4.9
    private let high = 6.0

    private var status: (String, Color) {
        switch pH {
        case ..<5.2: return ("Too low", .orange)
        case ..<5.6: return ("In range", .green)
        default: return ("Too high", .orange)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Estimated Mash pH")
                Spacer()
                Text(UnitSystem.number(pH, digits: 2))
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(status.1)
                Text(status.0).font(.caption).foregroundStyle(status.1)
            }
            GeometryReader { geo in
                let x = { (v: Double) -> CGFloat in
                    CGFloat((min(max(v, low), high) - low) / (high - low)) * geo.size.width
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.systemFill))
                    Capsule()
                        .fill(Color.green.opacity(0.35))
                        .frame(width: x(5.6) - x(5.2))
                        .offset(x: x(5.2))
                    Circle()
                        .fill(status.1)
                        .overlay(Circle().strokeBorder(.background, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .offset(x: x(pH) - 8)
                }
            }
            .frame(height: 16)
            HStack {
                Text(UnitSystem.number(low, digits: 1))
                Spacer()
                Text("5.2 – 5.6")
                Spacer()
                Text(UnitSystem.number(high, digits: 1))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Estimated mash pH \(UnitSystem.number(pH, digits: 2)), \(status.0)")
    }
}
