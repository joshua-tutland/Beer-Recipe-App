import Foundation

/// Stores each recipe as a JSON file in a directory (the app's Documents/Recipes folder),
/// so recipes stay on the device, survive app updates, and are included in iCloud/iTunes backups.
public struct RecipeRepository: Sendable {
    public let directory: URL
    /// Coordinate file access with `NSFileCoordinator`. Required for iCloud (ubiquitous)
    /// containers, so the system's sync process never sees a half-written file.
    public let usesFileCoordination: Bool

    public init(directory: URL, usesFileCoordination: Bool = false) {
        self.directory = directory
        self.usesFileCoordination = usesFileCoordination
    }

    /// Folder for files stored alongside the recipes (inventory, custom ingredients).
    public var supportDirectory: URL { directory.deletingLastPathComponent() }

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

    /// Every readable recipe, newest first. Files iCloud hasn't downloaded yet (`.name.json.icloud`
    /// placeholders) are skipped.
    public func loadAll() -> [Recipe] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { readFile($0).flatMap { try? Self.decoder.decode(Recipe.self, from: $0) } }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    public func save(_ recipe: Recipe) throws {
        try ensureDirectory()
        try writeFile(Self.encoder.encode(recipe), to: url(for: recipe.id))
    }

    public func delete(id: UUID) throws {
        let file = url(for: id)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try coordinate(writing: file, options: .forDeleting) { try FileManager.default.removeItem(at: $0) }
    }

    // MARK: Coordinated file access

    public func readFile(_ url: URL) -> Data? {
        var data: Data?
        try? coordinate(reading: url) { data = try? Data(contentsOf: $0) }
        return data
    }

    public func writeFile(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try coordinate(writing: url, options: .forReplacing) { try data.write(to: $0, options: [.atomic]) }
    }

    #if canImport(ObjectiveC)
    private func coordinate(reading url: URL, _ body: (URL) throws -> Void) throws {
        guard usesFileCoordination else { return try body(url) }
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }

    private func coordinate(writing url: URL, options: NSFileCoordinator.WritingOptions,
                            _ body: (URL) throws -> Void) throws {
        guard usesFileCoordination else { return try body(url) }
        var coordinationError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinationError) { url in
            do { try body(url) } catch { bodyError = error }
        }
        if let error = coordinationError ?? bodyError { throw error }
    }
    #else
    private enum WritingOption { case forDeleting, forReplacing }

    private func coordinate(reading url: URL, _ body: (URL) throws -> Void) throws { try body(url) }

    private func coordinate(writing url: URL, options: WritingOption, _ body: (URL) throws -> Void) throws {
        try body(url)
    }
    #endif

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
