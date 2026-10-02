import SwiftUI
import BrewCore

/// Split view: recipe list in the sidebar, editor in the detail column.
/// Collapses to a navigation stack on iPhone automatically.
struct ContentView: View {
    @Environment(RecipeStore.self) private var store
    @State private var selection: UUID?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @State private var importMessage: String?

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            RecipeListView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340)
        } detail: {
            if let id = selection, let binding = store.binding(for: id) {
                RecipeEditorView(recipe: binding)
                    .id(id)
            } else {
                ContentUnavailableView {
                    Label("No Recipe Selected", systemImage: "mug")
                } description: {
                    Text("Choose a recipe or create a new one.")
                } actions: {
                    Button("New Recipe") { selection = store.newRecipe().id }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        // Recipes shared from Files, Mail, Messages or AirDrop ("Open in Brew Recipes").
        .onOpenURL { url in
            // brewrecipes://recipe/<id> from a widget; anything else is a shared recipe file.
            if let id = AppGroup.recipeID(from: url) {
                selection = id
            } else {
                openSharedFile(url)
            }
        }
        // "Open Recipe" from Siri or Shortcuts.
        .onChange(of: AppRouter.shared.recipeToOpen) { _, id in
            guard let id else { return }
            store.reloadFromDisk()
            selection = id
            AppRouter.shared.recipeToOpen = nil
        }
        .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func openSharedFile(_ url: URL) {
        guard url.isFileURL else { return }
        do {
            let imported = try store.importRecipeFile(from: url)
            if let first = imported.first { selection = first.id }
            if imported.count > 1 { importMessage = "Imported \(imported.count) recipes." }
        } catch {
            importMessage = "\(url.lastPathComponent) couldn't be opened: \(error.localizedDescription)"
        }
    }
}
