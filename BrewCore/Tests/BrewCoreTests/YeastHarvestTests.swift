import XCTest
@testable import BrewCore

final class YeastHarvestTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private func days(_ n: Double) -> Date { start.addingTimeInterval(n * 86_400) }

    private func harvest(ml: Double = 200, consistency: SlurryConsistency = .medium) throws -> YeastHarvest {
        let yeast = try XCTUnwrap(SampleRecipes.paleAle.yeasts.first?.yeast)
        return YeastHarvest(yeast: yeast, harvestedOn: start, slurryML: ml, consistency: consistency)
    }

    func testCellEstimate() throws {
        let h = try harvest()
        // Medium slurry: 2 B/mL × 75% yeast × 90% viable = 1.35 B/mL.
        XCTAssertEqual(h.billionViableCellsPerML(on: start), 1.35, accuracy: 0.0001)
        XCTAssertEqual(h.viableCells(on: start), 270, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(h.slurryML(forCells: 200, on: start)), 148.1, accuracy: 0.1)
    }

    func testViabilityFallsWithAge() throws {
        let h = try harvest()
        XCTAssertEqual(h.viability(on: days(30)), 0.9 - 0.21, accuracy: 0.0001)
        XCTAssertGreaterThan(try XCTUnwrap(h.slurryML(forCells: 200, on: days(30))),
                             try XCTUnwrap(h.slurryML(forCells: 200, on: start)))
        // Long-forgotten slurry is treated as dead.
        XCTAssertEqual(h.viability(on: days(200)), 0)
        XCTAssertNil(h.slurryML(forCells: 200, on: days(200)))
        XCTAssertEqual(h.viability(on: days(-5)), 0.9, "Dates before the harvest count as day 0")
    }

    func testGenerationsCountOnFromThePitch() throws {
        let recipe = SampleRecipes.paleAle
        var first = BrewSession(recipe: recipe)
        let g1 = try XCTUnwrap(YeastHarvest.harvest(from: first, recipe: recipe, slurryML: 300))
        XCTAssertEqual(g1.generation, 1)
        XCTAssertEqual(g1.sourceSessionID, first.id)
        XCTAssertTrue(g1.source.contains(recipe.name))

        var second = BrewSession(recipe: recipe)
        second.pitch(from: g1)
        XCTAssertEqual(second.pitchedHarvestID, g1.id)
        XCTAssertEqual(second.yeastGeneration, 1)
        let g2 = try XCTUnwrap(YeastHarvest.harvest(from: second, recipe: recipe, slurryML: 300))
        XCTAssertEqual(g2.generation, 2)

        first.yeastGeneration = YeastHarvest.recommendedMaxGeneration
        let old = try XCTUnwrap(YeastHarvest.harvest(from: first, recipe: recipe, slurryML: 100))
        XCTAssertTrue(old.isPastRecommendedGenerations)
    }

    func testRemovingSlurry() throws {
        let a = try harvest(ml: 200)
        let b = try harvest(ml: 100)
        let afterPartial = [a, b].removingSlurry(150, from: a.id)
        XCTAssertEqual(afterPartial.first { $0.id == a.id }?.slurryML, 50)
        let afterAll = afterPartial.removingSlurry(80, from: a.id)
        XCTAssertNil(afterAll.first { $0.id == a.id }, "Empty jars are removed")
        XCTAssertEqual(afterAll.count, 1)
    }

    func testOldSessionsStillDecode() throws {
        let session = BrewSession(recipe: SampleRecipes.paleAle)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        json.removeValue(forKey: "yeastGeneration")
        json.removeValue(forKey: "pitchedHarvestID")
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(BrewSession.self, from: data)
        XCTAssertNil(decoded.yeastGeneration)
        XCTAssertNil(decoded.pitchedHarvestID)
    }

    func testHarvestRoundTrips() throws {
        let h = try harvest(consistency: .thick)
        let decoded = try JSONDecoder().decode(YeastHarvest.self, from: JSONEncoder().encode(h))
        XCTAssertEqual(decoded, h)
    }
}
