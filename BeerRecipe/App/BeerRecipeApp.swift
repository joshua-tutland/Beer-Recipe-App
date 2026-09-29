import SwiftUI
import BrewCore

@main
struct BeerRecipeApp: App {
    @State private var store = RecipeStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .tint(.brewAmber)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushPendingSaves() }
        }
    }
}
