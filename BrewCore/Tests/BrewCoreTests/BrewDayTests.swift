import XCTest
@testable import BrewCore

final class BrewDayPlanTests: XCTestCase {
    func testAllGrainPlanFollowsTheBrewDay() throws {
        let recipe = SampleRecipes.paleAle
        let steps = BrewDayPlan.steps(for: recipe, units: .metric)
        let ids = steps.map(\.id)

        // Phases appear in brew-day order.
        let phaseOrder = steps.map(\.phase)
        XCTAssertEqual(phaseOrder, phaseOrder.sorted { BrewPhase.allCases.firstIndex(of: $0)! < BrewPhase.allCases.firstIndex(of: $1)! })

        XCTAssertTrue(ids.contains("mash-strike"))
        XCTAssertTrue(ids.contains("sparge"))
        let strike = try XCTUnwrap(steps.first { $0.id == "mash-strike" })
        XCTAssertTrue(strike.title.contains("72°C"), strike.title)

        let mash = try XCTUnwrap(steps.first { $0.id == "mash-0" })
        XCTAssertEqual(mash.durationMinutes, 60)

        // Boil schedule: Magnum at the start, Cascade + Whirlfloc grouped at 10 minutes.
        let boil = try XCTUnwrap(steps.first { $0.id == "boil" })
        XCTAssertEqual(boil.durationMinutes, 60)
        XCTAssertEqual(boil.alerts.map(\.minutesRemaining), [60, 10])
        XCTAssertTrue(boil.alerts[0].title.hasPrefix("Start of boil"))
        XCTAssertTrue(boil.alerts[1].title.contains("Cascade"))
        XCTAssertTrue(boil.alerts[1].title.contains("Whirlfloc"))

        let whirlpool = try XCTUnwrap(steps.first { $0.id == "whirlpool" })
        XCTAssertEqual(whirlpool.durationMinutes, 20)

        // Dry hop 4 days before packaging in a 14-day primary.
        let dryHop = try XCTUnwrap(steps.first { $0.id.hasPrefix("dryhop-") })
        XCTAssertTrue(dryHop.title.hasPrefix("Day 10"), dryHop.title)
        XCTAssertEqual(dryHop.phase, .later)

        XCTAssertEqual(Set(ids).count, ids.count, "step ids must be unique")
    }

    func testExtractPlanSkipsTheMash() {
        let dme = Fermentable(name: "Light DME", type: .dryExtract, colorLovibond: 4, potentialPPG: 44)
        let recipe = Recipe(type: .extract, fermentables: [FermentableAddition(fermentable: dme, amountKg: 3)], mashSteps: [])
        let ids = BrewDayPlan.steps(for: recipe, units: .imperial).map(\.id)
        XCTAssertFalse(ids.contains("mash-strike"))
        XCTAssertFalse(ids.contains("sparge"))
        XCTAssertFalse(ids.contains("prep-crush"))
        XCTAssertTrue(ids.contains("boil"))
    }

    func testFlameoutAdditionAlertsAtZero() {
        var recipe = SampleRecipes.irishStout
        let hop = recipe.hops[0].hop
        recipe.hops.append(HopAddition(hop: hop, amountGrams: 10, use: .boil, time: 0))
        let boil = BrewDayPlan.steps(for: recipe, units: .metric).first { $0.id == "boil" }!
        XCTAssertEqual(boil.alerts.last?.minutesRemaining, 0)
        XCTAssertTrue(boil.alerts.last?.title.hasPrefix("Flameout") ?? false)
    }

    func testSessionRemembersCompletedSteps() throws {
        var session = BrewSession(recipe: SampleRecipes.paleAle)
        XCTAssertFalse(session.isStepDone("sparge"))
        session.setStep("sparge", done: true)
        session.setStep("sparge", done: true)
        XCTAssertEqual(session.completedStepIDs, ["sparge"])
        session.setStep("sparge", done: false)
        XCTAssertFalse(session.isStepDone("sparge"))

        // Sessions saved before the checklist existed still decode.
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        json.removeValue(forKey: "completedStepIDs")
        let old = try JSONDecoder().decode(BrewSession.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(old.completedStepIDs)
    }
}

final class StepTimerTests: XCTestCase {
    func testCountdownPauseAndResume() {
        let t0 = Date(timeIntervalSince1970: 1_000)
        var timer = StepTimer(duration: 600)
        XCTAssertTrue(timer.isIdle)
        XCTAssertEqual(timer.remaining(at: t0), 600)

        timer.start(at: t0)
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(100)), 500)
        XCTAssertEqual(timer.progress(at: t0.addingTimeInterval(150)), 0.25, accuracy: 0.0001)

        timer.pause(at: t0.addingTimeInterval(100))
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(5_000)), 500)  // frozen while paused

        timer.start(at: t0.addingTimeInterval(1_000))
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(1_200)), 300)
        XCTAssertFalse(timer.isFinished(at: t0.addingTimeInterval(1_200)))
        XCTAssertTrue(timer.isFinished(at: t0.addingTimeInterval(1_600)))
        XCTAssertEqual(timer.remaining(at: t0.addingTimeInterval(9_999)), 0)

        timer.reset()
        XCTAssertTrue(timer.isIdle)
        XCTAssertEqual(timer.remaining(at: t0), 600)
    }

    func testFormatting() {
        XCTAssertEqual(StepTimer.format(59.2), "1:00")
        XCTAssertEqual(StepTimer.format(3_549), "59:09")
        XCTAssertEqual(StepTimer.format(3_909), "1:05:09")
        XCTAssertEqual(StepTimer.format(-5), "0:00")
    }
}
