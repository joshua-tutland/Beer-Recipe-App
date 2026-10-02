import SwiftUI
import BrewCore

/// The brewer's stock of ingredients.
struct InventoryView: View {
    enum Sheet: Identifiable {
        case pick(InventoryKind)
        case edit(InventoryItem, isNew: Bool)

        var id: String {
            switch self {
            case .pick(let kind): return "pick-\(kind.rawValue)"
            case .edit(let item, _): return "edit-\(item.id)"
            }
        }
    }

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("unitSystem") private var units: UnitSystem = .imperial
    @State private var kind = InventoryKind.fermentable
    @State private var query = ""
    @State private var sheet: Sheet?

    private var items: [InventoryItem] {
        store.inventory
            .filter { $0.kind == kind && $0.name.matchesSearch(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        List {
            ForEach(items) { item in
                Button { sheet = .edit(item, isNew: false) } label: {
                    InventoryRow(item: item, units: units)
                }
            }
            .onDelete { offsets in
                let current = items
                store.deleteInventory(ids: offsets.map { current[$0].id })
            }
        }
        .overlay {
            if items.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView {
                        Label("No \(kind.displayName)", systemImage: "shippingbox")
                    } description: {
                        Text("Add what you have on hand to see what each recipe is missing.")
                    } actions: {
                        Button("Add \(kind.displayName)") { sheet = .pick(kind) }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("Kind", selection: $kind) {
                ForEach(InventoryKind.allCases) { Text($0 == .fermentable ? "Malts" : $0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .searchable(text: $query)
        .navigationTitle("Inventory")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Button("Add", systemImage: "plus") { sheet = .pick(kind) }
            }
        }
        .sheet(item: $sheet) { sheet in
            NavigationStack {
                switch sheet {
                case .pick(.fermentable):
                    FermentablePickerView { self.sheet = .edit(InventoryItem(fermentable: $0, kg: 0), isNew: true) }
                case .pick(.hop):
                    HopPickerView { self.sheet = .edit(InventoryItem(hop: $0, grams: 0), isNew: true) }
                case .pick(.yeast):
                    YeastPickerView { self.sheet = .edit(InventoryItem(yeast: $0, packs: 1), isNew: true) }
                case .pick(.misc):
                    MiscPickerView { self.sheet = .edit(InventoryItem(misc: $0, amount: 0), isNew: true) }
                case .edit(let item, let isNew):
                    InventoryItemEditor(item: item, isNew: isNew, units: units)
                }
            }
        }
    }
}

struct InventoryRow: View {
    let item: InventoryItem
    let units: UnitSystem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).foregroundStyle(.primary)
                HStack(spacing: 6) {
                    if let alpha = item.alphaAcid, item.kind == .hop {
                        Text("\(UnitSystem.number(alpha, digits: 1))% AA")
                    }
                    if let date = item.bestBefore {
                        Text(item.isExpired() ? "Expired" : "Best before \(date.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(item.isExpired() ? Color.red : Color.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Text(Inventory.format(item.amount, kind: item.kind, unit: item.unit, units: units))
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
    }
}

/// Add or edit one stock item.
struct InventoryItemEditor: View {
    @State var item: InventoryItem
    let isNew: Bool
    let units: UnitSystem

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                switch item.kind {
                case .fermentable:
                    NumberField(label: "Amount",
                                value: $item.amount.converted(units.largeWeight(fromKg:), units.kg(fromLargeWeight:)),
                                unit: units.largeWeightUnit, digits: 3)
                case .hop:
                    NumberField(label: "Amount",
                                value: $item.amount.converted(units.smallWeight(fromGrams:), units.grams(fromSmallWeight:)),
                                unit: units.smallWeightUnit, digits: units == .metric ? 0 : 2)
                    NumberField(label: "Alpha Acid",
                                value: Binding(get: { item.alphaAcid ?? 0 }, set: { item.alphaAcid = $0 > 0 ? $0 : nil }),
                                unit: "%", digits: 1)
                case .yeast:
                    NumberField(label: "Packs", value: $item.amount, digits: 1)
                case .misc:
                    NumberField(label: "Amount", value: $item.amount, unit: item.unit, digits: 2)
                    TextField("Unit", text: $item.unit)
                }
            } header: {
                Text(item.name)
            }
            Section {
                Toggle("Best Before Date", isOn: Binding(
                    get: { item.bestBefore != nil },
                    set: { item.bestBefore = $0 ? Calendar.current.date(byAdding: .month, value: 6, to: Date()) : nil }))
                if item.bestBefore != nil {
                    DatePicker("Best Before", selection: Binding(
                        get: { item.bestBefore ?? Date() },
                        set: { item.bestBefore = $0 }), displayedComponents: .date)
                }
                TextField("Notes (supplier, lot, storage…)", text: $item.notes, axis: .vertical)
            } footer: {
                Text("When you brew, the oldest stock (soonest best-before date) is used first.")
            }
            if !isNew {
                Section {
                    Button("Remove from Inventory", role: .destructive) {
                        store.deleteInventory(ids: [item.id])
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Add to Inventory" : "Edit Stock")
        .navigationBarTitleDisplayMode(.inline)
        .keyboardDoneButton()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save") {
                    if isNew { store.addInventory(item) } else { store.updateInventory(item) }
                    dismiss()
                }
                .disabled(item.amount <= 0)
            }
        }
    }
}

/// What a recipe needs versus what's in stock, with a shareable shopping list.
struct RecipeInventoryView: View {
    let recipe: Recipe
    let units: UnitSystem

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    @State private var confirmRestock = false

    var body: some View {
        let needs = Inventory.needs(for: recipe, stock: store.inventory)
        let missing = needs.filter { !$0.isCovered }

        List {
            Section {
                if missing.isEmpty {
                    Label("Everything is in stock", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else {
                    Label("\(missing.count) of \(needs.count) ingredients short", systemImage: "cart")
                        .foregroundStyle(.orange)
                }
            }
            ForEach(InventoryKind.allCases) { kind in
                let rows = needs.filter { $0.kind == kind }
                if !rows.isEmpty {
                    Section(kind.displayName) {
                        ForEach(rows) { need in
                            NeedRow(need: need, units: units)
                        }
                    }
                }
            }
            if !missing.isEmpty {
                Section {
                    Button("Share Shopping List", systemImage: "square.and.arrow.up") { showShare = true }
                    Button("Mark Missing Items as Bought", systemImage: "cart.badge.plus") { confirmRestock = true }
                } footer: {
                    Text("Marking items as bought adds the missing amounts to your inventory.")
                }
            }
        }
        .navigationTitle("Ingredients for \(recipe.name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: [Inventory.shoppingList(for: recipe, needs: needs, units: units)])
        }
        .confirmationDialog("Add the missing amounts to your inventory?", isPresented: $confirmRestock,
                            titleVisibility: .visible) {
            Button("Add to Inventory") {
                store.setInventory(Inventory.restocking(needs, into: store.inventory))
            }
        }
    }
}

private struct NeedRow: View {
    let need: IngredientNeed
    let units: UnitSystem

    var body: some View {
        HStack {
            Image(systemName: need.isCovered ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(need.isCovered ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(need.name)
                Text("Need \(Inventory.format(need.required, kind: need.kind, unit: need.unit, units: units)) · have \(Inventory.format(need.onHand, kind: need.kind, unit: need.unit, units: units))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !need.isCovered {
                Text("−\(Inventory.format(need.shortfall, kind: need.kind, unit: need.unit, units: units))")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }
}
