import Foundation

/// A saved snapshot of a recipe's formulation, so brewers can see how it evolved and roll back.
public struct RecipeVersion: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var note: String
    /// The recipe as it was, without its brew logs and version history.
    public var recipe: Recipe

    public init(id: UUID = UUID(), date: Date = Date(), note: String, of recipe: Recipe) {
        self.id = id
        self.date = date
        self.note = note
        self.recipe = recipe.formulationOnly
    }
}

public extension Recipe {
    /// The recipe without brew logs or version history.
    var formulationOnly: Recipe {
        var copy = self
        copy.sessions = []
        copy.versions = []
        return copy
    }

    /// Whether the ingredients or process differ from `other` (ignoring names of brews, history,
    /// notes and timestamps).
    func formulationDiffers(from other: Recipe) -> Bool {
        var a = formulationOnly
        var b = other.formulationOnly
        for r in [\Recipe.modifiedAt, \Recipe.createdAt] { a[keyPath: r] = .distantPast; b[keyPath: r] = .distantPast }
        a.notes = ""; b.notes = ""
        return a != b
    }

    /// Saves the current formulation as a version, unless it matches the latest one.
    @discardableResult
    mutating func saveVersion(note: String, date: Date = Date()) -> Bool {
        if let latest = versions.first?.recipe, !formulationDiffers(from: latest) { return false }
        versions.insert(RecipeVersion(date: date, note: note, of: self), at: 0)
        return true
    }

    /// Replaces the formulation with a saved version, keeping brew logs and history. The current
    /// formulation is saved first so the restore can be undone.
    mutating func restore(_ version: RecipeVersion) {
        saveVersion(note: "Before restoring “\(version.note)”")
        let sessions = self.sessions
        let versions = self.versions
        let id = self.id
        let created = createdAt
        self = version.recipe
        self.id = id
        self.createdAt = created
        self.modifiedAt = Date()
        self.sessions = sessions
        self.versions = versions
    }
}

// MARK: - Differences

/// Human-readable differences between two versions of a recipe.
public enum RecipeDiff {
    public static func changes(from old: Recipe, to new: Recipe, units: UnitSystem) -> [String] {
        var out: [String] = []
        let n = UnitSystem.number

        if old.name != new.name { out.append("Renamed “\(old.name)” → “\(new.name)”") }
        if old.styleId != new.styleId {
            out.append("Style: \(old.style?.name ?? "none") → \(new.style?.name ?? "none")")
        }
        if old.equipment.batchSizeL != new.equipment.batchSizeL {
            out.append("Batch size: \(units.formatVolume(liters: old.equipment.batchSizeL)) → \(units.formatVolume(liters: new.equipment.batchSizeL))")
        }
        if old.equipment.efficiency != new.equipment.efficiency {
            out.append("Efficiency: \(n(old.equipment.efficiency, 0))% → \(n(new.equipment.efficiency, 0))%")
        }
        if old.equipment.boilTimeMinutes != new.equipment.boilTimeMinutes {
            out.append("Boil: \(n(old.equipment.boilTimeMinutes, 0)) → \(n(new.equipment.boilTimeMinutes, 0)) min")
        }

        // Fermentables, matched by ingredient.
        out += listChanges(old.fermentables, new.fermentables, key: { $0.fermentable.id }, name: { $0.fermentable.name },
                           amount: { units.formatLargeWeight(kg: $0.amountKg) }, value: { $0.amountKg })
        // Hops, matched by variety + use + time.
        out += listChanges(old.hops, new.hops,
                           key: { "\($0.hop.id)|\($0.use.rawValue)|\($0.time)" },
                           name: { "\($0.hop.name) (\($0.use.displayName.lowercased()) \(n($0.time, 0)) \($0.use.timeUnit))" },
                           amount: { units.formatSmallWeight(grams: $0.amountGrams) }, value: { $0.amountGrams })
        out += listChanges(old.yeasts, new.yeasts, key: { $0.yeast.id }, name: { $0.yeast.displayName },
                           amount: { "\(n($0.packs, 0)) pack(s)" }, value: { $0.packs })
        out += listChanges(old.miscs, new.miscs, key: { $0.misc.id }, name: { $0.misc.name },
                           amount: { "\(n($0.amount, 1)) \($0.unit)" }, value: { $0.amount })

        if let a = old.mashSteps.first?.tempC, let b = new.mashSteps.first?.tempC, a != b {
            out.append("Mash: \(units.formatTemperature(celsius: a)) → \(units.formatTemperature(celsius: b))")
        }
        if old.fermentation.primaryTempC != new.fermentation.primaryTempC {
            out.append("Fermentation: \(units.formatTemperature(celsius: old.fermentation.primaryTempC)) → \(units.formatTemperature(celsius: new.fermentation.primaryTempC))")
        }
        if old.water != new.water { out.append("Water treatment changed") }

        let a = old.stats, b = new.stats
        var stats: [String] = []
        if abs(a.og - b.og) >= 0.0005 { stats.append("OG \(UnitSystem.gravity(a.og)) → \(UnitSystem.gravity(b.og))") }
        if abs(a.ibu - b.ibu) >= 0.5 { stats.append("IBU \(n(a.ibu, 0)) → \(n(b.ibu, 0))") }
        if abs(a.srm - b.srm) >= 0.5 { stats.append("SRM \(n(a.srm, 1)) → \(n(b.srm, 1))") }
        if abs(a.abv - b.abv) >= 0.05 { stats.append("ABV \(n(a.abv, 1))% → \(n(b.abv, 1))%") }
        if !stats.isEmpty { out.append(stats.joined(separator: ", ")) }
        return out
    }

