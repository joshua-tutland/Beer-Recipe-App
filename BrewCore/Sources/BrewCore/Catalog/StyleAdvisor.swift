import Foundation

/// A suggestion for bringing a recipe into its style's range, with an optional one-tap fix.
public struct StyleSuggestion: Identifiable, Hashable, Sendable {
    public enum Stat: String, Sendable {
        case og, fg, abv, ibu, srm
    }

    public enum Action: Hashable, Sendable {
        /// Multiply every fermentable's amount (keeps the grist percentages).
        case scaleFermentables(Double)
        /// Multiply every hop addition that adds bitterness (everything except dry hops).
        case scaleKettleHops(Double)
        case setFermentableAmount(id: UUID, kg: Double)
        case addFermentable(Fermentable, kg: Double)
        case removeFermentable(id: UUID)
    }

    public var stat: Stat
    /// What's wrong, e.g. "OG 1.040 is below the style's 1.044–1.060."
    public var problem: String
    /// What to do about it.
    public var advice: String
    public var action: Action?
    /// Button title for `action`.
    public var actionTitle: String?

    public var id: String { stat.rawValue }
}

/// Compares a recipe with its style and suggests changes for anything out of range.
///
/// Fixes aim a quarter of the way into the range rather than at its edge, so a small later edit
/// doesn't push the recipe straight back out.
public enum StyleAdvisor {
    static let inset = 0.25

    public static func suggestions(for recipe: Recipe, style: BeerStyle, units: UnitSystem) -> [StyleSuggestion] {
        let stats = recipe.stats
        let rows = Dictionary(uniqueKeysWithValues: style.compare(stats).map { ($0.label, $0) })
        var result: [StyleSuggestion] = []

        if let row = rows["OG"], row.fit != .inRange,
           let s = gravitySuggestion(recipe: recipe, row: row, units: units) {
            result.append(s)
        }
        if let row = rows["IBU"], row.fit != .inRange {
            result.append(bitternessSuggestion(recipe: recipe, row: row, units: units))
        }
        if let row = rows["SRM"], row.fit != .inRange,
           let s = colorSuggestion(recipe: recipe, row: row, units: units) {
            result.append(s)
        }
        if let row = rows["FG"], row.fit != .inRange {
            result.append(finishingSuggestion(row: row))
        }
        // ABV follows OG and FG; only mention it on its own when those are both fine.
        if let row = rows["ABV %"], row.fit != .inRange, !result.contains(where: { $0.stat == .og || $0.stat == .fg }) {
            let low = row.fit == .low
            result.append(StyleSuggestion(
                stat: .abv,
                problem: "ABV \(row.formatted(row.value))% is \(low ? "below" : "above") the style's \(row.formatted(row.min))–\(row.formatted(row.max))%.",
                advice: low
                    ? "Raise the OG toward the top of its range, or use a more attenuative yeast."
                    : "Lower the OG toward the bottom of its range, or use a less attenuative yeast."))
        }
        return result
    }

    /// The value a fix should aim for.
    static func target(_ row: StyleComparisonRow) -> Double {
        let span = row.max - row.min
        return row.fit == .low ? row.min + span * inset : row.max - span * inset
    }

    // MARK: Gravity

    private static func gravitySuggestion(recipe: Recipe, row: StyleComparisonRow, units: UnitSystem) -> StyleSuggestion? {
        let low = row.fit == .low
        let problem = "OG \(row.formatted(row.value)) is \(low ? "below" : "above") the style's \(row.formatted(row.min))–\(row.formatted(row.max))."
        let currentPoints = (row.value - 1) * 1000
        let goal = target(row)
        let totalKg = recipe.fermentables.reduce(0) { $0 + $1.amountKg }
        guard currentPoints > 0, totalKg > 0 else {
            return StyleSuggestion(stat: .og, problem: problem, advice: "Add fermentables to the recipe.")
        }
        // Gravity points scale exactly with the amount of every fermentable.
        let factor = (goal - 1) * 1000 / currentPoints
        let changeKg = abs(totalKg * (factor - 1))
        let percent = Int((abs(factor - 1) * 100).rounded())
        return StyleSuggestion(
            stat: .og, problem: problem,
            advice: "\(low ? "Increase" : "Reduce") every fermentable by \(percent)% (\(units.formatLargeWeight(kg: changeKg)) in total) to reach about \(row.formatted(goal)). Grist percentages stay the same.",
            action: .scaleFermentables(factor),
            actionTitle: "\(low ? "Increase" : "Reduce") Fermentables \(percent)%")
    }

    // MARK: Bitterness

    private static func bitternessSuggestion(recipe: Recipe, row: StyleComparisonRow, units: UnitSystem) -> StyleSuggestion {
        let low = row.fit == .low
        let problem = "IBU \(row.formatted(row.value)) is \(low ? "below" : "above") the style's \(row.formatted(row.min))–\(row.formatted(row.max))."
        let goal = target(row)
        let kettle = recipe.hops.filter { $0.use != .dryHop }
        guard row.value > 0, !kettle.isEmpty else {
            return StyleSuggestion(stat: .ibu, problem: problem,
                                   advice: "Add a 60-minute bittering hop addition.")
        }
        // Every IBU formula here is linear in hop weight, so scaling the kettle hops scales IBU.
        let factor = goal / row.value
        let grams = kettle.reduce(0) { $0 + $1.amountGrams } * abs(factor - 1)
        let percent = Int((abs(factor - 1) * 100).rounded())
        return StyleSuggestion(
            stat: .ibu, problem: problem,
            advice: "\(low ? "Increase" : "Reduce") every boil and whirlpool hop addition by \(percent)% (\(units.formatSmallWeight(grams: grams)) in total) to reach about \(row.formatted(goal)) IBU. Dry hops are left alone.",
            action: .scaleKettleHops(factor),
            actionTitle: "\(low ? "Increase" : "Reduce") Kettle Hops \(percent)%")
    }

