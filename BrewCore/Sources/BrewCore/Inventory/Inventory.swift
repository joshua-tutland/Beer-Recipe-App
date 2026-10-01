import Foundation

public enum InventoryKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case fermentable, hop, yeast, misc

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fermentable: return "Malts & Sugars"
        case .hop: return "Hops"
        case .yeast: return "Yeast"
        case .misc: return "Other"
        }
    }
}

/// Something the brewer has on hand.
///
/// Amounts are stored in fixed units: kilograms for fermentables, grams for hops, packs for
/// yeast, and the item's own `unit` (g, mL, tablet…) for other ingredients.
public struct InventoryItem: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var kind: InventoryKind
    /// Catalog or custom ingredient id, used to match recipe additions.
    public var ingredientId: String
    public var name: String
    public var amount: Double
    /// Unit for `.misc` items; ignored for the other kinds.
    public var unit: String
    /// Alpha acid of this hop lot, if known.
    public var alphaAcid: Double?
    public var bestBefore: Date?
    public var notes: String

    public init(id: UUID = UUID(), kind: InventoryKind, ingredientId: String, name: String, amount: Double,
                unit: String = "", alphaAcid: Double? = nil, bestBefore: Date? = nil, notes: String = "") {
        self.id = id
        self.kind = kind
        self.ingredientId = ingredientId
        self.name = name
        self.amount = amount
        self.unit = unit
        self.alphaAcid = alphaAcid
        self.bestBefore = bestBefore
        self.notes = notes
    }

    public init(fermentable: Fermentable, kg: Double) {
        self.init(kind: .fermentable, ingredientId: fermentable.id, name: fermentable.name, amount: kg)
    }

    public init(hop: Hop, grams: Double, alphaAcid: Double? = nil) {
        self.init(kind: .hop, ingredientId: hop.id, name: hop.name, amount: grams, alphaAcid: alphaAcid ?? hop.alphaAcid)
    }

    public init(yeast: Yeast, packs: Double) {
        self.init(kind: .yeast, ingredientId: yeast.id, name: yeast.displayName, amount: packs)
    }

    public init(misc: Misc, amount: Double, unit: String? = nil) {
        self.init(kind: .misc, ingredientId: misc.id, name: misc.name, amount: amount, unit: unit ?? misc.defaultUnit)
    }

    public func isExpired(at date: Date = Date()) -> Bool {
        bestBefore.map { $0 < date } ?? false
    }

    /// Whether this stock item can supply a requirement for the given ingredient.
    func matches(kind: InventoryKind, ingredientId: String, name: String, unit: String) -> Bool {
        guard self.kind == kind else { return false }
        if kind == .misc && self.unit.caseInsensitiveCompare(unit) != .orderedSame { return false }
        return self.ingredientId == ingredientId || self.name.caseInsensitiveCompare(name) == .orderedSame
    }
}

/// How much of one ingredient a recipe needs, against what's in stock.
public struct IngredientNeed: Hashable, Identifiable, Sendable {
    public var id: String { "\(kind.rawValue)/\(ingredientId)/\(unit)" }
    public var kind: InventoryKind
    public var ingredientId: String
    public var name: String
    public var required: Double
    public var onHand: Double
    /// Unit for `.misc` needs.
    public var unit: String

    public var shortfall: Double { max(0, required - onHand) }
    public var isCovered: Bool { shortfall <= Inventory.tolerance(kind) }
}

public enum Inventory {
    /// Amounts below this count as "none left" (avoids 0.0000001 kg leftovers).
    static func tolerance(_ kind: InventoryKind) -> Double {
        switch kind {
        case .fermentable: return 0.001  // 1 g
        case .hop: return 0.05
        case .yeast: return 0.01
        case .misc: return 0.001
        }
    }

