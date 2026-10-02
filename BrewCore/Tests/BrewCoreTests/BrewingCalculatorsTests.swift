import XCTest
@testable import BrewCore

final class YeastStarterTests: XCTestCase {
    func testViabilityAndExtract() {
        XCTAssertEqual(YeastStarter.liquidCells(packs: 1, ageDays: 0), 100)
        XCTAssertEqual(YeastStarter.liquidCells(packs: 2, ageDays: 30), 158, accuracy: 0.1)
        XCTAssertEqual(YeastStarter.liquidCells(packs: 1, ageDays: 400), 0)
        XCTAssertEqual(YeastStarter.dryMaltExtractGrams(volumeL: 1, gravity: 1.036), 98, accuracy: 1)
    }

    func testStirPlateGrowth() {
        // 100 B cells in a 1 L, 1.036 starter on a stir plate → ~237 B (Braukaiser).
        let result = YeastStarter.grow(cellsBillions: 100, step: .init(volumeL: 1))
        XCTAssertEqual(result.endCellsBillions, 237, accuracy: 2)
        // Overpitched starters barely grow.
        let crowded = YeastStarter.grow(cellsBillions: 400, step: .init(volumeL: 1))
        XCTAssertEqual(crowded.endCellsBillions, 400, accuracy: 0.001)
    }

    func testNoStirGrowth() {
        // 100 B cells in 2 L without a stir plate → ~208 B (White).
        let result = YeastStarter.grow(cellsBillions: 100, step: .init(volumeL: 2, aeration: .none))
        XCTAssertEqual(result.endCellsBillions, 208, accuracy: 2)
    }

    func testStepsCompound() {
        let results = YeastStarter.run(startingCells: 100, steps: [.init(volumeL: 1), .init(volumeL: 2)])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[1].startCellsBillions, results[0].endCellsBillions)
        XCTAssertGreaterThan(results[1].endCellsBillions, results[0].endCellsBillions)
    }
}

final class CarbonationTests: XCTestCase {
    func testForceCarbonationPressure() {
        // Matches standard carbonation charts.
        XCTAssertEqual(Carbonation.forceCarbonationPSI(tempC: BrewMath.fToC(38), volumes: 2.5), 11.2, accuracy: 0.2)
        XCTAssertEqual(Carbonation.forceCarbonationPSI(tempC: BrewMath.fToC(45), volumes: 2.4), 13.7, accuracy: 0.2)
        XCTAssertGreaterThan(Carbonation.forceCarbonationPSI(tempC: 3, volumes: 3.0),
                             Carbonation.forceCarbonationPSI(tempC: 3, volumes: 2.0))
    }

    func testBalancedLineLength() {
        // 12 psi, 3/16" vinyl, faucet 1 ft above the keg: (12 − 0.5 − 1) / 3 = 3.5 ft.
        XCTAssertEqual(Carbonation.balancedLineFeet(kegPSI: 12, line: .vinyl3_16, riseFeet: 1), 3.5, accuracy: 0.001)
        XCTAssertEqual(Carbonation.balancedLineFeet(kegPSI: 0, line: .vinyl3_16), 0)
    }
}

final class HopSubstitutionTests: XCTestCase {
    func testSuggestionsComeFromTheCatalog() throws {
        let cascade = try XCTUnwrap(IngredientCatalog.hop(named: "Cascade"))
        let names = HopSubstitution.suggestions(for: cascade, in: IngredientCatalog.hops).map(\.name)
        XCTAssertTrue(names.contains("Centennial"), "\(names)")
        XCTAssertFalse(names.contains("Cascade"))
    }

    func testKettleAdditionKeepsBitterness() throws {
        let magnum = try XCTUnwrap(IngredientCatalog.hop(named: "Magnum"))
        let warrior = try XCTUnwrap(IngredientCatalog.hop(named: "Warrior"))
        var recipe = SampleRecipes.paleAle
        let index = try XCTUnwrap(recipe.hops.firstIndex { $0.hop.id == magnum.id })
        let before = recipe.stats.ibu
        recipe.hops[index] = HopSubstitution.substitute(recipe.hops[index], with: warrior)
        XCTAssertEqual(recipe.hops[index].hop.name, "Warrior")
        XCTAssertEqual(recipe.hops[index].amountGrams, 12 * 13 / 16, accuracy: 0.001)
        XCTAssertEqual(recipe.stats.ibu, before, accuracy: 0.01)
    }

    func testDryHopKeepsWeight() throws {
        let citra = try XCTUnwrap(IngredientCatalog.hop(named: "Citra"))
        var recipe = SampleRecipes.paleAle
        let index = try XCTUnwrap(recipe.hops.firstIndex { $0.use == .dryHop })
        let grams = recipe.hops[index].amountGrams
        recipe.hops[index] = HopSubstitution.substitute(recipe.hops[index], with: citra)
        XCTAssertEqual(recipe.hops[index].amountGrams, grams)
        XCTAssertEqual(recipe.hops[index].alphaAcid, citra.alphaAcid)
    }
}
