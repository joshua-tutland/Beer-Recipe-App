import SwiftUI
import BrewCore

/// Searchable, sectioned list of ingredients with a "Custom" button for adding your own.
struct CatalogPickerView<Item: Identifiable, Row: View, CustomForm: View>: View where Item.ID == String {
    let title: String
    let items: [Item]
    let section: (Item) -> String
    let searchText: (Item) -> String
    @ViewBuilder let row: (Item) -> Row
    @ViewBuilder let customForm: (@escaping (Item) -> Void) -> CustomForm
    let onPick: (Item) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var showCustom = false

    private var filtered: [Item] { items.filter { searchText($0).matchesSearch(query) } }

    private var sections: [String] {
        var seen = Set<String>()
        return filtered.map(section).filter { seen.insert($0).inserted }
    }

    var body: some View {
        List {
            ForEach(sections, id: \.self) { name in
                Section(name) {
                    ForEach(filtered.filter { section($0) == name }) { item in
                        Button { onPick(item) } label: {
                            row(item).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .overlay {
            if filtered.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Custom", systemImage: "plus") { showCustom = true }
            }
        }
        .sheet(isPresented: $showCustom) {
            NavigationStack {
                customForm { item in
                    showCustom = false
                    onPick(item)
                }
            }
        }
    }
}

struct FermentablePickerView: View {
    @Environment(RecipeStore.self) private var store
    let onPick: (Fermentable) -> Void

    var body: some View {
        CatalogPickerView(
            title: "Add Fermentable",
            items: store.allFermentables,
            section: { store.isCustom(id: $0.id) ? "My Ingredients" : $0.type.displayName },
            searchText: { "\($0.name) \($0.origin ?? "") \($0.notes ?? "")" },
            row: { FermentableInfoRow(fermentable: $0) },
            customForm: { done in NewFermentableForm(onSave: done) },
            onPick: onPick
        )
    }
}

struct HopPickerView: View {
    @Environment(RecipeStore.self) private var store
    let onPick: (Hop) -> Void

    var body: some View {
        CatalogPickerView(
            title: "Add Hop",
            items: store.allHops,
            section: { store.isCustom(id: $0.id) ? "My Hops" : String($0.name.prefix(1)).uppercased() },
            searchText: { "\($0.name) \($0.origin ?? "") \($0.aroma ?? "") \($0.purpose.displayName)" },
            row: { HopInfoRow(hop: $0) },
            customForm: { done in NewHopForm(onSave: done) },
            onPick: onPick
        )
    }
}

struct YeastPickerView: View {
    @Environment(RecipeStore.self) private var store
    let onPick: (Yeast) -> Void

    var body: some View {
        CatalogPickerView(
            title: "Add Yeast",
            items: store.allYeasts,
            section: { store.isCustom(id: $0.id) ? "My Yeasts" : $0.type.displayName },
            searchText: { "\($0.displayName) \($0.notes ?? "")" },
            row: { YeastInfoRow(yeast: $0) },
            customForm: { done in NewYeastForm(onSave: done) },
            onPick: onPick
        )
    }
}

struct MiscPickerView: View {
    @Environment(RecipeStore.self) private var store
    let onPick: (Misc) -> Void

    var body: some View {
        CatalogPickerView(
            title: "Add Ingredient",
            items: store.allMiscs,
            section: { store.isCustom(id: $0.id) ? "My Ingredients" : $0.type.displayName },
            searchText: { "\($0.name) \($0.notes ?? "")" },
            row: { MiscInfoRow(misc: $0) },
            customForm: { done in NewMiscForm(onSave: done) },
            onPick: onPick
        )
    }
}

// MARK: - Rows

struct FermentableInfoRow: View {
    let fermentable: Fermentable

    var body: some View {
        HStack {
            BeerSwatch(srm: BrewMath.lovibondToSRM(fermentable.colorLovibond), size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(fermentable.name)
                Text("\(fermentable.colorLovibond, specifier: "%.0f")°L · \(fermentable.potentialPPG, specifier: "%.0f") PPG\(fermentable.origin.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = fermentable.notes {
                    Text(notes).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
        }
    }
}

struct HopInfoRow: View {
    let hop: Hop

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(hop.name)
                Text("\(hop.alphaAcid, specifier: "%.1f")% AA · \(hop.purpose.displayName)\(hop.origin.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let aroma = hop.aroma {
                    Text(aroma).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
        }
    }
}

struct YeastInfoRow: View {
    let yeast: Yeast
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(yeast.displayName)
                Text("\(yeast.form.displayName) · \(yeast.attenuationMin, specifier: "%.0f")–\(yeast.attenuationMax, specifier: "%.0f")% · \(units.formatTemperature(celsius: yeast.tempMinC))–\(units.formatTemperature(celsius: yeast.tempMaxC))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = yeast.notes {
                    Text(notes).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
        }
    }
}

struct MiscInfoRow: View {
    let misc: Misc

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(misc.name)
                Text("\(misc.type.displayName) · \(misc.defaultUse.displayName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let notes = misc.notes {
                    Text(notes).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
        }
    }
}

// MARK: - Custom ingredient forms

struct NewFermentableForm: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onSave: ((Fermentable) -> Void)?

    @State private var item = Fermentable(name: "", type: .grain, colorLovibond: 2, potentialPPG: 37)

    var body: some View {
        Form {
            TextField("Name", text: $item.name)
            Picker("Type", selection: $item.type) {
                ForEach(FermentableType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            NumberField(label: "Color", value: $item.colorLovibond, unit: "°L", digits: 1)
            NumberField(label: "Potential", value: $item.potentialPPG, unit: "PPG", digits: 1)
            Toggle("Unfermentable (e.g. lactose)", isOn: Binding(
                get: { item.fermentability == 0 },
                set: { item.fermentability = $0 ? 0 : (item.type == .sugar ? 100 : nil) }))
            TextField("Origin", text: Binding(get: { item.origin ?? "" }, set: { item.origin = $0.isEmpty ? nil : $0 }))
            TextField("Notes", text: Binding(get: { item.notes ?? "" }, set: { item.notes = $0.isEmpty ? nil : $0 }), axis: .vertical)
        }
        .onChange(of: item.type) { _, type in
            if type == .sugar && item.fermentability == nil { item.fermentability = 100 }
            if type != .sugar && item.fermentability == 100 { item.fermentability = nil }
        }
        .navigationTitle("New Fermentable")
        .customFormToolbar(canSave: !item.name.isEmpty) {
            store.addCustom(item)
            if let onSave { onSave(item) } else { dismiss() }
        }
    }
}

struct NewHopForm: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onSave: ((Hop) -> Void)?

    @State private var item = Hop(name: "", alphaAcid: 8)

    var body: some View {
        Form {
            TextField("Name", text: $item.name)
            NumberField(label: "Alpha Acid", value: $item.alphaAcid, unit: "%", digits: 1)
            Picker("Purpose", selection: $item.purpose) {
                ForEach(HopPurpose.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            TextField("Origin", text: Binding(get: { item.origin ?? "" }, set: { item.origin = $0.isEmpty ? nil : $0 }))
            TextField("Aroma", text: Binding(get: { item.aroma ?? "" }, set: { item.aroma = $0.isEmpty ? nil : $0 }), axis: .vertical)
        }
        .navigationTitle("New Hop")
        .customFormToolbar(canSave: !item.name.isEmpty) {
            store.addCustom(item)
            if let onSave { onSave(item) } else { dismiss() }
        }
    }
}

struct NewYeastForm: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    var onSave: ((Yeast) -> Void)?

    @State private var item = Yeast(name: "", attenuationMin: 73, attenuationMax: 77, tempMinC: 18, tempMaxC: 22)

    var body: some View {
        Form {
            TextField("Name", text: $item.name)
            TextField("Laboratory", text: Binding(get: { item.laboratory ?? "" }, set: { item.laboratory = $0.isEmpty ? nil : $0 }))
            TextField("Product ID", text: Binding(get: { item.productId ?? "" }, set: { item.productId = $0.isEmpty ? nil : $0 }))
            Picker("Type", selection: $item.type) {
                ForEach(YeastType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Form", selection: $item.form) {
                ForEach(YeastForm.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            NumberField(label: "Attenuation Min", value: $item.attenuationMin, unit: "%", digits: 0)
            NumberField(label: "Attenuation Max", value: $item.attenuationMax, unit: "%", digits: 0)
            NumberField(label: "Temp Min",
                        value: $item.tempMinC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                        unit: units.temperatureUnit, digits: 0)
            NumberField(label: "Temp Max",
                        value: $item.tempMaxC.converted(units.temperature(fromC:), units.celsius(fromTemperature:)),
                        unit: units.temperatureUnit, digits: 0)
        }
        .navigationTitle("New Yeast")
        .customFormToolbar(canSave: !item.name.isEmpty) {
            store.addCustom(item)
            if let onSave { onSave(item) } else { dismiss() }
        }
    }
}

struct NewMiscForm: View {
    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var onSave: ((Misc) -> Void)?

    @State private var item = Misc(name: "", type: .spice, defaultUse: .boil)

    var body: some View {
        Form {
            TextField("Name", text: $item.name)
            Picker("Type", selection: $item.type) {
                ForEach(MiscType.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Picker("Use", selection: $item.defaultUse) {
                ForEach(MiscUse.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            TextField("Unit (g, ml, tsp, each…)", text: $item.defaultUnit)
        }
        .navigationTitle("New Ingredient")
        .customFormToolbar(canSave: !item.name.isEmpty) {
            store.addCustom(item)
            if let onSave { onSave(item) } else { dismiss() }
        }
    }
}

private extension View {
    func customFormToolbar(canSave: Bool, save: @escaping () -> Void) -> some View {
        modifier(CustomFormToolbar(canSave: canSave, save: save))
    }
}

private struct CustomFormToolbar: ViewModifier {
    let canSave: Bool
    let save: () -> Void
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDoneButton()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!canSave)
                }
            }
    }
}
