import XCTest
@testable import BrewCore

final class RecipeScalerTests: XCTestCase {
    func testDoublingKeepsTheBeerTheSame() {
        let original = SampleRecipes.paleAle
        let scaled = RecipeScaler.scale(original, with: .init(batchSizeL: 40, efficiency: original.equipment.efficiency))

        XCTAssertEqual(scaled.equipment.batchSizeL, 40)
        XCTAssertEqual(scaled.fermentables[0].amountKg, original.fermentables[0].amountKg * 2, accuracy: 0.0001)
        XCTAssertEqual(scaled.stats.og, original.stats.og, accuracy: 0.0001)
        XCTAssertEqual(scaled.stats.fg, original.stats.fg, accuracy: 0.0001)
        XCTAssertEqual(scaled.stats.srm, original.stats.srm, accuracy: 0.01)
        XCTAssertEqual(scaled.stats.ibu, original.stats.ibu, accuracy: 0.05)

        // Dry hops scale with volume only.
        let dryOriginal = original.hops.first { $0.use == .dryHop }!.amountGrams
        let dryScaled = scaled.hops.first { $0.use == .dryHop }!.amountGrams
        XCTAssertEqual(dryScaled, dryOriginal * 2, accuracy: 0.0001)
    }

    func testEfficiencyChangeAdjustsOnlyMashedIngredients() {
        let malt = Fermentable(name: "Malt", type: .grain, colorLovibond: 2, potentialPPG: 37)
        let sugar = Fermentable(name: "Sugar", type: .sugar, colorLovibond: 0, potentialPPG: 46, fermentability: 100)
        let recipe = Recipe(equipment: Equipment(batchSizeL: 20, efficiency: 80),
                            fermentables: [FermentableAddition(fermentable: malt, amountKg: 4),
                                           FermentableAddition(fermentable: sugar, amountKg: 0.5)])
        let scaled = RecipeScaler.scale(recipe, with: .init(batchSizeL: 20, efficiency: 64))

        XCTAssertEqual(scaled.fermentables[0].amountKg, 5.0, accuracy: 0.0001)   // 4 × 80/64
        XCTAssertEqual(scaled.fermentables[1].amountKg, 0.5, accuracy: 0.0001)   // sugar unchanged
        XCTAssertEqual(scaled.stats.og, recipe.stats.og, accuracy: 0.0001)
    }

    func testWithoutPreservingBitternessHopsScaleLinearly() {
        let original = SampleRecipes.paleAle
        let scaled = RecipeScaler.scale(original, with: .init(batchSizeL: 10, efficiency: 72, preserveBitterness: false))
        for (a, b) in zip(original.hops, scaled.hops) {
            XCTAssertEqual(b.amountGrams, a.amountGrams / 2, accuracy: 0.0001)
        }
    }

    func testInvalidTargetsLeaveRecipeUnchanged() {
        let original = SampleRecipes.paleAle
        XCTAssertEqual(RecipeScaler.scale(original, with: .init(batchSizeL: 0, efficiency: 70)), original)
    }
}

final class BrewSessionTests: XCTestCase {
    private let malt = Fermentable(id: "m", name: "Malt", type: .grain, colorLovibond: 2, potentialPPG: 37)

    private func recipe() -> Recipe {
        Recipe(equipment: Equipment(batchSizeL: 20, efficiency: 72),
               fermentables: [FermentableAddition(fermentable: malt, amountKg: 5)])
    }

    func testPlanSnapshotsPredictions() {
        let r = recipe()
        let session = BrewSession(recipe: r)
        XCTAssertEqual(session.name, "Batch 1")
        XCTAssertEqual(session.plan.og, r.stats.og, accuracy: 0.00001)
        XCTAssertEqual(session.plan.mashedPointGallons, 407.855, accuracy: 0.01)
        XCTAssertEqual(session.plan.fixedPointGallons, 0)
        XCTAssertNil(session.results.abv)
        XCTAssertNil(session.results.brewhouseEfficiency)
    }

