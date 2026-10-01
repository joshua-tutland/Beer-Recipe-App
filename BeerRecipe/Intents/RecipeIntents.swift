import AppIntents
import Foundation
import Observation
import BrewCore

// MARK: - Shared access

/// Reads and writes recipes for Siri and Shortcuts, which can run without the app's UI.
enum RecipeLibrary {
    static func repository() -> RecipeRepository {
        if UserDefaults.standard.bool(forKey: CloudSync.enabledKey),
           let container = FileManager.default.url(forUbiquityContainerIdentifier: nil) {
            let folder = container.appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Recipes", isDirectory: true)
            return RecipeRepository(directory: folder, usesFileCoordination: true)
        }
        return .documents()
    }

    static func allRecipes() -> [Recipe] { repository().loadAll() }

    static func save(_ recipe: Recipe) throws {
        try repository().save(recipe)
        // If the app is running, tell the store to pick up the change.
        NotificationCenter.default.post(name: .recipesChangedOutsideStore, object: nil)
    }
}

extension Notification.Name {
    static let recipesChangedOutsideStore = Notification.Name("recipesChangedOutsideStore")
}

/// Lets an intent ask the UI to show a recipe.
@Observable
final class AppRouter {
    static let shared = AppRouter()
    var recipeToOpen: UUID?
}

// MARK: - Entity

struct RecipeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Recipe"
    static let defaultQuery = RecipeQuery()

    var id: UUID
    var name: String
    var style: String?

    init(_ recipe: Recipe) {
        id = recipe.id
        name = recipe.name
        style = recipe.style?.name
    }

    var displayRepresentation: DisplayRepresentation {
        if let style {
            return DisplayRepresentation(title: "\(name)", subtitle: "\(style)")
        }
        return DisplayRepresentation(title: "\(name)")
    }
}

struct RecipeQuery: EntityStringQuery {
    func entities(for identifiers: [UUID]) async throws -> [RecipeEntity] {
        RecipeLibrary.allRecipes().filter { identifiers.contains($0.id) }.map(RecipeEntity.init)
    }

    func entities(matching string: String) async throws -> [RecipeEntity] {
        RecipeLibrary.allRecipes().filter { $0.name.matchesSearch(string) }.map(RecipeEntity.init)
    }

    func suggestedEntities() async throws -> [RecipeEntity] {
        RecipeLibrary.allRecipes().prefix(20).map(RecipeEntity.init)
    }
}

enum RecipeIntentError: Error, CustomLocalizedStringResourceConvertible {
    case notFound
    case nothingFermenting(String)
    case badGravity

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notFound: return "That recipe couldn't be found."
        case .nothingFermenting(let name): return "\(name) has no brew in progress. Start a brew day in the app first."
        case .badGravity: return "Gravity should be between 0.990 and 1.200."
        }
    }
}

// MARK: - Intents

struct RecipeStatsIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Recipe Stats"
    static let description = IntentDescription("Reads out a recipe's predicted OG, FG, ABV, bitterness and color.")

    @Parameter(title: "Recipe")
    var recipe: RecipeEntity

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let found = RecipeLibrary.allRecipes().first(where: { $0.id == recipe.id }) else {
            throw RecipeIntentError.notFound
        }
        let s = found.stats
        let text = "\(found.name): OG \(UnitSystem.gravity(s.og)), FG \(UnitSystem.gravity(s.fg)), "
            + String(format: "%.1f%% ABV, %.0f IBU, %.0f SRM.", s.abv, s.ibu, s.srm)
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

struct LogGravityIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Gravity Reading"
    static let description = IntentDescription("Adds a hydrometer reading to the brew that's currently fermenting.")

    @Parameter(title: "Recipe")
    var recipe: RecipeEntity

    @Parameter(title: "Gravity", description: "Specific gravity, e.g. 1.012", inclusiveRange: (0.99, 1.2))
    var gravity: Double

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard (0.99...1.2).contains(gravity) else { throw RecipeIntentError.badGravity }
        guard var found = RecipeLibrary.allRecipes().first(where: { $0.id == recipe.id }) else {
            throw RecipeIntentError.notFound
        }
        guard let index = found.sessions.firstIndex(where: { $0.fg == nil }) else {
            throw RecipeIntentError.nothingFermenting(found.name)
        }
        found.sessions[index].readings.append(GravityReading(gravity: gravity, note: "Siri / Shortcuts"))
        found.modifiedAt = Date()
        try RecipeLibrary.save(found)
        var message = "Logged \(UnitSystem.gravity(gravity)) for \(found.name)."
        if let abv = found.sessions[index].results.abv {
            message += String(format: " That's %.1f%% ABV so far.", abv)
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct CalculateABVIntent: AppIntent {
    static let title: LocalizedStringResource = "Calculate ABV"
    static let description = IntentDescription("Works out alcohol by volume from original and final gravity.")

    @Parameter(title: "Original Gravity", inclusiveRange: (1.0, 1.2))
    var originalGravity: Double

    @Parameter(title: "Final Gravity", inclusiveRange: (0.99, 1.2))
    var finalGravity: Double

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let abv = BrewMath.abv(og: originalGravity, fg: finalGravity)
        let rounded = (abv * 10).rounded() / 10
        return .result(value: rounded, dialog: IntentDialog(stringLiteral: String(format: "%.1f%% ABV", abv)))
    }
}

struct OpenRecipeIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Recipe"
    static let openAppWhenRun = true

    @Parameter(title: "Recipe")
    var recipe: RecipeEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.recipeToOpen = recipe.id
        return .result()
    }
}

struct BrewShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RecipeStatsIntent(),
                    phrases: ["Show stats for \(\.$recipe) in \(.applicationName)",
                              "Get \(.applicationName) recipe stats"],
                    shortTitle: "Recipe Stats",
                    systemImageName: "chart.bar.doc.horizontal")
        AppShortcut(intent: LogGravityIntent(),
                    phrases: ["Log a gravity reading in \(.applicationName)",
                              "Log gravity for \(\.$recipe) in \(.applicationName)"],
                    shortTitle: "Log Gravity",
                    systemImageName: "drop")
        AppShortcut(intent: CalculateABVIntent(),
                    phrases: ["Calculate ABV in \(.applicationName)"],
                    shortTitle: "Calculate ABV",
                    systemImageName: "percent")
        AppShortcut(intent: OpenRecipeIntent(),
                    phrases: ["Open \(\.$recipe) in \(.applicationName)"],
                    shortTitle: "Open Recipe",
                    systemImageName: "book")
    }
}
