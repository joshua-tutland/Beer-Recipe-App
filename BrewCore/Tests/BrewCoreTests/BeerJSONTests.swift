import XCTest
@testable import BrewCore

final class BeerJSONTests: XCTestCase {
    private func sampleWithEverything() -> Recipe {
        var recipe = SampleRecipes.paleAle
        recipe.fermentation.secondaryDays = 7
        recipe.notes = "Line one\nLine \"two\""
        if let oats = IngredientCatalog.fermentable(named: "Flaked Oats") {
            recipe.fermentables.append(FermentableAddition(fermentable: oats, amountKg: 0.3))
        }
        if let lactose = IngredientCatalog.fermentable(named: "Lactose") {
            recipe.fermentables.append(FermentableAddition(fermentable: lactose, amountKg: 0.2))
        }
        if let magnum = IngredientCatalog.hop(named: "Magnum") {
            recipe.hops.append(HopAddition(hop: magnum, amountGrams: 5, use: .mash, time: 60))
            recipe.hops.append(HopAddition(hop: magnum, amountGrams: 7, use: .boil, time: 0, form: .cryo))
        }
        return recipe
    }

    func testRoundTripKeepsTheBeer() throws {
        let original = sampleWithEverything()
        let data = BeerJSON.export([original])
        XCTAssertTrue(BeerJSON.looksLikeBeerJSON(data))
        let recipe = try XCTUnwrap(BeerJSON.importRecipes(from: data).first)

        XCTAssertEqual(recipe.name, original.name)
        XCTAssertEqual(recipe.author, original.author)
        XCTAssertEqual(recipe.styleId, "18B")
        XCTAssertEqual(recipe.notes, original.notes)
        XCTAssertEqual(recipe.fermentables.count, original.fermentables.count)
        XCTAssertEqual(recipe.hops.count, original.hops.count)
        XCTAssertEqual(recipe.equipment.batchSizeL, original.equipment.batchSizeL, accuracy: 0.001)
        XCTAssertEqual(recipe.equipment.boilOffLPerHour, original.equipment.boilOffLPerHour, accuracy: 0.01)
        XCTAssertEqual(recipe.fermentation.secondaryDays, 7)
        XCTAssertEqual(recipe.fermentation.primaryTempC, original.fermentation.primaryTempC, accuracy: 0.01)

        // Hop uses survive, including the hop stand and dry hop.
        XCTAssertEqual(recipe.hops.map(\.use), original.hops.map(\.use))
        XCTAssertEqual(recipe.hops.map(\.time), original.hops.map(\.time))
        XCTAssertEqual(recipe.hops.last?.form, .cryo)
        // Flaked oats come back as an adjunct, lactose stays unfermentable.
        XCTAssertEqual(recipe.fermentables.first { $0.fermentable.name == "Flaked Oats" }?.fermentable.type, .adjunct)
        XCTAssertEqual(recipe.fermentables.first { $0.fermentable.name == "Lactose" }?.fermentable.fermentability, 0)
        // Whirlfloc tablets: BeerJSON says "each", the app restores "tablet".
        XCTAssertEqual(recipe.miscs.first?.unit, "tablet")
        XCTAssertEqual(recipe.miscs.first?.timeMinutes, 10)

        XCTAssertEqual(recipe.stats.og, original.stats.og, accuracy: 0.0005)
        XCTAssertEqual(recipe.stats.fg, original.stats.fg, accuracy: 0.0005)
        XCTAssertEqual(recipe.stats.ibu, original.stats.ibu, accuracy: 0.5)
        XCTAssertEqual(recipe.stats.srm, original.stats.srm, accuracy: 0.1)

        // CI validates this file against the official BeerJSON schema.
        if let dir = ProcessInfo.processInfo.environment["EXPORT_DIR"] {
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("sample.beerjson.json"))
        }
    }

    func testImportsOtherAppsUnits() throws {
        // A recipe as another app might write it: US units, EBC color, Plato potential.
        let json = """
        {"beerjson": {"version": 1.0, "recipes": [{
          "name": "Imported IPA", "type": "all grain", "author": "Someone",
          "batch_size": {"value": 5.5, "unit": "gal"},
          "efficiency": {"brewhouse": {"value": 70, "unit": "%"}},
          "boil": {"boil_time": {"value": 1, "unit": "hr"}},
          "style": {"name": "American IPA", "category": "IPA", "style_guide": "BJCP 2021", "type": "beer"},
          "mash": {"name": "Mash", "grain_temperature": {"value": 68, "unit": "F"},
                   "mash_steps": [{"name": "Rest", "type": "infusion", "step_temperature": {"value": 152, "unit": "F"}, "step_time": {"value": 1, "unit": "hr"}}]},
          "fermentation": {"name": "F", "fermentation_steps": [{"name": "Primary", "start_temperature": {"value": 66, "unit": "F"}, "step_time": {"value": 2, "unit": "week"}}]},
          "ingredients": {
            "fermentable_additions": [
              {"name": "Some Base Malt", "type": "grain", "yield": {"potential": {"value": 9.25, "unit": "plato"}}, "color": {"value": 4, "unit": "EBC"}, "amount": {"value": 11, "unit": "lb"}},
              {"name": "Honey", "type": "honey", "yield": {"fine_grind": {"value": 75, "unit": "%"}}, "color": {"value": 2, "unit": "SRM"}, "amount": {"value": 16, "unit": "oz"}}
            ],
            "hop_additions": [
              {"name": "Experimental 123", "alpha_acid": {"value": 14.2, "unit": "%"}, "form": "plug", "amount": {"value": 1, "unit": "oz"},
               "timing": {"use": "add_to_boil", "duration": {"value": 60, "unit": "min"}}},
              {"name": "Citra", "alpha_acid": {"value": 13, "unit": "%"}, "form": "pellet", "amount": {"value": 2, "unit": "oz"},
               "timing": {"use": "add_to_fermentation", "duration": {"value": 72, "unit": "hr"}}}
            ],
            "culture_additions": [
              {"name": "House Ale", "type": "ale", "form": "liquid", "producer": "Local Lab", "amount": {"value": 2, "unit": "pkg"}}
            ]
          }}]}}
        """
        let recipe = try XCTUnwrap(BeerJSON.importRecipes(from: Data(json.utf8)).first)

        XCTAssertEqual(recipe.equipment.batchSizeL, 20.82, accuracy: 0.01)
        XCTAssertEqual(recipe.equipment.boilTimeMinutes, 60)
        XCTAssertEqual(recipe.styleId, "21A", "falls back to matching the style name")
        XCTAssertEqual(recipe.mashSteps.first?.tempC ?? 0, 66.67, accuracy: 0.01)
        XCTAssertEqual(recipe.mashSteps.first?.minutes, 60)
        XCTAssertEqual(recipe.equipment.grainTempC, 20, accuracy: 0.01)
        XCTAssertEqual(recipe.fermentation.primaryDays, 14)

        let base = try XCTUnwrap(recipe.fermentables.first)
        XCTAssertEqual(base.amountKg, 4.99, accuracy: 0.01)
        XCTAssertEqual(base.fermentable.potentialPPG, 37, accuracy: 0.3)
        XCTAssertEqual(base.fermentable.colorLovibond, 2.05, accuracy: 0.05)
        let honey = try XCTUnwrap(recipe.fermentables.last)
        XCTAssertEqual(honey.fermentable.type, .sugar)
        XCTAssertEqual(honey.amountKg, 0.4536, accuracy: 0.001)

        let bittering = try XCTUnwrap(recipe.hops.first)
        XCTAssertEqual(bittering.amountGrams, 28.35, accuracy: 0.01)
        XCTAssertEqual(bittering.alphaAcid, 14.2)
        XCTAssertEqual(bittering.use, .boil)
        XCTAssertEqual(bittering.time, 60)
        XCTAssertEqual(bittering.form, .leaf)
        let dryHop = try XCTUnwrap(recipe.hops.last)
        XCTAssertEqual(dryHop.use, .dryHop)
        XCTAssertEqual(dryHop.time, 3)

        XCTAssertEqual(recipe.yeasts.first?.packs, 2)
        XCTAssertEqual(recipe.yeasts.first?.yeast.laboratory, "Local Lab")
        XCTAssertGreaterThan(recipe.stats.og, 1.05)
    }

    func testRejectsNonBeerJSON() {
        XCTAssertThrowsError(try BeerJSON.importRecipes(from: Data("<RECIPES/>".utf8)))
        XCTAssertThrowsError(try BeerJSON.importRecipes(from: Data(#"{"beerjson": {"version": 1}}"#.utf8)))
        XCTAssertFalse(BeerJSON.looksLikeBeerJSON(Data("  <?xml version=\"1.0\"?>".utf8)))
        XCTAssertTrue(BeerJSON.looksLikeBeerJSON(Data("\n  {\"beerjson\": {}}".utf8)))
    }
}
