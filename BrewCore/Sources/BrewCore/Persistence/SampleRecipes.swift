import Foundation

/// Starter recipes shown on first launch.
public enum SampleRecipes {
    public static var all: [Recipe] { [paleAle, hazyIPA, irishStout] }

    private static func grain(_ name: String, _ kg: Double) -> FermentableAddition? {
        IngredientCatalog.fermentable(named: name).map { FermentableAddition(fermentable: $0, amountKg: kg) }
    }

    private static func hop(_ name: String, _ grams: Double, _ use: HopUse, _ time: Double) -> HopAddition? {
        IngredientCatalog.hop(named: name).map { HopAddition(hop: $0, amountGrams: grams, use: use, time: time) }
    }

    private static func yeast(_ productId: String) -> YeastAddition? {
        IngredientCatalog.yeast(productId: productId).map { YeastAddition(yeast: $0) }
    }

    public static var paleAle: Recipe {
        Recipe(
            name: "Cascade Pale Ale",
            author: "Brew Recipe Builder",
            styleId: "18B",
            notes: "A classic American pale ale showcasing Cascade.\nMash at 66°C for a balanced body.",
            fermentables: [
                grain("Pale Malt (2-Row)", 4.3),
                grain("Crystal 40L", 0.35),
                grain("Carapils / Carafoam", 0.2)
            ].compactMap { $0 },
            hops: [
                hop("Magnum", 12, .boil, 60),
                hop("Cascade", 28, .boil, 10),
                hop("Cascade", 42, .whirlpool, 20),
                hop("Cascade", 56, .dryHop, 4)
            ].compactMap { $0 },
            yeasts: [yeast("US-05")].compactMap { $0 },
            miscs: IngredientCatalog.miscs.first { $0.name == "Whirlfloc Tablet" }
                .map { [MiscAddition(misc: $0, amount: 1, timeMinutes: 10)] } ?? []
        )
    }

    public static var hazyIPA: Recipe {
        var r = Recipe(
            name: "Juicy Hazy IPA",
            author: "Brew Recipe Builder",
            styleId: "21C",
            notes: "Soft, juicy and low in bitterness. Keep oxygen exposure to a minimum when dry hopping.",
            fermentables: [
                grain("Pilsner Malt", 4.2),
                grain("Flaked Oats", 1.0),
                grain("Wheat Malt (Pale)", 0.8)
            ].compactMap { $0 },
            hops: [
                hop("Citra", 10, .boil, 60),
                hop("Citra", 50, .whirlpool, 20),
                hop("Mosaic", 50, .whirlpool, 20),
                hop("Citra", 75, .dryHop, 3),
                hop("Mosaic", 75, .dryHop, 3)
            ].compactMap { $0 },
            yeasts: [yeast("Verdant IPA")].compactMap { $0 },
            mashSteps: [MashStep(name: "Saccharification", tempC: 67, minutes: 60)]
        )
        r.fermentation.primaryTempC = 19
        return r
    }

    public static var irishStout: Recipe {
        var r = Recipe(
            name: "Dry Irish Stout",
            author: "Brew Recipe Builder",
            styleId: "15B",
            notes: "Roasty and dry. Serve on nitro if you can.",
            fermentables: [
                grain("Maris Otter", 2.9),
                grain("Flaked Barley", 0.7),
                grain("Roasted Barley", 0.35),
                grain("Chocolate Malt", 0.1)
            ].compactMap { $0 },
            hops: [hop("East Kent Goldings", 50, .boil, 60)].compactMap { $0 },
            yeasts: [yeast("S-04")].compactMap { $0 },
            mashSteps: [MashStep(name: "Saccharification", tempC: 65, minutes: 60)]
        )
        r.fermentation.carbonationVolumes = 2.0
        return r
    }
}
