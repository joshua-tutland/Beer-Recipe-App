import Foundation

/// Resizes a recipe to a new batch size and/or brewhouse efficiency while keeping the beer the same.
public enum RecipeScaler {
    public struct Options: Hashable, Sendable {
        public var batchSizeL: Double
        public var efficiency: Double
        /// Re-balance kettle hop additions so the scaled recipe hits the original IBU exactly.
        public var preserveBitterness: Bool

        public init(batchSizeL: Double, efficiency: Double, preserveBitterness: Bool = true) {
            self.batchSizeL = batchSizeL
            self.efficiency = efficiency
            self.preserveBitterness = preserveBitterness
        }
    }

    /// Returns a scaled copy of `recipe`.
    ///
    /// - Every ingredient is multiplied by the volume ratio.
    /// - Mashed ingredients are additionally adjusted for the efficiency change, so OG stays the same.
    /// - With `preserveBitterness`, boil / first wort / whirlpool / mash hops are nudged so IBU
    ///   matches the original (equipment losses don't scale, which shifts utilization slightly).
    ///   Dry hops scale with volume only.
    public static func scale(_ recipe: Recipe, with options: Options) -> Recipe {
        let oldBatch = recipe.equipment.batchSizeL
        guard oldBatch > 0, options.batchSizeL > 0, options.efficiency > 0 else { return recipe }

        let volumeRatio = options.batchSizeL / oldBatch
        let efficiencyRatio = recipe.equipment.efficiency / options.efficiency

        var scaled = recipe
        scaled.equipment.batchSizeL = options.batchSizeL
        scaled.equipment.efficiency = options.efficiency

        for i in scaled.fermentables.indices {
            let mashed = scaled.fermentables[i].fermentable.type.isMashed
            scaled.fermentables[i].amountKg *= volumeRatio * (mashed ? efficiencyRatio : 1)
        }
        for i in scaled.hops.indices {
            scaled.hops[i].amountGrams *= volumeRatio
        }
        for i in scaled.miscs.indices {
            scaled.miscs[i].amount *= volumeRatio
        }
        if var water = scaled.water {
            // Salts are dosed per liter of brewing water, which grows with the batch.
            for i in water.salts.indices { water.salts[i].grams *= volumeRatio }
            water.acidML *= volumeRatio
            scaled.water = water
        }
        for i in scaled.yeasts.indices {
            scaled.yeasts[i].packs = max(1, (scaled.yeasts[i].packs * volumeRatio).rounded(.up))
        }

        if options.preserveBitterness {
            let target = recipe.stats.ibu
            // IBU is linear in hop weight at a fixed gravity, and gravity is preserved, so this
            // converges immediately; a second pass absorbs the small change in boil gravity.
            for _ in 0..<2 {
                let current = scaled.stats.ibu
                guard target > 0, current > 0 else { break }
                let correction = target / current
                for i in scaled.hops.indices where scaled.hops[i].use != .dryHop {
                    scaled.hops[i].amountGrams *= correction
                }
            }
        }
        return scaled
    }

    /// A name for a scaled copy, e.g. "Cascade Pale Ale (40 L)".
    public static func scaledName(_ name: String, batchSizeL: Double, units: UnitSystem) -> String {
        "\(name) (\(units.formatVolume(liters: batchSizeL)))"
    }
}
