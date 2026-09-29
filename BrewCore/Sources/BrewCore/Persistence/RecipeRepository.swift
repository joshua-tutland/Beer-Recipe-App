import Foundation

/// Stores each recipe as a JSON file in a directory (the app's Documents/Recipes folder),
/// so recipes stay on the device, survive app updates, and are included in iCloud/iTunes backups.
public struct RecipeRepository: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `Documents/Recipes` in the app sandbox.
    public static func documents() -> RecipeRepository {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return RecipeRepository(directory: docs.appendingPathComponent("Recipes", isDirectory: true))
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func loadAll() -> [Recipe] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Self.decoder.decode(Recipe.self, from: Data(contentsOf: $0)) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func save(_ recipe: Recipe) throws {
        try ensureDirectory()
        let data = try Self.encoder.encode(recipe)
        try data.write(to: url(for: recipe.id), options: [.atomic])
    }

    public func delete(id: UUID) throws {
        let file = url(for: id)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }

    public static func encode(_ recipe: Recipe) throws -> Data { try encoder.encode(recipe) }
    public static func decode(_ data: Data) throws -> Recipe { try decoder.decode(Recipe.self, from: data) }
}

/// The brewer's own ingredients (added by hand or imported), stored alongside recipes.
public struct CustomIngredients: Codable, Hashable, Sendable {
    public var fermentables: [Fermentable] = []
    public var hops: [Hop] = []
    public var yeasts: [Yeast] = []
    public var miscs: [Misc] = []

    public init() {}

    public static func fileURL(in directory: URL) -> URL {
        directory.appendingPathComponent("custom-ingredients.json")
    }

    public static func load(from url: URL) -> CustomIngredients {
        guard let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(CustomIngredients.self, from: data) else {
            return CustomIngredients()
        }
        return value
    }

    public func save(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: [.atomic])
    }
}
