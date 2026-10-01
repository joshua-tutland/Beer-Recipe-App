import XCTest
@testable import BrewCore

/// Sanity limits for the bundled ingredient data, including entries imported from common-beer-data.
final class IngredientDataTests: XCTestCase {
    func testExpandedCatalogSizes() {
        XCTAssertGreaterThanOrEqual(IngredientCatalog.fermentables.count, 100)
        XCTAssertGreaterThanOrEqual(IngredientCatalog.hops.count, 75)
        XCTAssertGreaterThanOrEqual(IngredientCatalog.yeasts.count, 150)
    }

    func testFermentableValuesAreSane() {
        for f in IngredientCatalog.fermentables {
            XCTAssertTrue((0...46.5).contains(f.potentialPPG), "\(f.name) PPG \(f.potentialPPG)")
            XCTAssertTrue((0...600).contains(f.colorLovibond), "\(f.name) color \(f.colorLovibond)")
            if let fermentability = f.fermentability {
                XCTAssertTrue((0...100).contains(fermentability), f.name)
            }
            // Lactose and maltodextrin are unfermentable; molasses is ~90% fermentable.
            if f.type == .sugar && !["Lactose", "Maltodextrin", "Molasses"].contains(f.name) {
                XCTAssertEqual(f.fermentability, 100, "\(f.name) should ferment fully")
            }
        }
        // Lactose must stay unfermentable under any name.
        for f in IngredientCatalog.fermentables where f.name.lowercased().contains("lactose") || f.name.lowercased().contains("milk sugar") {
            XCTAssertEqual(f.fermentability, 0, f.name)
        }
    }

    func testHopValuesAreSane() {
        for h in IngredientCatalog.hops {
            XCTAssertTrue((1...25).contains(h.alphaAcid), "\(h.name) alpha \(h.alphaAcid)")
        }
    }

    func testYeastValuesAreSane() {
        for y in IngredientCatalog.yeasts {
            XCTAssertLessThanOrEqual(y.attenuationMin, y.attenuationMax, y.displayName)
            XCTAssertTrue((55...100).contains(y.attenuationMin), "\(y.displayName) attenuation \(y.attenuationMin)")
            XCTAssertLessThan(y.tempMinC, y.tempMaxC, y.displayName)
            XCTAssertFalse(y.name.isEmpty)
        }
        // Lab + product id identifies a yeast uniquely.
        let keys = IngredientCatalog.yeasts.map { "\($0.laboratory ?? "")|\($0.productId ?? $0.name)".lowercased() }
        XCTAssertEqual(Set(keys).count, keys.count)
    }

    func testCuratedEntriesKeepTheirIds() {
        // Recipes, inventory and tests refer to these ids; the import must never change them.
        XCTAssertEqual(IngredientCatalog.fermentable(named: "Pale Malt (2-Row)")?.id, "pale-malt-2-row")
        XCTAssertEqual(IngredientCatalog.hop(named: "Cascade")?.id, "cascade")
        XCTAssertEqual(IngredientCatalog.yeast(productId: "US-05")?.id, "fermentis-us-05")
        XCTAssertEqual(IngredientCatalog.yeast(productId: "US-05")?.attenuationMin, 78)
    }

    func testImportedIngredientsAreAvailable() {
        XCTAssertNotNil(IngredientCatalog.hop(named: "Glacier"))
        XCTAssertNotNil(IngredientCatalog.fermentable(named: "Special Roast"))
        XCTAssertNotNil(IngredientCatalog.yeast(productId: "WLP550"))
        XCTAssertFalse(ThirdPartyNotices.text.isEmpty)
        XCTAssertTrue(ThirdPartyNotices.text.contains("Wall Brew Co"))
    }
}
