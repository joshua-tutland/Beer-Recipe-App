import XCTest
@testable import BrewCore

final class BrewingSnapshotTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    /// Noon on 10 March 2026 (UTC), a whole second so it survives ISO 8601 encoding.
    private let brewDay = Date(timeIntervalSince1970: 1_773_144_000)
    private func days(_ n: Int) -> Date { brewDay.addingTimeInterval(Double(n) * 86_400) }

    /// The hazy IPA has dry hops; give it a fermenting batch.
    private func fermentingRecipe() -> (Recipe, BrewSession) {
        var recipe = SampleRecipes.hazyIPA
        var session = BrewSession(recipe: recipe, brewDate: brewDay, name: "Batch 1")
        session.og = 1.064
        session.readings = [GravityReading(date: days(3), gravity: 1.030),
                            GravityReading(date: days(5), gravity: 1.020)]
        recipe.sessions = [session]
        return (recipe, session)
    }

    func testFermentingBatch() throws {
        let (recipe, session) = fermentingRecipe()
        let snapshot = BrewingSnapshot.make(recipes: [recipe, SampleRecipes.paleAle], units: .metric,
                                            now: days(6), calendar: calendar)
        XCTAssertEqual(snapshot.recipeCount, 2)
        XCTAssertEqual(snapshot.brewsThisYear, 1)
        let batch = try XCTUnwrap(snapshot.batches.first)
        XCTAssertEqual(snapshot.batches.count, 1)
        XCTAssertEqual(batch.id, session.id)
        XCTAssertEqual(batch.recipeID, recipe.id)
        XCTAssertEqual(batch.day(on: days(6), calendar: calendar), 6)
        XCTAssertEqual(batch.currentGravity, 1.020, "Latest reading by date")
        XCTAssertEqual(batch.latestReadingDate, days(5))
        XCTAssertEqual(batch.abvSoFar, (1.064 - 1.020) * 131.25, accuracy: 0.0001)
        let expectedProgress = (1.064 - 1.020) / (1.064 - session.plan.fg)
        XCTAssertEqual(batch.progress, min(1, expectedProgress), accuracy: 0.0001)
        XCTAssertFalse(batch.isReadyToPackage)
    }

    func testMilestonesFollowTheFermentationSchedule() throws {
        let (recipe, _) = fermentingRecipe()
        let batch = try XCTUnwrap(BrewingSnapshot.make(recipes: [recipe], units: .metric, now: days(1),
                                                       calendar: calendar).batches.first)
        let primary = Int(recipe.fermentation.primaryDays)
        let dryHops = recipe.hops.filter { $0.use == .dryHop }
        XCTAssertFalse(dryHops.isEmpty)
        XCTAssertEqual(batch.milestones.filter { $0.kind == .dryHop }.count, dryHops.count)
        let start = calendar.startOfDay(for: brewDay)
        for hop in dryHops {
            let date = calendar.date(byAdding: .day, value: Int((recipe.fermentation.primaryDays - hop.time).rounded()), to: start)
            XCTAssertTrue(batch.milestones.contains { $0.kind == .dryHop && $0.date == date && $0.title.contains(hop.hop.name) })
        }
        let check = try XCTUnwrap(batch.milestones.first { $0.kind == .checkFinalGravity })
        XCTAssertEqual(check.date, calendar.date(byAdding: .day, value: primary, to: start))
        XCTAssertEqual(batch.milestones.last?.kind, .package)
        XCTAssertEqual(batch.milestones.map(\.date), batch.milestones.map(\.date).sorted())
        XCTAssertEqual(batch.nextMilestone, batch.milestones.first)
    }

    func testTickedStepsAndFinalGravityDropMilestones() throws {
        var (recipe, session) = fermentingRecipe()
        for hop in recipe.hops where hop.use == .dryHop { session.setStep("dryhop-\(hop.id.uuidString)", done: true) }
        session.fg = 1.014
        recipe.sessions = [session]
        let batch = try XCTUnwrap(BrewingSnapshot.make(recipes: [recipe], units: .metric, now: days(12),
                                                       calendar: calendar).batches.first)
        XCTAssertEqual(batch.milestones.map(\.kind), [.package])
        XCTAssertTrue(batch.isReadyToPackage)
        XCTAssertEqual(batch.currentGravity, 1.014)
        XCTAssertEqual(batch.progress, 1, accuracy: 0.0001, "Past the predicted FG is clamped to 100%")
    }

    func testPackagedUnbrewedAndStaleBatchesAreLeftOut() {
        var recipe = SampleRecipes.paleAle
        var packaged = BrewSession(recipe: recipe, brewDate: brewDay)
        packaged.og = 1.050
        packaged.packagedDate = days(20)
        let planned = BrewSession(recipe: recipe, brewDate: brewDay)  // no OG yet
        var forgotten = BrewSession(recipe: recipe, brewDate: days(-200))
        forgotten.og = 1.050
        recipe.sessions = [packaged, planned, forgotten]
        let snapshot = BrewingSnapshot.make(recipes: [recipe], units: .metric, now: days(21), calendar: calendar)
        XCTAssertTrue(snapshot.batches.isEmpty)
    }

    func testNewestBatchFirst() {
        var a = SampleRecipes.paleAle
        var b = SampleRecipes.irishStout
        var older = BrewSession(recipe: a, brewDate: days(-10)); older.og = 1.050
        var newer = BrewSession(recipe: b, brewDate: days(-2)); newer.og = 1.042
        a.sessions = [older]
        b.sessions = [newer]
        let snapshot = BrewingSnapshot.make(recipes: [a, b], units: .imperial, now: brewDay, calendar: calendar)
        XCTAssertEqual(snapshot.batches.map(\.id), [newer.id, older.id])
    }

    func testFileRoundTripAndContentComparison() throws {
        let (recipe, _) = fermentingRecipe()
        let snapshot = BrewingSnapshot.make(recipes: [recipe], units: .metric, now: days(6), calendar: calendar)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        try snapshot.write(to: url)
        XCTAssertEqual(BrewingSnapshot.read(from: url), snapshot)

        var later = snapshot
        later.generatedAt = days(7)
        XCTAssertTrue(later.hasSameContent(as: snapshot))
        later.batches[0].latestGravity = 1.015
        XCTAssertFalse(later.hasSameContent(as: snapshot))
        XCTAssertNil(BrewingSnapshot.read(from: url.appendingPathExtension("missing")))
    }
}
