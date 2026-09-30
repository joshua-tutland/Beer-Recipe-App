import SwiftUI
import UniformTypeIdentifiers
import BrewCore

struct RecipeListView: View {
    @Environment(RecipeStore.self) private var store
    @Binding var selection: UUID?

    @State private var searchText = ""
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var showLibrary = false
    @State private var showTools = false
    @State private var shareItem: ShareItem?
    @State private var alertMessage: String?

    private var filtered: [Recipe] {
        store.recipes.filter {
            $0.name.matchesSearch(searchText) || ($0.style?.name.matchesSearch(searchText) ?? false)
        }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(filtered) { recipe in
                NavigationLink(value: recipe.id) {
                    RecipeRow(recipe: recipe)
                }
                .contextMenu {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        selection = store.duplicate(id: recipe.id)?.id
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        delete([recipe.id])
                    }
                }
                .swipeActions(edge: .leading) {
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        selection = store.duplicate(id: recipe.id)?.id
                    }
                    .tint(.brewAmber)
                }
            }
            .onDelete { offsets in
                delete(offsets.map { filtered[$0].id })
            }
        }
        .overlay {
            if store.recipes.isEmpty {
                ContentUnavailableView {
                    Label("No Recipes", systemImage: "book.closed")
                } description: {
                    Text("Tap + to create your first beer recipe.")
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search recipes")
        .navigationTitle("Recipes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(RecipeType.allCases, id: \.self) { type in
                        Button(type.displayName) { selection = store.newRecipe(type: type).id }
                    }
                } label: {
                    Label("New Recipe", systemImage: "plus")
                } primaryAction: {
                    selection = store.newRecipe().id
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Brewing Tools", systemImage: "function") { showTools = true }
                    Button("Ingredient Library", systemImage: "leaf") { showLibrary = true }
                    Button("Import BeerXML…", systemImage: "square.and.arrow.down") { showImporter = true }
                    Button("Export All as BeerXML", systemImage: "square.and.arrow.up") { exportAll() }
                        .disabled(store.recipes.isEmpty)
                    Divider()
                    Button("Settings", systemImage: "gear") { showSettings = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.xml, .data], allowsMultipleSelection: true) { result in
            importFiles(result)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showTools) { ToolsView() }
        .sheet(isPresented: $showLibrary) { NavigationStack { IngredientLibraryView() } }
        .sheet(item: $shareItem) { item in ActivityView(items: [item.url]) }
        .alert("Import", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
    }

    private func delete(_ ids: [UUID]) {
        if let selected = selection, ids.contains(selected) { selection = nil }
        store.delete(ids: ids)
    }

    private func importFiles(_ result: Result<[URL], Error>) {
        do {
            var count = 0
            for url in try result.get() {
                let recipes = try store.importBeerXML(from: url)
                count += recipes.count
                if let first = recipes.first { selection = first.id }
            }
            alertMessage = "Imported \(count) recipe\(count == 1 ? "" : "s")."
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func exportAll() {
        do {
            let url = try RecipeExporter.beerXMLFile(for: store.recipes, name: "Brew Recipes")
            shareItem = ShareItem(url: url)
        } catch {
            alertMessage = error.localizedDescription
        }
    }
}

struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        let stats = recipe.stats
        HStack(spacing: 12) {
            BeerSwatch(srm: stats.srm, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.name.isEmpty ? "Untitled" : recipe.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(recipe.style?.name ?? recipe.type.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text("OG \(UnitSystem.gravity(stats.og)) · \(stats.abv, specifier: "%.1f")% · \(stats.ibu, specifier: "%.0f") IBU")
                    if !recipe.sessions.isEmpty {
                        Label("\(recipe.sessions.count)", systemImage: "flame.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Color.brewAmber)
                            .accessibilityLabel("Brewed \(recipe.sessions.count) times")
                    }
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
