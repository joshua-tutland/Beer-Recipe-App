import SwiftUI
import UserNotifications
import BrewCore

@main
struct BeerRecipeApp: App {
    @State private var store = RecipeStore()
    @State private var timers = BrewTimers()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .environment(timers)
                .tint(.brewAmber)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushPendingSaves() }
        }
    }
}
