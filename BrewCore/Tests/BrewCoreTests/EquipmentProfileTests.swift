import XCTest
@testable import BrewCore

final class EquipmentProfileTests: XCTestCase {
    private func singleMalt(_ equipment: Equipment) -> Recipe {
        let malt = Fermentable(id: "m", name: "Malt", type: .grain, colorLovibond: 2, potentialPPG: 37)
        return Recipe(equipment: equipment, fermentables: [FermentableAddition(fermentable: malt, amountKg: 5)])
    }

    func testFullVolumeMashPutsAllWaterInTheMash() {
        let biab = Equipment(trubLossL: 1.5, mashTunDeadspaceL: 0, grainAbsorptionLPerKg: 0.6, mashMethod: .fullVolume)
        let stats = singleMalt(biab).stats
        XCTAssertEqual(stats.preBoilVolumeL, 25, accuracy: 0.001)
        XCTAssertEqual(stats.totalWaterL, 28, accuracy: 0.001)       // 25 + 5 kg × 0.6
        XCTAssertEqual(stats.strikeWaterL, 28, accuracy: 0.001)
        XCTAssertEqual(stats.spargeWaterL, 0)
        // Thinner mash → lower strike temperature than a 3 L/kg mash (72.3 °C).
        XCTAssertEqual(stats.strikeTempC, 69.37, accuracy: 0.05)

        let steps = BrewDayPlan.steps(for: singleMalt(biab), units: .metric)
        XCTAssertTrue(steps.first { $0.id == "mash-strike" }?.title.contains("full volume") ?? false)
        XCTAssertEqual(steps.first { $0.id == "sparge" }?.title, "Lift the bag and let it drain")
    }

    func testSpargeMethodUnchanged() {
        let stats = singleMalt(Equipment()).stats
        XCTAssertEqual(stats.strikeWaterL, 15, accuracy: 0.001)
        XCTAssertEqual(stats.strikeTempC, 72.29, accuracy: 0.05)
        XCTAssertEqual(stats.spargeWaterL, 15.5, accuracy: 0.01)
    }

    func testOldEquipmentStillDecodes() throws {
        let old = #"{"batchSizeL": 19, "boilTimeMinutes": 90, "efficiency": 65}"#
        let equipment = try JSONDecoder().decode(Equipment.self, from: Data(old.utf8))
        XCTAssertEqual(equipment.batchSizeL, 19)
        XCTAssertEqual(equipment.boilTimeMinutes, 90)
        XCTAssertEqual(equipment.mashMethod, .sparge)
        XCTAssertEqual(equipment.trubLossL, Equipment().trubLossL)
    }

    func testPresets() {
        XCTAssertGreaterThanOrEqual(EquipmentProfile.presets.count, 5)
        XCTAssertTrue(EquipmentProfile.presets.contains { $0.equipment.mashMethod == .fullVolume })
        XCTAssertEqual(Set(EquipmentProfile.presets.map(\.name)).count, EquipmentProfile.presets.count)
        let profile = EquipmentProfile.presets[1]
        let decoded = try? JSONDecoder().decode(EquipmentProfile.self, from: JSONEncoder().encode(profile))
        XCTAssertEqual(decoded, profile)
    }
}
