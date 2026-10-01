import Foundation

enum CatalogLoader {
    static func load<T: Decodable>(_ name: String) -> [T] {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            assertionFailure("Missing bundled resource \(name).json")
            return []
        }
        do {
            return try JSONDecoder().decode([T].self, from: Data(contentsOf: url))
        } catch {
            assertionFailure("Could not decode \(name).json: \(error)")
            return []
        }
    }
}

/// The ingredient database bundled with the app.
///
/// Values are typical figures gathered from maltster, hop grower and yeast lab
/// specifications. Actual lots vary — the app lets the brewer override alpha acid,
/// attenuation, and so on per recipe.
public enum IngredientCatalog {
    public static let fermentables: [Fermentable] = CatalogLoader.load("fermentables")
    public static let hops: [Hop] = CatalogLoader.load("hops")
    public static let yeasts: [Yeast] = CatalogLoader.load("yeasts")
    public static let miscs: [Misc] = CatalogLoader.load("miscs")

    public static func fermentable(named name: String) -> Fermentable? {
        fermentables.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public static func hop(named name: String) -> Hop? {
        hops.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    public static func yeast(productId: String) -> Yeast? {
        yeasts.first { $0.productId?.caseInsensitiveCompare(productId) == .orderedSame }
    }
}

public extension String {
    /// Case- and diacritic-insensitive search helper.
    func matchesSearch(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}

/// License texts for bundled third-party data, shown in Settings.
public enum ThirdPartyNotices {
    public static let text: String = {
        guard let url = Bundle.module.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()
}