    private static func listChanges<T>(_ old: [T], _ new: [T], key: (T) -> String, name: (T) -> String,
                                       amount: (T) -> String, value: (T) -> Double) -> [String] {
        var out: [String] = []
        let oldByKey = Dictionary(old.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        let newByKey = Dictionary(new.map { (key($0), $0) }, uniquingKeysWith: { a, _ in a })
        for item in new {
            if let previous = oldByKey[key(item)] {
                if abs(value(previous) - value(item)) > 0.0001 {
                    out.append("\(name(item)): \(amount(previous)) → \(amount(item))")
                }
            } else {
                out.append("Added \(amount(item)) \(name(item))")
            }
        }
        for item in old where newByKey[key(item)] == nil {
            out.append("Removed \(name(item))")
        }
        return out
    }
}

// MARK: - Tasting scoresheet

/// A BJCP-style 50-point scoresheet.
public struct TastingScoresheet: Codable, Hashable, Sendable {
    public enum Category: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable, Identifiable {
        case aroma, appearance, flavor, mouthfeel, overall

        public var id: String { rawValue }
        public var displayName: String { rawValue.capitalized }

        public var maximum: Int {
            switch self {
            case .aroma: return 12
            case .appearance: return 3
            case .flavor: return 20
            case .mouthfeel: return 5
            case .overall: return 10
            }
        }

        public var prompt: String {
            switch self {
            case .aroma: return "Malt, hops, esters and other aromatics"
            case .appearance: return "Color, clarity and head"
            case .flavor: return "Malt, hops, fermentation character, balance, finish"
            case .mouthfeel: return "Body, carbonation, warmth, creaminess, astringency"
            case .overall: return "Overall drinking pleasure and style accuracy"
            }
        }
    }

    public var scores: [Category: Int]
    public var notes: [Category: String]
    public var tastedOn: Date

    public init(tastedOn: Date = Date()) {
        scores = [:]
        notes = [:]
        self.tastedOn = tastedOn
    }

    public var total: Int {
        Category.allCases.reduce(0) { $0 + min(max(scores[$1] ?? 0, 0), $1.maximum) }
    }

    /// The BJCP scoring guide's descriptor for a total.
    public var rating: String {
        switch total {
        case 45...: return "Outstanding"
        case 38...: return "Excellent"
        case 30...: return "Very Good"
        case 21...: return "Good"
        case 14...: return "Fair"
        default: return "Problematic"
        }
    }
}
