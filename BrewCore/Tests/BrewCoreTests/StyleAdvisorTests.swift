import XCTest
@testable import BrewCore

final class StyleAdvisorTests: XCTestCase {
    private func style(_ id: String) throws -> BeerStyle { try XCTUnwrap(StyleCatalog.style(id: id)) }

    private func suggestion(_ stat: StyleSuggestion.Stat, for recipe: Recipe, style: BeerStyle) -> StyleSuggestion? {
        StyleAdvisor.suggestions(for: recipe, style: style, units: .metric).first { $0.stat == stat }
    }

    func testLowGravityScalesFermentables() throws {
        let apa = try style("18B")
        var recipe = SampleRecipes.paleAle
        recipe.apply(.scaleFermentables(0.7))
        XCTAssertLessThan(recipe.stats.og, apa.ogMin)

        let s = try XCTUnwrap(suggestion(.og, for: recipe, style: apa))
        let percents = recipe.stats.fermentableShares.map(\.percent)
        recipe.apply(try XCTUnwrap(s.action))
        // A quarter of the way into 1.045–1.060.
        XCTAssertEqual(recipe.stats.og, 1.048_75, accuracy: 0.0002)
        for (after, before) in zip(recipe.stats.fermentableShares.map(\.percent), percents) {
            XCTAssertEqual(after, before, accuracy: 0.0001, "Grist percentages are kept")
        }
    }

    func testHighBitternessScalesKettleHopsOnly() throws {
        let apa = try style("18B")
        var recipe = SampleRecipes.paleAle
        recipe.apply(.scaleKettleHops(3))
        XCTAssertGreaterThan(recipe.stats.ibu, apa.ibuMax)
        let dryHops = recipe.hops.filter { $0.use == .dryHop }.map(\.amountGrams)

        let s = try XCTUnwrap(suggestion(.ibu, for: recipe, style: apa))
        recipe.apply(try XCTUnwrap(s.action))
        XCTAssertEqual(recipe.stats.ibu, 45, accuracy: 0.05)
        XCTAssertEqual(recipe.hops.filter { $0.use == .dryHop }.map(\.amountGrams), dryHops)
    }

    func testTooLightAddsRoastedMaltForDarkStyles() throws {
        let stout = try style("15B")
        var recipe = SampleRecipes.paleAle
        XCTAssertLessThan(recipe.stats.srm, stout.srmMin)

        let s = try XCTUnwrap(suggestion(.srm, for: recipe, style: stout))
        guard case .addFermentable(let malt, _) = try XCTUnwrap(s.action) else {
            return XCTFail("Expected a new malt, got \(String(describing: s.action))")
        }
        XCTAssertEqual(malt.id, "carafa-special-ii")
        recipe.apply(try XCTUnwrap(s.action))
        XCTAssertEqual(recipe.stats.srm, 28.75, accuracy: 0.05)
    }

    func testTooDarkCutsTheDarkestMalt() throws {
        let apa = try style("18B")
        var recipe = SampleRecipes.irishStout
        let before = recipe.stats.srm
        XCTAssertGreaterThan(before, apa.srmMax)

        let s = try XCTUnwrap(suggestion(.srm, for: recipe, style: apa))
        let darkest = try XCTUnwrap(recipe.fermentables.max { $0.fermentable.colorLovibond < $1.fermentable.colorLovibond })
        recipe.apply(try XCTUnwrap(s.action))
        XCTAssertLessThan(recipe.stats.srm, before)
        let after = recipe.fermentables.first { $0.id == darkest.id }
        XCTAssertTrue(after == nil || after!.amountKg < darkest.amountKg)
    }

    func testSlightlyLightUsesExistingCrystal() throws {
        var recipe = SampleRecipes.paleAle
        let crystal = try XCTUnwrap(recipe.fermentables.first { $0.fermentable.colorLovibond >= 20 })
        recipe.fermentables.removeAll { $0.fermentable.colorLovibond >= 20 && $0.id != crystal.id }
        recipe.apply(.setFermentableAmount(id: crystal.id, kg: 0))
        let apa = try style("18B")
        guard recipe.stats.srm < apa.srmMin else { return }  // already in range without it

        let s = try XCTUnwrap(suggestion(.srm, for: recipe, style: apa))
        guard case .setFermentableAmount(let id, _) = try XCTUnwrap(s.action) else {
            return XCTFail("Expected more of the existing crystal malt")
        }
        XCTAssertEqual(id, crystal.id)
        recipe.apply(try XCTUnwrap(s.action))
        XCTAssertEqual(recipe.stats.srm, 6.25, accuracy: 0.05)
    }

    func testFinalGravityIsAdviceOnly() throws {
        let lightLager = try style("1A")
        let recipe = SampleRecipes.paleAle
        XCTAssertGreaterThan(recipe.stats.fg, lightLager.fgMax)
        let s = try XCTUnwrap(suggestion(.fg, for: recipe, style: lightLager))
        XCTAssertNil(s.action)
        XCTAssertTrue(s.advice.contains("more attenuative"))
    }

    func testMoreyInverse() {
        for srm in [2.0, 8.5, 30] {
            XCTAssertEqual(BrewMath.moreySRM(mcu: StyleAdvisor.mcu(forSRM: srm)), srm, accuracy: 0.0001)
        }
    }
}