    /// Every ingredient the recipe uses, combined (e.g. three Cascade additions → one line).
    public static func needs(for recipe: Recipe, stock: [InventoryItem]) -> [IngredientNeed] {
        var order: [String] = []
        var needs: [String: IngredientNeed] = [:]

        func add(_ kind: InventoryKind, _ ingredientId: String, _ name: String, _ amount: Double, unit: String = "") {
            guard amount > 0 else { return }
            let key = "\(kind.rawValue)/\(ingredientId)/\(unit.lowercased())"
            if needs[key] == nil {
                order.append(key)
                let onHand = stock
                    .filter { $0.matches(kind: kind, ingredientId: ingredientId, name: name, unit: unit) }
                    .reduce(0) { $0 + $1.amount }
                needs[key] = IngredientNeed(kind: kind, ingredientId: ingredientId, name: name,
                                            required: 0, onHand: onHand, unit: unit)
            }
            needs[key]?.required += amount
        }

        for a in recipe.fermentables { add(.fermentable, a.fermentable.id, a.fermentable.name, a.amountKg) }
        for h in recipe.hops { add(.hop, h.hop.id, h.hop.name, h.amountGrams) }
        for y in recipe.yeasts { add(.yeast, y.yeast.id, y.yeast.displayName, y.packs) }
        for m in recipe.miscs { add(.misc, m.misc.id, m.misc.name, m.amount, unit: m.unit) }

        return order.compactMap { needs[$0] }
    }

    public static func canBrew(_ recipe: Recipe, stock: [InventoryItem]) -> Bool {
        needs(for: recipe, stock: stock).allSatisfy(\.isCovered)
    }

    /// Stock after brewing the recipe. Uses the oldest (soonest best-before) lots first and removes
    /// lots that run out. Ingredients not in stock are simply skipped.
    public static func deducting(_ recipe: Recipe, from stock: [InventoryItem]) -> [InventoryItem] {
        var result = stock
        for need in needs(for: recipe, stock: stock) {
            var remaining = need.required
            let lots = result.indices
                .filter { result[$0].matches(kind: need.kind, ingredientId: need.ingredientId, name: need.name, unit: need.unit) }
                .sorted { (result[$0].bestBefore ?? .distantFuture) < (result[$1].bestBefore ?? .distantFuture) }
            for i in lots where remaining > 0 {
                let used = min(result[i].amount, remaining)
                result[i].amount -= used
                remaining -= used
            }
        }
        return result.filter { $0.amount > tolerance($0.kind) }
    }

    /// Adds the missing amounts to stock (after a shopping trip).
    public static func restocking(_ needs: [IngredientNeed], into stock: [InventoryItem]) -> [InventoryItem] {
        var result = stock
        for need in needs where !need.isCovered {
            if let i = result.firstIndex(where: {
                $0.matches(kind: need.kind, ingredientId: need.ingredientId, name: need.name, unit: need.unit)
            }) {
                result[i].amount += need.shortfall
            } else {
                result.append(InventoryItem(kind: need.kind, ingredientId: need.ingredientId, name: need.name,
                                            amount: need.shortfall, unit: need.unit))
            }
        }
        return result
    }

    /// Plain-text shopping list for sharing.
    public static func shoppingList(for recipe: Recipe, needs: [IngredientNeed], units: UnitSystem) -> String {
        let missing = needs.filter { !$0.isCovered }
        guard !missing.isEmpty else { return "Everything for \(recipe.name) is in stock." }
        var lines = ["Shopping list: \(recipe.name)", ""]
        for kind in InventoryKind.allCases {
            let items = missing.filter { $0.kind == kind }
            guard !items.isEmpty else { continue }
            lines.append(kind.displayName)
            for need in items {
                lines.append("☐ \(format(need.shortfall, kind: kind, unit: need.unit, units: units))  \(need.name)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Formats an amount in the right unit for its kind.
    public static func format(_ amount: Double, kind: InventoryKind, unit: String, units: UnitSystem) -> String {
        switch kind {
        case .fermentable: return units.formatLargeWeight(kg: amount)
        case .hop: return units.formatSmallWeight(grams: amount)
        case .yeast:
            let packs = UnitSystem.number(amount, digits: amount == amount.rounded() ? 0 : 1)
            return "\(packs) pack\(amount == 1 ? "" : "s")"
        case .misc: return "\(UnitSystem.number(amount, digits: amount < 10 ? 1 : 0)) \(unit)"
        }
    }
}
