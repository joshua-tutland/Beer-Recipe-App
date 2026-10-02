import XCTest
@testable import BrewCore

final class InventoryTests: XCTestCase {
    private var recipe: Recipe { SampleRecipes.paleAle }

    private func fullStock() -> [InventoryItem] {
        Inventory.needs(for: recipe, stock: []).map {
            InventoryItem(kind: $0.kind, ingredientId: $0.ingredientId, name: $0.name, amount: $0.required, unit: $0.unit)
        }
    }

    func testNeedsCombineRepeatedIngredients() throws {
        let needs = Inventory.needs(for: recipe, stock: [])
        // Cascade is used three times (10 min, whirlpool, dry hop): 28 + 42 + 56 g.
        let cascade = try XCTUnwrap(needs.first { $0.name == "Cascade" })
        XCTAssertEqual(cascade.required, 126, accuracy: 0.001)
        XCTAssertEqual(cascade.onHand, 0)
        XCTAssertEqual(cascade.shortfall, 126, accuracy: 0.001)
        XCTAssertEqual(needs.filter { $0.kind == .hop }.count, 2)  // Magnum + Cascade
        XCTAssertEqual(needs.first { $0.kind == .yeast }?.required, 1)
        XCTAssertEqual(needs.first { $0.kind == .misc }?.unit, "tablet")
        XCTAssertFalse(Inventory.canBrew(recipe, stock: []))
    }

    func testOnHandMatchesByIdOrName() throws {
        let cascade = IngredientCatalog.hop(named: "Cascade")!
        let byId = InventoryItem(hop: cascade, grams: 100)
        let byName = InventoryItem(kind: .hop, ingredientId: "something-else", name: "cascade", amount: 50)
        let wrongKind = InventoryItem(kind: .fermentable, ingredientId: cascade.id, name: "Cascade", amount: 999)
        let need = try XCTUnwrap(Inventory.needs(for: recipe, stock: [byId, byName, wrongKind]).first { $0.name == "Cascade" })
        XCTAssertEqual(need.onHand, 150, accuracy: 0.001)
        XCTAssertTrue(need.isCovered)
    }

    func testMiscOnlyMatchesSameUnit() throws {
        let whirlfloc = IngredientCatalog.miscs.first { $0.name == "Whirlfloc Tablet" }!
        let grams = InventoryItem(misc: whirlfloc, amount: 10, unit: "g")
        var need = try XCTUnwrap(Inventory.needs(for: recipe, stock: [grams]).first { $0.kind == .misc })
        XCTAssertEqual(need.onHand, 0)
        let tablets = InventoryItem(misc: whirlfloc, amount: 10, unit: "Tablet")
        need = try XCTUnwrap(Inventory.needs(for: recipe, stock: [tablets]).first { $0.kind == .misc })
        XCTAssertEqual(need.onHand, 10)
    }

    func testCanBrewWithFullStock() {
        XCTAssertTrue(Inventory.canBrew(recipe, stock: fullStock()))
    }

    func testDeductingUsesOldestLotFirstAndRemovesEmptyLots() {
        let malt = IngredientCatalog.fermentable(named: "Pale Malt (2-Row)")!
        let old = InventoryItem(id: UUID(), kind: .fermentable, ingredientId: malt.id, name: malt.name, amount: 2,
                                bestBefore: Date(timeIntervalSince1970: 1_000))
        let fresh = InventoryItem(id: UUID(), kind: .fermentable, ingredientId: malt.id, name: malt.name, amount: 10,
                                  bestBefore: Date(timeIntervalSince1970: 9_000_000_000))
        let unrelated = InventoryItem(kind: .hop, ingredientId: "x", name: "Unused Hop", amount: 30)

        let after = Inventory.deducting(recipe, from: [fresh, old, unrelated])
        XCTAssertNil(after.first { $0.id == old.id }, "the older lot is used up first")
        XCTAssertEqual(after.first { $0.id == fresh.id }?.amount ?? 0, 10 - (4.3 - 2), accuracy: 0.0001)
        XCTAssertEqual(after.first { $0.id == unrelated.id }?.amount, 30)
    }

    func testDeductingFullStockLeavesNothing() {
        XCTAssertTrue(Inventory.deducting(recipe, from: fullStock()).isEmpty)
    }

    func testRestockingCoversShortfall() {
        let malt = IngredientCatalog.fermentable(named: "Pale Malt (2-Row)")!
        let partial = [InventoryItem(fermentable: malt, kg: 1)]
        let needs = Inventory.needs(for: recipe, stock: partial)
        let restocked = Inventory.restocking(needs, into: partial)
        XCTAssertTrue(Inventory.canBrew(recipe, stock: restocked))
        // Existing lot topped up rather than duplicated.
        XCTAssertEqual(restocked.filter { $0.ingredientId == malt.id }.count, 1)
        XCTAssertEqual(restocked.first { $0.ingredientId == malt.id }?.amount ?? 0, 4.3, accuracy: 0.0001)
    }

    func testShoppingList() {
        let list = Inventory.shoppingList(for: recipe, needs: Inventory.needs(for: recipe, stock: []), units: .metric)
        XCTAssertTrue(list.hasPrefix("Shopping list: Cascade Pale Ale"))
        XCTAssertTrue(list.contains("☐ 4.30 kg  Pale Malt (2-Row)"), list)
        XCTAssertTrue(list.contains("☐ 126 g  Cascade"), list)
        XCTAssertTrue(list.contains("☐ 1 pack  Fermentis US-05 Safale American"), list)

        let none = Inventory.shoppingList(for: recipe, needs: Inventory.needs(for: recipe, stock: fullStock()), units: .metric)
        XCTAssertEqual(none, "Everything for Cascade Pale Ale is in stock.")
    }

    func testExpiry() {
        let item = InventoryItem(kind: .yeast, ingredientId: "y", name: "Y", amount: 1, bestBefore: Date(timeIntervalSince1970: 0))
        XCTAssertTrue(item.isExpired())
        XCTAssertFalse(InventoryItem(kind: .yeast, ingredientId: "y", name: "Y", amount: 1).isExpired())
    }
}
