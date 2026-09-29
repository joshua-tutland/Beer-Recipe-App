import XCTest
@testable import BrewCore

final class BrewCalculatorTests: XCTestCase {
    private let paleMalt = Fermentable(id: "test-pale", name: "Test Pale", type: .grain, colorLovibond: 2, potentialPPG: 37)
    private let testHop = Hop(id: "test-hop", name: "Test Hop", alphaAcid: 10)
    private let testYeast = Yeast(id: "test-yeast", name: "Test Ale", attenuationMin: 78, attenuationMax: 82,
                                  tempMinC: 18, tempMaxC: 22)

    private func singleMaltRecipe() -> Recipe {
        Recipe(name: "Test",
               fermentables: [FermentableAddition(fermentable: paleMalt, amountKg: 5)],
               hops: [HopAddition(hop: testHop, amountGrams: 30, use: .boil, time: 60, form: .pellet)],
               yeasts: [YeastAddition(yeast: testYeast)])
    }

    // Expected values were cross-checked with an independent implementation of the same formulas.

    func testGravityAndAlcohol() {
        let stats = singleMaltRecipe().stats
        XCTAssertEqual(stats.og, 1.0556, accuracy: 0.0005)
        XCTAssertEqual(stats.fg, 1.0111, accuracy: 0.0005)
        XCTAssertEqual(stats.abv, 5.84, accuracy: 0.05)
        XCTAssertEqual(stats.ogPlato, 13.71, accuracy: 0.05)
        XCTAssertEqual(stats.preBoilGravity, 1.0478, accuracy: 0.0005)
        XCTAssertEqual(stats.apparentAttenuation, 80, accuracy: 0.1)
    }

    func testTinsethBitterness() {
        let stats = singleMaltRecipe().stats
        XCTAssertEqual(stats.ibu, 34.87, accuracy: 0.2)
        XCTAssertEqual(stats.buGuRatio, 34.87 / 55.6, accuracy: 0.01)
    }

    func testRagerIsHigherForLongBoils() {
        var recipe = singleMaltRecipe()
        let tinseth = recipe.stats.ibu
        recipe.ibuFormula = .rager
        XCTAssertGreaterThan(recipe.stats.ibu, tinseth)
    }

    func testDryHopsAddNoBitterness() {
        var recipe = singleMaltRecipe()
        recipe.hops = [HopAddition(hop: testHop, amountGrams: 100, use: .dryHop, time: 4)]
        XCTAssertEqual(recipe.stats.ibu, 0)
    }

    func testWhirlpoolAddsLessThanBoil() {
        var recipe = singleMaltRecipe()
        recipe.hops = [HopAddition(hop: testHop, amountGrams: 30, use: .whirlpool, time: 20, whirlpoolTempC: 80)]
        let whirlpool = recipe.stats.ibu
        recipe.hops[0].use = .boil
        XCTAssertGreaterThan(whirlpool, 0)
        XCTAssertLessThan(whirlpool, recipe.stats.ibu)
    }

    func testMoreyColor() {
        XCTAssertEqual(singleMaltRecipe().stats.srm, 3.98, accuracy: 0.05)
        XCTAssertEqual(BrewMath.srmToEBC(10), 19.7, accuracy: 0.001)
    }

    func testSimpleSugarFermentsCompletely() {
        let dextrose = Fermentable(name: "Dextrose", type: .sugar, colorLovibond: 0, potentialPPG: 42, fermentability: 100)
        var recipe = singleMaltRecipe()
        recipe.fermentables = [FermentableAddition(fermentable: dextrose, amountKg: 1),
                               FermentableAddition(fermentable: paleMalt, amountKg: 4)]
        let stats = recipe.stats
        XCTAssertEqual(stats.og, 1.0620, accuracy: 0.0005)
        XCTAssertEqual(stats.fg, 1.0089, accuracy: 0.0005)
    }

    func testLactoseIsUnfermentable() {
        let lactose = Fermentable(name: "Lactose", type: .sugar, colorLovibond: 0, potentialPPG: 35, fermentability: 0)
        var recipe = singleMaltRecipe()
        recipe.fermentables = [FermentableAddition(fermentable: lactose, amountKg: 0.5),
                               FermentableAddition(fermentable: paleMalt, amountKg: 4)]
        XCTAssertEqual(recipe.stats.fg, 1.0162, accuracy: 0.0005)
    }

    func testExtractIgnoresEfficiency() {
        let dme = Fermentable(name: "DME", type: .dryExtract, colorLovibond: 4, potentialPPG: 44)
        var recipe = Recipe(type: .extract, fermentables: [FermentableAddition(fermentable: dme, amountKg: 1)])
        let og = recipe.stats.og
        recipe.equipment.efficiency = 40
        XCTAssertEqual(recipe.stats.og, og, accuracy: 0.00001)
        XCTAssertEqual(recipe.stats.spargeWaterL, 0)
    }

    func testWaterVolumes() {
        let stats = singleMaltRecipe().stats
        XCTAssertEqual(stats.strikeWaterL, 15.0, accuracy: 0.01)
        XCTAssertEqual(stats.strikeTempC, 72.29, accuracy: 0.05)
        XCTAssertEqual(stats.preBoilVolumeL, 25.0, accuracy: 0.01)
        XCTAssertEqual(stats.totalWaterL, 30.5, accuracy: 0.01)
        XCTAssertEqual(stats.spargeWaterL, 15.5, accuracy: 0.01)
    }

    func testPrimingSugar() {
        XCTAssertEqual(BrewMath.residualCO2(tempC: 20), 0.861, accuracy: 0.005)
        XCTAssertEqual(singleMaltRecipe().stats.primingDextroseGrams, 123.5, accuracy: 0.5)
    }

    func testCalories() {
        XCTAssertEqual(BrewMath.caloriesPer12oz(og: 1.050, fg: 1.010), 165.2, accuracy: 0.5)
    }

    func testPlatoRoundTrip() {
        for sg in [1.030, 1.050, 1.080, 1.100] {
            XCTAssertEqual(BrewMath.platoToSG(BrewMath.sgToPlato(sg)), sg, accuracy: 0.0005)
        }
    }

    func testEmptyRecipeIsSafe() {
        let stats = Recipe().stats
        XCTAssertEqual(stats.og, 1.0)
        XCTAssertEqual(stats.ibu, 0)
        XCTAssertEqual(stats.srm, 0)
        XCTAssertTrue(stats.abv.isFinite)
    }

    func testUnitConversions() {
        XCTAssertEqual(UnitSystem.imperial.volume(fromLiters: 18.927), 5.0, accuracy: 0.001)
        XCTAssertEqual(UnitSystem.imperial.temperature(fromC: 100), 212, accuracy: 0.001)
        XCTAssertEqual(UnitSystem.imperial.kg(fromLargeWeight: 10), 4.536, accuracy: 0.001)
        XCTAssertEqual(UnitSystem.metric.formatTemperature(celsius: 66.4), "66°C")
    }
}
