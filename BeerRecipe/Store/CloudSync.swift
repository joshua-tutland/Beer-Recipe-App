import Foundation
import Observation
import BrewCore

/// Optional iCloud sync. When on, the store reads and writes the app's iCloud Drive container
/// instead of the local Documents folder. iOS uploads and downloads the files; this class
/// watches for changes from other devices, makes sure they're downloaded, and settles conflicts
/// (newest recipe wins).
///
/// Requires the iCloud capability with "iCloud Documents" in Xcode (see README). Without it, or
/// when the user isn't signed in to iCloud, sync reports itself unavailable and the app stays local.
@Observable
final class CloudSync {
    enum Status: Equatable {
        case off
        case connecting
        case on(lastChange: Date)
        case unavailable(String)

        var description: String {
            switch self {
            case .off: return "Recipes are stored on this device only."
            case .connecting: return "Connecting to iCloud…"
            case .on(let date): return "Synced with iCloud · updated \(date.formatted(date: .omitted, time: .shortened))"
            case .unavailable(let reason): return reason
            }
        }
    }

    static let enabledKey = "iCloudSyncEnabled"

    private(set) var status: Status = .off
    private(set) var isEnabled = UserDefaults.standard.bool(forKey: CloudSync.enabledKey)

    @ObservationIgnored private weak var store: RecipeStore?
    @ObservationIgnored private var query: NSMetadataQuery?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    deinit { stopWatching() }

    /// Call once at launch.
    func start(store: RecipeStore) {
        guard self.store == nil else { return }  // extra iPad windows share the same sync
        self.store = store
        if isEnabled { connect(carryOver: false) }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if enabled {
            connect(carryOver: true)
        } else {
            stopWatching()
            // Bring the latest iCloud copies back to this device before going local.
            store?.switchRepository(to: .documents(), carryOver: true)
            status = .off
        }
    }

    // MARK: Connecting

    private func connect(carryOver: Bool) {
        status = .connecting
        // The container lookup can block, so it must not run on the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            let container = FileManager.default.url(forUbiquityContainerIdentifier: nil)
            DispatchQueue.main.async { self.connected(to: container, carryOver: carryOver) }
        }
    }

    private func connected(to container: URL?, carryOver: Bool) {
        guard isEnabled else { return }
        guard let container else {
            let reason = FileManager.default.ubiquityIdentityToken == nil
                ? "Sign in to iCloud and turn on iCloud Drive in the Settings app, then try again."
                : "This build doesn't include the iCloud capability. Add iCloud Documents in Xcode (see README)."
            // Fall back to local storage; turning sync back on later merges local recipes in.
            isEnabled = false
            UserDefaults.standard.set(false, forKey: Self.enabledKey)
            store?.switchRepository(to: .documents(), carryOver: false)
            status = .unavailable(reason)
            return
        }
        let recipes = container
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Recipes", isDirectory: true)
        store?.switchRepository(to: RecipeRepository(directory: recipes, usesFileCoordination: true),
                                carryOver: carryOver)
        status = .on(lastChange: Date())
        startWatching()
    }

    // MARK: Watching for changes from other devices

    private func startWatching() {
        stopWatching()
        let query = NSMetadataQuery()
        query.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        query.predicate = NSPredicate(format: "%K LIKE '*.json'", NSMetadataItemFSNameKey)
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryDidFinishGathering, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                self?.queryChanged()
            })
        }
        self.query = query
        query.start()
    }

    private func stopWatching() {
        query?.stop()
        query = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func queryChanged() {
        guard let query else { return }
        query.disableUpdates()
        defer { query.enableUpdates() }

        for case let item as NSMetadataItem in query.results {
            guard let url = item.value(forAttribute: NSMetadataItemURLKey) as? URL else { continue }
            let downloadStatus = item.value(forAttribute: NSMetadataUbiquitousItemDownloadingStatusKey) as? String
            if downloadStatus != NSMetadataUbiquitousItemDownloadingStatusCurrent {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }
            if item.value(forAttribute: NSMetadataUbiquitousItemHasUnresolvedConflictsKey) as? Bool == true {
                resolveConflicts(at: url)
            }
        }
        store?.reloadFromDisk()
        status = .on(lastChange: Date())
    }

    /// Two devices changed the same file while offline: keep the newest recipe (or, for the
    /// inventory and custom-ingredient files, the copy iCloud already chose) and discard the rest.
    private func resolveConflicts(at url: URL) {
        guard let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url), !conflicts.isEmpty,
              let current = NSFileVersion.currentVersionOfItem(at: url) else { return }
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { url in
            if url.deletingLastPathComponent().lastPathComponent == "Recipes" {
                let versions = [current] + conflicts
                let contents = versions.map { (try? Data(contentsOf: $0.url)) ?? Data() }
                if let winner = RecipeSync.winningVersion(contents), winner > 0 {
                    _ = try? versions[winner].replaceItem(at: url, options: [])
                }
            }
            for version in conflicts { version.isResolved = true }
            try? NSFileVersion.removeOtherVersionsOfItem(at: url)
        }
    }
}
