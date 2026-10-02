import Foundation

/// Text and color for a bottle label, built from a recipe and (optionally) one of its brews.
public struct BottleLabel: Hashable, Sendable {
    public var title: String
    public var subtitle: String
    public var statsLine: String
    public var dateLine: String
    public var tagline: String
    public var colorHex: String

    public struct Options: Hashable, Sendable {
        public var showStyle = true
        public var showABV = true
        public var showIBU = true
        public var showColor = false
        public var showDate = true

        public init() {}
    }

    /// Uses the brew's measured ABV when it has both OG and FG; otherwise the recipe's estimate.
    public static func make(recipe: Recipe, session: BrewSession?, title: String? = nil, tagline: String = "",
                            options: Options = Options()) -> BottleLabel {
        let stats = recipe.stats
        var parts: [String] = []
        if options.showABV {
            if let og = session?.og, let fg = session?.fg {
                parts.append(String(format: "%.1f%% ABV", BrewMath.abv(og: og, fg: fg)))
            } else {
                parts.append(String(format: "%.1f%% ABV (est.)", stats.abv))
            }
        }
        if options.showIBU { parts.append(String(format: "%.0f IBU", stats.ibu)) }
        if options.showColor { parts.append(String(format: "%.0f SRM", stats.srm)) }

        var dateLine = ""
        if options.showDate, let session {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            dateLine = "Brewed \(formatter.string(from: session.brewDate))"
            if let packaged = session.packagedDate {
                dateLine += " · Bottled \(formatter.string(from: packaged))"
            }
        }

        let name = (title ?? recipe.name).trimmingCharacters(in: .whitespaces)
        return BottleLabel(title: name.isEmpty ? "Homebrew" : name,
                           subtitle: options.showStyle ? (recipe.style?.name ?? "") : "",
                           statsLine: parts.joined(separator: " · "),
                           dateLine: dateLine,
                           tagline: tagline.trimmingCharacters(in: .whitespacesAndNewlines),
                           colorHex: stats.colorHex)
    }
}

/// Printable label sheets (US Letter), sized for common Avery stock.
public enum LabelSheet: String, CaseIterable, Codable, Sendable, Identifiable {
    case avery5163, avery5164

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .avery5163: return "Avery 5163 · 4 × 2 in · 10 per sheet"
        case .avery5164: return "Avery 5164 · 4 × 3⅓ in · 6 per sheet"
        }
    }

    /// Layout in inches.
    public var columns: Int { 2 }
    public var rows: Int { self == .avery5163 ? 5 : 3 }
    public var labelWidth: Double { 4 }
    public var labelHeight: Double { self == .avery5163 ? 2 : 10.0 / 3 }
    public var topMargin: Double { 0.5 }
    public var leftMargin: Double { 0.156_25 }
    public var horizontalGap: Double { 0.1875 }
    public var verticalGap: Double { 0 }
    public var perSheet: Int { columns * rows }

    /// Frame of label `index` (0-based, row by row) in points, origin at the top-left of the page.
    public func frame(at index: Int) -> (x: Double, y: Double, width: Double, height: Double) {
        let column = index % columns
        let row = (index / columns) % rows
        let x = (leftMargin + Double(column) * (labelWidth + horizontalGap)) * 72
        let y = (topMargin + Double(row) * (labelHeight + verticalGap)) * 72
        return (x, y, labelWidth * 72, labelHeight * 72)
    }
}
