import SwiftUI
import BrewCore

/// Browse the bundled ingredient database and manage your own custom ingredients.
struct IngredientLibraryView: View {
    enum Kind: String, CaseIterable, Identifiable {
        case fermentables = "Malts", hops = "Hops", yeasts = "Yeast", miscs = "Other"
        var id: Self { self }
    }

    @Environment(RecipeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind = Kind.fermentables
    @State private var query = ""
    @State private var addingCustom = false

    var body: some View {
        List {
            switch kind {
            case .fermentables:
                rows(store.allFermentables, text: { "\($0.name) \($0.origin ?? "")" }) { FermentableInfoRow(fermentable: $0) }
            case .hops:
                rows(store.allHops, text: { "\($0.name) \($0.aroma ?? "")" }) { HopInfoRow(hop: $0) }
            case .yeasts:
                rows(store.allYeasts, text: { $0.displayName }) { YeastInfoRow(yeast: $0) }
            case .miscs:
                rows(store.allMiscs, text: { $0.name }) { MiscInfoRow(misc: $0) }
            }
        }
        .safeAreaInset(edge: .top) {
            Picker("Category", selection: $kind) {
                ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .searchable(text: $query)
        .navigationTitle("Ingredient Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            ToolbarItem(placement: .primaryAction) {
                Button("Add Custom", systemImage: "plus") { addingCustom = true }
            }
        }
        .sheet(isPresented: $addingCustom) {
            NavigationStack {
                switch kind {
                case .fermentables: NewFermentableForm()
                case .hops: NewHopForm()
                case .yeasts: NewYeastForm()
                case .miscs: NewMiscForm()
                }
            }
        }
    }

    @ViewBuilder
    private func rows<Item: Identifiable, Row: View>(_ items: [Item], text: @escaping (Item) -> String,
                                                     @ViewBuilder row: @escaping (Item) -> Row) -> some View
    where Item.ID == String {
        let matching = items.filter { text($0).matchesSearch(query) }
        let custom = matching.filter { store.isCustom(id: $0.id) }
        let bundled = matching.filter { !store.isCustom(id: $0.id) }
        if !custom.isEmpty {
            Section("My Ingredients") {
                ForEach(custom) { row($0) }
                    .onDelete { offsets in
                        offsets.map { custom[$0].id }.forEach(store.deleteCustom(id:))
                    }
            }
        }
        Section("Database (\(bundled.count))") {
            ForEach(bundled) { row($0) }
        }
    }
}
