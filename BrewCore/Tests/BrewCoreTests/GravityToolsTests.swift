import XCTest
@testable import BrewCore

final class GravityToolsTests: XCTestCase {
    func testHydrometerTemperatureCorrection() {
        // 1.050 read at 90 °F on a 60 °F hydrometer.
        let corrected = GravityTools.hydrometerCorrected(reading: 1.050,
                                                         sampleTempC: BrewMath.fToC(90),
                                                         calibrationTempC: BrewMath.fToC(60))
        XCTAssertEqual(corrected, 1.0541, accuracy: 0.0002)

        // No correction at the calibration temperature.
        XCTAssertEqual(GravityTools.hydrometerCorrected(reading: 1.040, sampleTempC: 20, calibrationTempC: 20),
                       1.040, accuracy: 0.00001)

        // Cold samples read slightly high, so the correction lowers them.
        XCTAssertLessThan(GravityTools.hydrometerCorrected(reading: 1.040, sampleTempC: 8, calibrationTempC: 20), 1.040)
    }

    func testRefractometerUnfermentedWort() {
        XCTAssertEqual(GravityTools.refractometerSG(brix: 13, wortCorrectionFactor: 1.04), 1.0505, accuracy: 0.0002)
        XCTAssertEqual(GravityTools.refractometerSG(brix: 13, wortCorrectionFactor: 1.0), 1.0527, accuracy: 0.0003)
        XCTAssertEqual(GravityTools.expectedBrix(sg: 1.050), 12.88, accuracy: 0.02)
    }

    func testRefractometerDuringFermentation() {
        XCTAssertEqual(GravityTools.refractometerFermentingSG(originalBrix: 13, currentBrix: 6.5), 1.0120, accuracy: 0.0002)
        XCTAssertEqual(GravityTools.refractometerFermentingSG(originalBrix: 12, currentBrix: 6), 1.0114, accuracy: 0.0002)
        // The naive conversion of the fermented reading would be badly wrong.
        XCTAssertGreaterThan(GravityTools.refractometerSG(brix: 6.5), 1.020)
    }

    func testWortCorrectionFactorCalibration() {
        XCTAssertEqual(GravityTools.wortCorrectionFactor(brix: 13, hydrometerSG: 1.050) ?? 0, 1.049, accuracy: 0.002)
        XCTAssertNil(GravityTools.wortCorrectionFactor(brix: 5, hydrometerSG: 1.000))
    }
}