    func testMeasuredEfficiencyAndAlcohol() {
        var s = BrewSession(recipe: recipe())
        s.og = 1.050
        s.fermenterVolumeL = 20
        s.preBoilGravity = 1.040
        s.preBoilVolumeL = 26
        s.postBoilVolumeL = 22
        s.fg = 1.010

        let r = s.results
        XCTAssertEqual(r.brewhouseEfficiency ?? 0, 64.77, accuracy: 0.05)
        XCTAssertEqual(r.kettleEfficiency ?? 0, 67.36, accuracy: 0.05)
        XCTAssertEqual(r.boilOffLPerHour ?? 0, 4.0, accuracy: 0.001)
        XCTAssertEqual(r.abv ?? 0, 5.25, accuracy: 0.01)
        XCTAssertEqual(r.apparentAttenuation ?? 0, 80, accuracy: 0.01)
        XCTAssertEqual(r.ogDifference ?? 0, 1.050 - s.plan.og, accuracy: 0.00001)

        // Predicted OG at 72% was ~1.0556, so 1.050 means ~72 × 50/55.6.
        XCTAssertEqual(r.brewhouseEfficiency ?? 0, 72 * 50 / ((s.plan.og - 1) * 1000), accuracy: 0.05)
    }

    func testSugarsAreExcludedFromEfficiency() {
        var r = recipe()
        let dextrose = Fermentable(name: "Dextrose", type: .sugar, colorLovibond: 0, potentialPPG: 42, fermentability: 100)
        r.fermentables.append(FermentableAddition(fermentable: dextrose, amountKg: 0.5))
        var s = BrewSession(recipe: r)
        s.og = 1.055
        XCTAssertEqual(s.results.brewhouseEfficiency ?? 0, 59.90, accuracy: 0.05)
    }

    func testLatestReadingIsUsedUntilFinalGravity() {
        var s = BrewSession(recipe: recipe())
        s.og = 1.050
        s.readings = [GravityReading(date: Date(timeIntervalSince1970: 100), gravity: 1.030),
                      GravityReading(date: Date(timeIntervalSince1970: 200), gravity: 1.020)]
        XCTAssertEqual(s.currentGravity, 1.020)
        XCTAssertEqual(s.results.abv ?? 0, 3.94, accuracy: 0.01)
        s.fg = 1.012
        XCTAssertEqual(s.currentGravity, 1.012)
    }

    func testSessionsPersistAndOldRecipesStillLoad() throws {
        var r = SampleRecipes.paleAle
        var s = BrewSession(recipe: r)
        s.og = 1.052
        s.readings = [GravityReading(gravity: 1.020)]
        r.sessions = [s]

        let decoded = try RecipeRepository.decode(RecipeRepository.encode(r))
        XCTAssertEqual(decoded.sessions.first?.og, 1.052)
        XCTAssertEqual(decoded.sessions.first?.readings.count, 1)

        // Simulate a file written before brew logs existed.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: RecipeRepository.encode(SampleRecipes.paleAle)) as? [String: Any])
        json.removeValue(forKey: "sessions")
        let old = try RecipeRepository.decode(JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.sessions.isEmpty)
        XCTAssertEqual(old.hops.count, SampleRecipes.paleAle.hops.count)
    }

    func testDuplicateDropsBrewLog() {
        var r = recipe()
        r.sessions = [BrewSession(recipe: r)]
        XCTAssertTrue(r.duplicated().sessions.isEmpty)
    }

    func testReportIncludesBrewLog() {
        var r = SampleRecipes.paleAle
        var s = BrewSession(recipe: r)
        s.og = 1.052
        s.rating = 4
        r.sessions = [s]
        let hasLog = RecipeReport(recipe: r, units: .metric).blocks.contains { block in
            if case .heading("Brew Log") = block { return true }
            return false
        }
        XCTAssertTrue(hasLog)
    }
}
