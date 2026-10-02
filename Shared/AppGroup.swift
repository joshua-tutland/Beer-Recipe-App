import Foundation

/// Values shared by the app and its widget extension.
enum AppGroup {
    /// The App Group both targets belong to, from the `APP_GROUP_ID` build setting (via
    /// Info.plist), so it only has to be changed in one place.
    static var identifier: String? {
        guard let id = Bundle.main.object(forInfoDictionaryKey: "BrewAppGroupIdentifier") as? String,
              !id.isEmpty, !id.contains("$(") else { return nil }
        return id
    }

    /// Widget kind for the fermentation status widget, used to ask WidgetKit to reload it.
    static let fermentationWidgetKind = "FermentationStatus"

    static let urlScheme = "brewrecipes"

    /// Opens a recipe in the app, e.g. when a widget is tapped.
    static func recipeURL(_ id: UUID) -> URL {
        URL(string: "\(urlScheme)://recipe/\(id.uuidString)")!
    }

    static func recipeID(from url: URL) -> UUID? {
        guard url.scheme == urlScheme, url.host == "recipe" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
