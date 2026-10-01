import XCTest
@testable import BrewCore

final class BottleLabelTests: XCTestCase {
    func testEstimatedWithoutMeasurements() {
        let recipe = SampleRecipes.paleAle
        let label = BottleLabel.make(recipe: recipe, session: nil, tagline: " Brewed with love ")
        XCTAssertEqual(label.title, "Cascade Pale Ale")
        XCTAssertEqual(label.subtitle, "American Pale Ale")
        XCTAssertTrue(label.statsLine.hasPrefix(String(format: "%.1f%% ABV (est.)", recipe.stats.abv)), label.statsLine)
        XCTAssertTrue(label.statsLine.contains("IBU"))
        XCTAssertEqual(label.dateLine, "")
        XCTAssertEqual(label.tagline, "Brewed with love")
        XCTAssertEqual(label.colorHex, recipe.stats.colorHex)
    }

    func testMeasuredABVAndDates() {
        let recipe = SampleRecipes.paleAle
        var session = BrewSession(recipe: recipe, brewDate: Date(timeIntervalSince1970: 1_700_000_000))
        session.og = 1.052
        session.fg = 1.010
        session.packagedDate = Date(timeIntervalSince1970: 1_701_500_000)
        var options = BottleLabel.Options()
        options.showIBU = false
        options.showColor = true
        let label = BottleLabel.make(recipe: recipe, session: session, title: "Batch #7", options: options)
        XCTAssertEqual(label.title, "Batch #7")
        XCTAssertTrue(label.statsLine.hasPrefix("5.5% ABV ·"), label.statsLine)
        XCTAssertFalse(label.statsLine.contains("IBU"))
        XCTAssertTrue(label.statsLine.contains("SRM"))
        XCTAssertTrue(label.dateLine.hasPrefix("Brewed "))
        XCTAssertTrue(label.dateLine.contains("Bottled"))
    }

    func testSheetGeometryFitsLetterPaper() {
        for sheet in LabelSheet.allCases {
            let last = sheet.frame(at: sheet.perSheet - 1)
            XCTAssertLessThanOrEqual(last.x + last.width, 8.5 * 72 + 0.01, sheet.rawValue)
            XCTAssertLessThanOrEqual(last.y + last.height, 11 * 72 + 0.01, sheet.rawValue)
            XCTAssertEqual(sheet.frame(at: 0).x, 0.15625 * 72, accuracy: 0.001)
        }
        XCTAssertEqual(LabelSheet.avery5163.perSheet, 10)
        XCTAssertEqual(LabelSheet.avery5164.perSheet, 6)
        // Index wraps onto the next page at the same position.
        XCTAssertEqual(LabelSheet.avery5163.frame(at: 10).y, LabelSheet.avery5163.frame(at: 0).y)
    }
}
