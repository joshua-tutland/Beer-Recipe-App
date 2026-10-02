import XCTest
@testable import BrewCore

final class WaterReportParserTests: XCTestCase {
    func testUSUtilityReport() {
        let text = """
        2025 Annual Water Quality Report
        Parameter            Average   Range      Units
        Calcium (Ca)         38        30 - 45    mg/L
        Magnesium (Mg)       9.5       7 - 12     mg/L
        Sodium               14        10 - 18    mg/L
        Chloride (Cl-)       21        15 - 30    mg/L
        Sulfate (SO4 2-)     35        28 - 41    mg/L
        Total Alkalinity (as CaCO3)  110  95 - 120  mg/L
        Total Hardness (as CaCO3)    135            mg/L
        pH                   7.8
        """
        let r = WaterReportParser.parse(text)
        XCTAssertEqual(r.ions[.calcium], 38)
        XCTAssertEqual(r.ions[.magnesium], 9.5)
        XCTAssertEqual(r.ions[.sodium], 14)
        XCTAssertEqual(r.ions[.chloride], 21)
        XCTAssertEqual(r.ions[.sulfate], 35)
        XCTAssertEqual(try XCTUnwrap(r.ions[.bicarbonate]), 110 * 61.02 / 50.04, accuracy: 0.01)
        XCTAssertTrue(r.bicarbonateFromAlkalinity)
        XCTAssertEqual(r.pH, 7.8)
        XCTAssertTrue(r.rangedIons.isEmpty, "The average column comes first, so no midpoints were used")
    }

    func testSymbolsTablesAndRanges() {
        let text = """
        Ca: 52 ppm
        Mg 8 ppm
        Na 10-14 ppm
        Cl
        18
        SO4: 60 ppm
        HCO3: 180 ppm
        """
        let r = WaterReportParser.parse(text)
        XCTAssertEqual(r.ions[.calcium], 52)
        XCTAssertEqual(r.ions[.magnesium], 8)
        XCTAssertEqual(r.ions[.sodium], 12)
        XCTAssertEqual(r.rangedIons, [.sodium])
        XCTAssertEqual(r.ions[.chloride], 18, "Value on the next line, as OCR often splits table rows")
        XCTAssertEqual(r.ions[.sulfate], 60)
        XCTAssertEqual(r.ions[.bicarbonate], 180)
        XCTAssertFalse(r.bicarbonateFromAlkalinity)
    }

    func testEuropeanReportUnits() {
        let text = """
        Calcium 1,25 mmol/l
        Magnesium 0,4 mmol/l
        Natrium / Sodium 9,8 mg/l
        Chlorid / Chloride 15 mg/l
        Sulfat / Sulphate 42 mg/l
        Hydrogencarbonat / Hydrogencarbonate 244 mg/l
        """
        let r = WaterReportParser.parse(text)
        XCTAssertEqual(try XCTUnwrap(r.ions[.calcium]), 1.25 * 40.08, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(r.ions[.magnesium]), 0.4 * 24.305, accuracy: 0.01)
        XCTAssertEqual(r.ions[.sodium], 9.8)
        XCTAssertEqual(r.ions[.chloride], 15)
        XCTAssertEqual(r.ions[.sulfate], 42)
        XCTAssertEqual(r.ions[.bicarbonate], 244)
    }

    func testMicrogramsAndThings_thatLookLikeIons() {
        let text = """
        Free Chlorine 1.2 mg/L
        Sodium 12000 ug/L
        mg/L values below
        Calcium Hardness (as CaCO3) 90
        """
        let r = WaterReportParser.parse(text)
        XCTAssertNil(r.ions[.chloride], "Chlorine isn't chloride")
        XCTAssertEqual(r.ions[.sodium], 12)
        XCTAssertNil(r.ions[.magnesium], "A line starting with the unit mg/L isn't magnesium")
        XCTAssertNil(r.ions[.calcium], "Calcium hardness is reported as CaCO3, not calcium")
    }

    func testAppliedKeepsMissingValues() {
        let r = WaterReportParser.parse("Calcium 40\nSulfate 80")
        let base = WaterProfile(name: "Mine", calcium: 1, magnesium: 5, sulfate: 1)
        let w = r.applied(to: base)
        XCTAssertEqual(w.calcium, 40)
        XCTAssertEqual(w.sulfate, 80)
        XCTAssertEqual(w.magnesium, 5)
        XCTAssertTrue(WaterReportParser.parse("Nothing useful here").isEmpty)
    }
}
