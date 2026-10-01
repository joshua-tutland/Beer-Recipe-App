import SwiftUI
import UserNotifications
import BrewCore

@main
struct BeerRecipeApp: App {
    @State private var store = RecipeStore(deferLoading: UserDefaults.standard.bool(forKey: CloudSync.enabledKey))
    @State private var cloud = CloudSync()
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
                .environment(cloud)
                .tint(.brewAmber)
                .task { cloud.start(store: store) }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.flushPendingSaves() }
        }
    }
}
