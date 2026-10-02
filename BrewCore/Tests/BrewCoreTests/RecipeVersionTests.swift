import XCTest
@testable import BrewCore

final class RecipeVersionTests: XCTestCase {
    func testSaveVersionSkipsUnchangedFormulation() {
        var recipe = SampleRecipes.paleAle
        XCTAssertTrue(recipe.saveVersion(note: "First brew"))
        recipe.notes = "Only notes changed"
        recipe.modifiedAt = Date()
        XCTAssertFalse(recipe.saveVersion(note: "No real change"))
        recipe.hops[0].amountGrams += 5
        XCTAssertTrue(recipe.saveVersion(note: "More Magnum"))
        XCTAssertEqual(recipe.versions.map(\.note), ["More Magnum", "First brew"])
        XCTAssertTrue(recipe.versions.allSatisfy { $0.recipe.versions.isEmpty && $0.recipe.sessions.isEmpty })
    }

    func testRestoreKeepsHistoryAndBrewLogs() {
        var recipe = SampleRecipes.paleAle
        let id = recipe.id
        recipe.saveVersion(note: "Original")
        let original = recipe.versions[0]
        recipe.sessions = [BrewSession(recipe: recipe)]
        recipe.fermentables[0].amountKg = 6

        recipe.restore(original)
        XCTAssertEqual(recipe.fermentables[0].amountKg, 4.3)
        XCTAssertEqual(recipe.sessions.count, 1)
        XCTAssertEqual(recipe.versions.first?.note, "Before restoring “Original”")
        XCTAssertEqual(recipe.versions.first?.recipe.fermentables[0].amountKg, 6)
        XCTAssertEqual(recipe.id, id)
    }

    func testDiffDescribesChanges() throws {
        let old = SampleRecipes.paleAle
        var new = old
        new.fermentables[1].amountKg = 0.45                 // Crystal 40L 0.35 → 0.45
        new.fermentables.remove(at: 2)                      // Carapils removed
        let honey = try XCTUnwrap(IngredientCatalog.fermentable(named: "Honey Malt"))
        new.fermentables.append(FermentableAddition(fermentable: honey, amountKg: 0.2))
        new.hops[0].amountGrams = 15                        // Magnum 12 → 15 g
        new.mashSteps[0].tempC = 67

        let changes = RecipeDiff.changes(from: old, to: new, units: .metric)
        XCTAssertTrue(changes.contains("Crystal 40L: 0.35 kg → 0.45 kg"), "\(changes)")
        XCTAssertTrue(changes.contains("Removed Carapils / Carafoam"), "\(changes)")
        XCTAssertTrue(changes.contains("Added 0.20 kg Honey Malt"), "\(changes)")
        XCTAssertTrue(changes.contains("Magnum (boil 60 min): 12 g → 15 g"), "\(changes)")
        XCTAssertTrue(changes.contains("Mash: 66°C → 67°C"), "\(changes)")
        XCTAssertTrue(changes.contains { $0.hasPrefix("OG ") && $0.contains("IBU") }, "\(changes)")
        XCTAssertTrue(RecipeDiff.changes(from: old, to: old, units: .metric).isEmpty)
    }

    func testVersionsPersistAndOldFilesLoad() throws {
        var recipe = SampleRecipes.paleAle
        recipe.saveVersion(note: "v1")
        let decoded = try RecipeRepository.decode(RecipeRepository.encode(recipe))
        XCTAssertEqual(decoded.versions.count, 1)
        XCTAssertEqual(decoded.versions[0].recipe.hops.count, recipe.hops.count)

        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: RecipeRepository.encode(SampleRecipes.paleAle)) as? [String: Any])
        json.removeValue(forKey: "versions")
        XCTAssertTrue(try RecipeRepository.decode(JSONSerialization.data(withJSONObject: json)).versions.isEmpty)
    }

    func testScoresheet() throws {
        var sheet = TastingScoresheet()
        XCTAssertEqual(sheet.total, 0)
        XCTAssertEqual(sheet.rating, "Problematic")
        sheet.scores = [.aroma: 10, .appearance: 3, .flavor: 17, .mouthfeel: 4, .overall: 8]
        XCTAssertEqual(sheet.total, 42)
        XCTAssertEqual(sheet.rating, "Excellent")
        sheet.scores[.appearance] = 9                        // capped at the category maximum (3)
        XCTAssertEqual(sheet.total, 42)

        var session = BrewSession(recipe: SampleRecipes.paleAle)
        session.scoresheet = sheet
        let decoded = try JSONDecoder().decode(BrewSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(decoded.scoresheet?.total, 42)
    }
}
