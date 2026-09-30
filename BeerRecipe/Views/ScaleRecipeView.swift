import SwiftUI
import BrewCore

/// Resize a recipe to a new batch size and/or efficiency, with a before/after preview.
struct ScaleRecipeView: View {
    let recipe: Recipe
    let units: UnitSystem
    /// Called with the scaled recipe and whether to save it as a new recipe.
    let onApply: (Recipe, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var batchSizeL: Double
    @State private var efficiency: Double
    @State private var preserveBitterness = true
    @State private var saveAsCopy = true

    init(recipe: Recipe, units: UnitSystem, onApply: @escaping (Recipe, Bool) -> Void) {
        self.recipe = recipe
        self.units = units
        self.onApply = onApply
        _batchSizeL = State(initialValue: recipe.equipment.batchSizeL)
        _efficiency = State(initialValue: recipe.equipment.efficiency)
    }

    private var scaled: Recipe {
        RecipeScaler.scale(recipe, with: .init(batchSizeL: batchSizeL, efficiency: efficiency,
                                               preserveBitterness: preserveBitterness))
    }

    private var isValid: Bool { batchSizeL > 0 && efficiency > 0 && efficiency <= 100 }

    var body: some View {
        let result = isValid ? scaled : recipe
        let before = recipe.stats
        let after = result.stats

        Form {
            Section {
                NumberField(label: "Batch Size",
                            value: $batchSizeL.converted(units.volume(fromLiters:), units.liters(fromVolume:)),
                            unit: units.volumeUnit)
                HStack {
                    ForEach([0.5, 2, 3], id: \.self) { factor in
                        Button("×\(factor == 0.5 ? "½" : String(Int(factor)))") {
                            batchSizeL = recipe.equipment.batchSizeL * factor
                        }
                        .buttonStyle(.bordered)
                    }
                    Spacer()
                    Button("Reset") {
                        batchSizeL = recipe.equipment.batchSizeL
                        efficiency = recipe.equipment.efficiency
                    }
                    .buttonStyle(.borderless)
                }
                if recipe.type != .extract {
                    NumberField(label: "Brewhouse Efficiency", value: $efficiency, unit: "%", digits: 0)
                }
                Toggle("Keep Bitterness (IBU)", isOn: $preserveBitterness)
            } header: {
                Text("Scale To")
            } footer: {
                Text("Grain is adjusted for the new efficiency so the gravity stays the same. Kettle hops are re-balanced to hit the same IBU; dry hops scale with volume.")
            }

            Section("Before → After") {
                compare("Batch", units.formatVolume(liters: recipe.equipment.batchSizeL),
                        units.formatVolume(liters: result.equipment.batchSizeL))
                compare("OG", UnitSystem.gravity(before.og), UnitSystem.gravity(after.og))
                compare("FG", UnitSystem.gravity(before.fg), UnitSystem.gravity(after.fg))
                compare("ABV", String(format: "%.1f%%", before.abv), String(format: "%.1f%%", after.abv))
                compare("IBU", String(format: "%.0f", before.ibu), String(format: "%.0f", after.ibu))
                compare("SRM", String(format: "%.1f", before.srm), String(format: "%.1f", after.srm))
            }

            if !recipe.fermentables.isEmpty {
                Section("Fermentables") {
                    ForEach(Array(recipe.fermentables.indices), id: \.self) { i in
                        let pair = (recipe.fermentables[i], result.fermentables[i])
                        compare(pair.0.fermentable.name, units.formatLargeWeight(kg: pair.0.amountKg),
                                units.formatLargeWeight(kg: pair.1.amountKg))
                    }
                }
            }
            if !recipe.hops.isEmpty {
                Section("Hops") {
                    ForEach(Array(recipe.hops.indices), id: \.self) { i in
                        let pair = (recipe.hops[i], result.hops[i])
                        compare("\(pair.0.hop.name) · \(pair.0.use.displayName)",
                                units.formatSmallWeight(grams: pair.0.amountGrams),
                                units.formatSmallWeight(grams: pair.1.amountGrams))
                    }
                }
            }
            if !recipe.miscs.isEmpty || !recipe.yeasts.isEmpty {
                Section("Other") {
                    ForEach(Array(recipe.yeasts.indices), id: \.self) { i in
                        let pair = (recipe.yeasts[i], result.yeasts[i])
                        compare(pair.0.yeast.displayName, "\(UnitSystem.number(pair.0.packs, digits: 0)) pk",
                                "\(UnitSystem.number(pair.1.packs, digits: 0)) pk")
                    }
                    ForEach(Array(recipe.miscs.indices), id: \.self) { i in
                        let pair = (recipe.miscs[i], result.miscs[i])
                        compare(pair.0.misc.name, "\(UnitSystem.number(pair.0.amount, digits: 1)) \(pair.0.unit)",
                                "\(UnitSystem.number(pair.1.amount, digits: 1)) \(pair.1.unit)")
                    }
                }
            }

            Section {
                Toggle("Save as a New Recipe", isOn: $saveAsCopy)
            } footer: {
                Text(saveAsCopy ? "The original recipe stays unchanged." : "This recipe will be replaced with the scaled version.")
            }
        }
        .navigationTitle("Scale Recipe")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(saveAsCopy ? "Save" : "Apply") {
                    onApply(scaled, saveAsCopy)
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
    }

    private func compare(_ label: String, _ old: String, _ new: String) -> some View {
        HStack {
            Text(label).lineLimit(1)
            Spacer()
            Text(old).foregroundStyle(.secondary).monospacedDigit()
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
            Text(new).monospacedDigit().fontWeight(old == new ? .regular : .semibold)
        }
        .font(.subheadline)
    }
}
