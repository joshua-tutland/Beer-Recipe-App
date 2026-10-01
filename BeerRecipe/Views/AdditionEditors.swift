import SwiftUI
import BrewCore

/// Shared chrome for the ingredient editing sheets.
private struct EditorChrome: ViewModifier {
    let title: String
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
    }
}

private extension View {
    func editorChrome(_ title: String) -> some View { modifier(EditorChrome(title: title)) }
}

struct FermentableAdditionEditor: View {
    @Binding var addition: FermentableAddition
    let units: UnitSystem

    var body: some View {
        Form {
            Section {
                NumberField(label: "Amount",
                            value: $addition.amountKg.converted(units.largeWeight(fromKg:), units.kg(fromLargeWeight:)),
                            unit: units.largeWeightUnit, digits: 3)
            }
            Section {
                Picker("Type", selection: $addition.fermentable.type) {
                    ForEach(FermentableType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                NumberField(label: "Color", value: $addition.fermentable.colorLovibond, unit: "°L", digits: 1)
                NumberField(label: "Potential", value: $addition.fermentable.potentialPPG, unit: "PPG", digits: 1)
                LabeledContent("Potential SG", value: UnitSystem.gravity(addition.fermentable.potentialSG))
                LabeledContent("Color (EBC)", value: UnitSystem.number(addition.fermentable.colorEBC, digits: 0))
            } header: {
                Text("Properties")
            } footer: {
                Text("Adjust to match your maltster's spec sheet. Changes apply to this recipe only.")
            }
            if addition.fermentable.maxPercent != nil || addition.fermentable.notes != nil {
                Section("About") {
                    if let max = addition.fermentable.maxPercent {
                        LabeledContent("Recommended Max", value: "\(Int(max))% of grist")
                    }
                    if let notes = addition.fermentable.notes { Text(notes).foregroundStyle(.secondary) }
                }
            }
        }
        .editorChrome(addition.fermentable.name)
    }
}

struct HopAdditionEditor: View {
    @Binding var addition: HopAddition
    let units: UnitSystem

    @Environment(RecipeStore.self) private var store
    @State private var pickingOther = false

    var body: some View {
        Form {
            Section {
                NumberField(label: "Amount",
                            value: $addition.amountGrams.converted(units.smallWeight(fromGrams:), units.grams(fromSmallWeight:)),
                            unit: units.smallWeightUnit, digits: units == .metric ? 1 : 2)
                NumberField(label: "Alpha Acid", value: $addition.alphaAcid, unit: "%", digits: 1)
            }
            Section("Addition") {
                Picker("Use", selection: $addition.use) {
                    ForEach(HopUse.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                if addition.use != .firstWort {
                    NumberField(label: addition.use == .whirlpool ? "Steep Time" : "Time",
                                value: $addition.time, unit: addition.use.timeUnit, digits: 0)
                }
                if addition.use == .whirlpool {
                    NumberField(label: "Whirlpool Temp",
                                value: $addition.whirlpoolTempC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                                unit: units.temperatureUnit, digits: 0)
                }
                Picker("Form", selection: $addition.form) {
                    ForEach(HopForm.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section {
                let suggestions = HopSubstitution.suggestions(for: addition.hop, in: store.allHops)
                ForEach(suggestions) { hop in
                    Button { swap(to: hop) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hop.name).foregroundStyle(.primary)
                                if let aroma = hop.aroma {
                                    Text(aroma).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Text(units.formatSmallWeight(grams: HopSubstitution.substitute(addition, with: hop).amountGrams))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button("Choose Another Hop…", systemImage: "arrow.triangle.swap") { pickingOther = true }
            } header: {
                Text("Substitute")
            } footer: {
                Text(addition.use == .dryHop
                     ? "Dry hops keep the same weight when swapped."
                     : "The amount is adjusted for the new hop's alpha acid so bitterness stays the same.")
            }
            Section("About \(addition.hop.name)") {
                LabeledContent("Typical Alpha", value: "\(UnitSystem.number(addition.hop.alphaAcid, digits: 1))%")
                LabeledContent("Purpose", value: addition.hop.purpose.displayName)
                if let origin = addition.hop.origin { LabeledContent("Origin", value: origin) }
                if let aroma = addition.hop.aroma { LabeledContent("Aroma", value: aroma) }
                if let subs = addition.hop.substitutes { LabeledContent("Substitutes", value: subs) }
            }
        }
        .sheet(isPresented: $pickingOther) {
            NavigationStack {
                HopPickerView { hop in
                    swap(to: hop)
                    pickingOther = false
                }
            }
        }
        .onChange(of: addition.use) { _, use in
            switch use {
            case .dryHop: if addition.time > 14 { addition.time = 4 }
            case .whirlpool: if addition.time > 60 { addition.time = 20 }
            default: break
            }
        }
        .editorChrome(addition.hop.name)
    }

    private func swap(to hop: Hop) {
        addition = HopSubstitution.substitute(addition, with: hop)
    }
}

struct YeastAdditionEditor: View {
    @Binding var addition: YeastAddition
    let units: UnitSystem

    var body: some View {
        Form {
            Section {
                NumberField(label: "Expected Attenuation", value: $addition.attenuation, unit: "%", digits: 0)
                NumberField(label: addition.yeast.form == .dry ? "Packets" : "Packs / Vials", value: $addition.packs, digits: 1)
            } footer: {
                Text("Attenuation drives the final gravity estimate. Mash hotter or use a less attenuative strain for more body.")
            }
            Section("About") {
                if let lab = addition.yeast.laboratory { LabeledContent("Laboratory", value: lab) }
                if let product = addition.yeast.productId { LabeledContent("Product", value: product) }
                LabeledContent("Type", value: addition.yeast.type.displayName)
                LabeledContent("Attenuation Range",
                               value: "\(Int(addition.yeast.attenuationMin))–\(Int(addition.yeast.attenuationMax))%")
                LabeledContent("Temperature",
                               value: "\(units.formatTemperature(celsius: addition.yeast.tempMinC))–\(units.formatTemperature(celsius: addition.yeast.tempMaxC))")
                if let floc = addition.yeast.flocculation { LabeledContent("Flocculation", value: floc) }
                if let tol = addition.yeast.alcoholTolerance { LabeledContent("Alcohol Tolerance", value: "\(Int(tol))%") }
                if let notes = addition.yeast.notes { Text(notes).foregroundStyle(.secondary) }
            }
        }
        .editorChrome(addition.yeast.name)
    }
}

struct MiscAdditionEditor: View {
    @Binding var addition: MiscAddition

    var body: some View {
        Form {
            Section {
                NumberField(label: "Amount", value: $addition.amount, unit: addition.unit, digits: 2)
                TextField("Unit", text: $addition.unit)
                Picker("Use", selection: $addition.use) {
                    ForEach(MiscUse.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                NumberField(label: "Time", value: $addition.timeMinutes, unit: "min", digits: 0)
            }
            if let notes = addition.misc.notes {
                Section("About") { Text(notes).foregroundStyle(.secondary) }
            }
        }
        .editorChrome(addition.misc.name)
    }
}

struct MashStepEditor: View {
    @Binding var step: MashStep
    let units: UnitSystem

    var body: some View {
        Form {
            TextField("Name", text: $step.name)
            Picker("Type", selection: $step.type) {
                ForEach(MashStepType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            NumberField(label: "Temperature",
                        value: $step.tempC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                        unit: units.temperatureUnit, digits: 0)
            NumberField(label: "Time", value: $step.minutes, unit: "min", digits: 0)
            Section {
                EmptyView()
            } footer: {
                Text("Lower mash temperatures (63–65°C / 145–149°F) make a drier, more fermentable wort; higher (68–70°C / 154–158°F) gives more body.")
            }
        }
        .editorChrome("Mash Step")
    }
}

struct StylePickerView: View {
    @Binding var selection: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [BeerStyle] {
        StyleCatalog.all.filter { "\($0.id) \($0.name) \($0.category)".matchesSearch(query) }
    }

    var body: some View {
        List {
            Button("No Style") {
                selection = nil
                dismiss()
            }
            ForEach(StyleCatalog.categories, id: \.self) { category in
                let styles = filtered.filter { $0.category == category }
                if !styles.isEmpty {
                    Section(category) {
                        ForEach(styles) { style in
                            Button {
                                selection = style.id
                                dismiss()
                            } label: {
                                HStack {
                                    BeerSwatch(srm: (style.srmMin + style.srmMax) / 2, size: 24)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(style.displayName).foregroundStyle(.primary)
                                        Text("OG \(UnitSystem.gravity(style.ogMin))–\(UnitSystem.gravity(style.ogMax)) · \(Int(style.ibuMin))–\(Int(style.ibuMax)) IBU · \(style.abvMin, specifier: "%.1f")–\(style.abvMax, specifier: "%.1f")%")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selection == style.id {
                                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Beer Style")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        }
    }
}
