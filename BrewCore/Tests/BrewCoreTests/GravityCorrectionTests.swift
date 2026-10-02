import XCTest
@testable import BrewCore

final class GravityCorrectionTests: XCTestCase {
    func testExtractConversion() {
        // 1 lb of 44 PPG extract in 1 gal is 44 points.
        let pointLiters = GravityCorrection.pointLitersPerKg(ppg: 44) * BrewMath.lbToKg(1)
        XCTAssertEqual(pointLiters / BrewMath.gallonsToLiters(1), 44, accuracy: 0.001)
    }

    func testLowPreBoilGravity() {
        // 28 L at 1.040 with 4 L still to boil off ends at 24 L and 1.0467; target 1.050.
        let r = GravityCorrection.plan(measuredSG: 1.040, volumeL: 28, boilOffL: 4, targetSG: 1.050,
                                       boilOffLPerHour: 4)
        XCTAssertEqual(r.projectedVolumeL, 24, accuracy: 0.0001)
        XCTAssertEqual(r.projectedSG, 1.046_67, accuracy: 0.0001)
        XCTAssertTrue(r.isLow)
        // 80 point-liters missing ÷ 367.2 per kg ≈ 218 g of DME.
        XCTAssertEqual(try XCTUnwrap(r.dryMaltExtractGrams), 217.9, accuracy: 0.5)
        // Or boil 1.6 L more (24 → 22.4 L) at 4 L/hr: 24 minutes.
        XCTAssertEqual(try XCTUnwrap(r.extraBoilMinutes), 24, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(r.volumeAfterExtraBoilL), 22.4, accuracy: 0.0001)
        XCTAssertNil(r.waterToAddL)
    }

    func testHighGravityAfterBoil() {
        // 20 L at 1.060 diluted to 1.050 needs 24 L: add 4 L of water.
        let r = GravityCorrection.plan(measuredSG: 1.060, volumeL: 20, targetSG: 1.050)
        XCTAssertTrue(r.isHigh)
        XCTAssertEqual(try XCTUnwrap(r.waterToAddL), 4, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(r.volumeAfterWaterL), 24, accuracy: 0.0001)
        XCTAssertNil(r.dryMaltExtractGrams)
        XCTAssertNil(r.extraBoilMinutes)
    }

    func testOnTargetNeedsNothing() {
        let r = GravityCorrection.plan(measuredSG: 1.0505, volumeL: 20, targetSG: 1.050)
        XCTAssertTrue(r.isOnTarget)
        XCTAssertNil(r.waterToAddL)
        XCTAssertNil(r.dryMaltExtractGrams)
    }

    func testNoBoilOffRateSkipsExtraBoil() {
        let r = GravityCorrection.plan(measuredSG: 1.045, volumeL: 20, targetSG: 1.050)
        XCTAssertNotNil(r.dryMaltExtractGrams)
        XCTAssertNil(r.extraBoilMinutes)
    }

    func testPreBoilFromSessionPlanHitsPlannedOG() {
        let recipe = SampleRecipes.paleAle
        let plan = BrewSession.Plan(recipe: recipe)
        // Measuring exactly the planned pre-boil numbers should land on the planned OG.
        let r = GravityCorrection.preBoil(measuredSG: plan.preBoilGravity, volumeL: plan.preBoilVolumeL, plan: plan)
        XCTAssertEqual(r.projectedSG, plan.og, accuracy: 0.002)
        XCTAssertEqual(r.projectedVolumeL, plan.postBoilVolumeL, accuracy: 0.0001)
    }
}