    // MARK: Color

    /// Malt color units needed for an SRM (inverse of the Morey equation).
    static func mcu(forSRM srm: Double) -> Double {
        srm > 0 ? pow(srm / 1.4922, 1 / 0.6859) : 0
    }

    private static func colorSuggestion(recipe: Recipe, row: StyleComparisonRow, units: UnitSystem) -> StyleSuggestion? {
        let low = row.fit == .low
        let problem = "Color \(row.formatted(row.value)) SRM is \(low ? "lighter" : "darker") than the style's \(row.formatted(row.min))–\(row.formatted(row.max)) SRM."
        let goal = target(row)
        let gallons = BrewMath.litersToGallons(max(recipe.equipment.batchSizeL, 0.001))
        let currentMCU = mcu(forSRM: row.value)
        let deltaMCU = mcu(forSRM: goal) - currentMCU
        let goalText = "about \(row.formatted(goal)) SRM"

        if low {
            // Add more of the darkest specialty malt already in the recipe, or a new one.
            // Crystal malt is fine for a little color; dark styles need a roasted malt instead.
            if let darkest = recipe.fermentables.filter({ $0.fermentable.colorLovibond >= 20 })
                .max(by: { $0.fermentable.colorLovibond < $1.fermentable.colorLovibond }),
               goal <= 15 || darkest.fermentable.colorLovibond >= 200 {
                let addKg = BrewMath.lbToKg(deltaMCU * gallons / darkest.fermentable.colorLovibond)
                return StyleSuggestion(
                    stat: .srm, problem: problem,
                    advice: "Add \(units.formatLargeWeight(kg: addKg)) more \(darkest.fermentable.name) for \(goalText).",
                    action: .setFermentableAmount(id: darkest.id, kg: darkest.amountKg + addKg),
                    actionTitle: "Add \(units.formatLargeWeight(kg: addKg)) \(darkest.fermentable.name)")
            }
            let id = goal <= 15 ? "crystal-60l" : "carafa-special-ii"
            guard let malt = IngredientCatalog.fermentables.first(where: { $0.id == id }) else { return nil }
            let addKg = BrewMath.lbToKg(deltaMCU * gallons / malt.colorLovibond)
            return StyleSuggestion(
                stat: .srm, problem: problem,
                advice: "Add \(units.formatLargeWeight(kg: addKg)) of \(malt.name) for \(goalText)."
                    + (goal > 15 ? " It's dehusked, so it adds color without much roast bitterness." : ""),
                action: .addFermentable(malt, kg: addKg),
                actionTitle: "Add \(units.formatLargeWeight(kg: addKg)) \(malt.name)")
        }

        // Too dark: cut back the darkest ingredient.
        guard let darkest = recipe.fermentables.max(by: { $0.fermentable.colorLovibond < $1.fermentable.colorLovibond }),
              darkest.fermentable.colorLovibond > 0 else { return nil }
        let removeKg = BrewMath.lbToKg(-deltaMCU * gallons / darkest.fermentable.colorLovibond)
        if removeKg >= darkest.amountKg * 0.95 {
            return StyleSuggestion(
                stat: .srm, problem: problem,
                advice: "Leave out the \(darkest.fermentable.name)"
                    + (removeKg > darkest.amountKg ? ", then check the color again: other malts are adding color too." : " for \(goalText)."),
                action: .removeFermentable(id: darkest.id),
                actionTitle: "Remove \(darkest.fermentable.name)")
        }
        let newKg = darkest.amountKg - removeKg
        return StyleSuggestion(
            stat: .srm, problem: problem,
            advice: "Use \(units.formatLargeWeight(kg: removeKg)) less \(darkest.fermentable.name) (\(units.formatLargeWeight(kg: newKg)) instead of \(units.formatLargeWeight(kg: darkest.amountKg))) for \(goalText).",
            action: .setFermentableAmount(id: darkest.id, kg: newKg),
            actionTitle: "Use Less \(darkest.fermentable.name)")
    }

    // MARK: Final gravity

    private static func finishingSuggestion(row: StyleComparisonRow) -> StyleSuggestion {
        let low = row.fit == .low
        return StyleSuggestion(
            stat: .fg,
            problem: "FG \(row.formatted(row.value)) is \(low ? "below" : "above") the style's \(row.formatted(row.min))–\(row.formatted(row.max)).",
            advice: low
                ? "The beer will finish too dry. Choose a less attenuative yeast, mash warmer (67–69°C / 153–156°F), or swap some sugar for crystal or dextrin malt."
                : "The beer will finish too sweet. Choose a more attenuative yeast, mash cooler (64–65°C / 147–149°F), or swap some crystal malt for base malt or sugar.")
    }
}

public extension Recipe {
    /// Applies a style suggestion's fix.
    mutating func apply(_ action: StyleSuggestion.Action) {
        switch action {
        case .scaleFermentables(let factor):
            for i in fermentables.indices { fermentables[i].amountKg *= factor }
        case .scaleKettleHops(let factor):
            for i in hops.indices where hops[i].use != .dryHop { hops[i].amountGrams *= factor }
        case .setFermentableAmount(let id, let kg):
            if let i = fermentables.firstIndex(where: { $0.id == id }) { fermentables[i].amountKg = max(0, kg) }
        case .addFermentable(let fermentable, let kg):
            fermentables.append(FermentableAddition(fermentable: fermentable, amountKg: kg))
        case .removeFermentable(let id):
            fermentables.removeAll { $0.id == id }
        }
    }
}
