import XCTest
@testable import BrewCore

final class WaterChemistryTests: XCTestCase {
    func testSaltAdditions() {
        var treatment = WaterTreatment(source: .distilled)
        treatment.setGrams(5, of: .gypsum)
        treatment.setGrams(3, of: .calciumChloride)
        let w = treatment.resultingProfile(totalWaterL: 30)
        XCTAssertEqual(w.calcium, (232.8 * 5 + 272.6 * 3) / 30, accuracy: 0.01)
        XCTAssertEqual(w.sulfate, 557.9 * 5 / 30, accuracy: 0.01)
        XCTAssertEqual(w.chloride, 482.3 * 3 / 30, accuracy: 0.01)
        XCTAssertEqual(w.sulfateToChloride ?? 0, 1.93, accuracy: 0.01)

        treatment.setGrams(0, of: .gypsum)
        XCTAssertEqual(treatment.salts.map(\.salt), [.calciumChloride])
    }

    func testDilutionAndResidualAlkalinity() {
        let dublin = WaterProfiles.profile(id: "dublin")!
        XCTAssertEqual(dublin.residualAlkalinity, 3.498, accuracy: 0.01)
        XCTAssertEqual(dublin.residualAlkalinityAsCaCO3, 175, accuracy: 1)
        XCTAssertEqual(dublin.diluted(by: 0.5).bicarbonate, 159.5, accuracy: 0.01)
        XCTAssertLessThan(dublin.ionBalanceError, 15, "bundled profiles should roughly balance")
    }

    func testMaltClassification() {
        func cls(_ name: String) -> MashPH.MaltClass? {
            IngredientCatalog.fermentable(named: name).map(MashPH.maltClass)
        }
        XCTAssertEqual(cls("Pale Malt (2-Row)"), .base)
        XCTAssertEqual(cls("Carapils / Carafoam"), .base)
        XCTAssertEqual(cls("Crystal 60L"), .crystal)
        XCTAssertEqual(cls("Special B"), .crystal)
        XCTAssertEqual(cls("Carafa Special II"), .roast)
        XCTAssertEqual(cls("Roasted Barley"), .roast)
        XCTAssertEqual(cls("Acidulated Malt"), .acidulated)
        XCTAssertEqual(cls("Flaked Oats"), .adjunct)
    }

    func testMashPHEstimate() throws {
        var recipe = SampleRecipes.paleAle
        recipe.water = WaterTreatment(source: .distilled)
        let distilled = try XCTUnwrap(recipe.waterReport?.mashPH)
        XCTAssertEqual(distilled.pH, 5.656, accuracy: 0.01)

        // Acid lowers it.
        recipe.water?.acidML = 2
        let acidified = try XCTUnwrap(recipe.waterReport?.mashPH)
        XCTAssertEqual(acidified.pH, 5.536, accuracy: 0.01)

        // Alkaline water raises it.
        recipe.water = WaterTreatment(source: WaterProfiles.profile(id: "dublin")!)
        let dublin = try XCTUnwrap(recipe.waterReport?.mashPH)
        XCTAssertGreaterThan(dublin.pH, 5.85)
    }

    func testPHSuggestions() throws {
        // Pale beer in distilled water needs acid.
        var pale = SampleRecipes.paleAle
        pale.water = WaterTreatment(source: .distilled)
        let report = try XCTUnwrap(pale.waterReport)
        guard case .acid(let ml) = pale.water!.suggestedPHAdjustment(for: report) else {
            return XCTFail("expected an acid suggestion")
        }
        pale.water?.acidML = ml
        XCTAssertEqual(pale.waterReport?.mashPH?.pH ?? 0, 5.4, accuracy: 0.02)

        // A very roasty grist in distilled water needs baking soda.
        let base = IngredientCatalog.fermentable(named: "Maris Otter")!
        let roast = IngredientCatalog.fermentable(named: "Roasted Barley")!
        var dark = Recipe(fermentables: [FermentableAddition(fermentable: base, amountKg: 2),
                                         FermentableAddition(fermentable: roast, amountKg: 1)],
                          water: WaterTreatment(source: .distilled))
        let darkReport = try XCTUnwrap(dark.waterReport)
        XCTAssertLessThan(darkReport.mashPH?.pH ?? 9, 5.4)
        guard case .bakingSoda(let grams) = dark.water!.suggestedPHAdjustment(for: darkReport) else {
            return XCTFail("expected a baking soda suggestion")
        }
        dark.water?.setGrams(grams, of: .bakingSoda)
        XCTAssertEqual(dark.waterReport?.mashPH?.pH ?? 0, 5.4, accuracy: 0.03)
    }

    func testSolverReachesTarget() {
        let target = WaterProfiles.profile(id: "t-pale-hoppy")!
        let salts = WaterSolver.salts(from: .distilled, to: target, totalWaterL: 30)
        var treatment = WaterTreatment(source: .distilled, salts: salts)
        treatment.targetId = target.id
        let result = treatment.resultingProfile(totalWaterL: 30)
        XCTAssertEqual(result.calcium, target.calcium, accuracy: 10)
        XCTAssertEqual(result.sulfate, target.sulfate, accuracy: 15)
        XCTAssertEqual(result.chloride, target.chloride, accuracy: 10)
        XCTAssertEqual(result.bicarbonate, 0, accuracy: 0.001)
        XCTAssertTrue(salts.allSatisfy { $0.grams >= 0 })
    }

    func testSolverNeverRemovesIons() {
        // Starting water already above target: nothing to add.
        let hard = WaterProfiles.profile(id: "burton")!
        let soft = WaterProfiles.profile(id: "t-light-soft")!
        XCTAssertTrue(WaterSolver.salts(from: hard, to: soft, totalWaterL: 30).isEmpty)
    }

    func testWaterPersistsAndAppearsInExports() throws {
        var recipe = SampleRecipes.paleAle
        var treatment = WaterTreatment(source: .distilled, targetId: "t-pale-hoppy")
        treatment.setGrams(8, of: .gypsum)
        treatment.acidML = 1.5
        recipe.water = treatment

        let decoded = try RecipeRepository.decode(RecipeRepository.encode(recipe))
        XCTAssertEqual(decoded.water, treatment)

        let headings = RecipeReport(recipe: recipe, units: .metric).blocks.compactMap { block -> String? in
            if case .heading(let h) = block { return h }
            return nil
        }
        XCTAssertTrue(headings.contains("Water Chemistry"))

        let step = BrewDayPlan.steps(for: recipe, units: .metric).first { $0.id == "prep-water" }
        XCTAssertTrue(step?.detail?.contains("Gypsum") ?? false)
        XCTAssertTrue(step?.detail?.contains("Lactic") ?? false)

        // Recipes without a water plan get no water step.
        XCTAssertNil(BrewDayPlan.steps(for: SampleRecipes.paleAle, units: .metric).first { $0.id == "prep-water" })
    }

    func testScalingScalesWaterAdditions() {
        var recipe = SampleRecipes.paleAle
        var treatment = WaterTreatment(source: .distilled)
        treatment.setGrams(4, of: .gypsum)
        treatment.acidML = 2
        recipe.water = treatment
        let scaled = RecipeScaler.scale(recipe, with: .init(batchSizeL: 40, efficiency: 72))
        XCTAssertEqual(scaled.water?.grams(of: .gypsum) ?? 0, 8, accuracy: 0.001)
        XCTAssertEqual(scaled.water?.acidML ?? 0, 4, accuracy: 0.001)
    }
}
