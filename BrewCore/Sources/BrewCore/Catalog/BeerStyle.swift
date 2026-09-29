import Foundation

public struct BeerStyle: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var category: String
    public var ogMin: Double
    public var ogMax: Double
    public var fgMin: Double
    public var fgMax: Double
    public var ibuMin: Double
    public var ibuMax: Double
    public var srmMin: Double
    public var srmMax: Double
    public var abvMin: Double
    public var abvMax: Double

    public var displayName: String { "\(id) \(name)" }
}

public enum StyleFit: Sendable {
    case low, inRange, high

    public var symbol: String {
        switch self {
        case .low: return "arrow.down.circle.fill"
        case .inRange: return "checkmark.circle.fill"
        case .high: return "arrow.up.circle.fill"
        }
    }
}

public struct StyleComparisonRow: Identifiable, Sendable {
    public var id: String { label }
    public var label: String
    public var value: Double
    public var min: Double
    public var max: Double
    public var fit: StyleFit
    public var format: String

    public func formatted(_ v: Double) -> String { String(format: format, v) }
}

public extension BeerStyle {
    func compare(_ stats: RecipeStats) -> [StyleComparisonRow] {
        func row(_ label: String, _ v: Double, _ lo: Double, _ hi: Double, _ format: String) -> StyleComparisonRow {
            // Round to the displayed precision so 1.0504 vs a max of 1.050 isn't flagged.
            let rounded = Double(String(format: format, v)) ?? v
            let fit: StyleFit = rounded < lo ? .low : (rounded > hi ? .high : .inRange)
            return StyleComparisonRow(label: label, value: v, min: lo, max: hi, fit: fit, format: format)
        }
        return [
            row("OG", stats.og, ogMin, ogMax, "%.3f"),
            row("FG", stats.fg, fgMin, fgMax, "%.3f"),
            row("ABV %", stats.abv, abvMin, abvMax, "%.1f"),
            row("IBU", stats.ibu, ibuMin, ibuMax, "%.0f"),
            row("SRM", stats.srm, srmMin, srmMax, "%.1f")
        ]
    }
}

public enum StyleCatalog {
    public static let all: [BeerStyle] = CatalogLoader.load("styles")

    public static func style(id: String) -> BeerStyle? { all.first { $0.id == id } }

    public static var categories: [String] {
        var seen = Set<String>()
        return all.map(\.category).filter { seen.insert($0).inserted }
    }
}
