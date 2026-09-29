import SwiftUI
import BrewCore

/// Split view: recipe list in the sidebar, editor in the detail column.
/// Collapses to a navigation stack on iPhone automatically.
struct ContentView: View {
    @Environment(RecipeStore.self) private var store
    @State private var selection: UUID?
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

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
    }
}
