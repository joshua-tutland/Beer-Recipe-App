import XCTest
@testable import BrewCore

final class CatalogTests: XCTestCase {
    func testCatalogsLoad() {
        XCTAssertGreaterThan(IngredientCatalog.fermentables.count, 50)
        XCTAssertGreaterThan(IngredientCatalog.hops.count, 50)
        XCTAssertGreaterThan(IngredientCatalog.yeasts.count, 30)
        XCTAssertGreaterThan(IngredientCatalog.miscs.count, 10)
        XCTAssertGreaterThan(StyleCatalog.all.count, 50)
    }

    func testCatalogIdsAreUnique() {
        XCTAssertEqual(Set(IngredientCatalog.fermentables.map(\.id)).count, IngredientCatalog.fermentables.count)
        XCTAssertEqual(Set(IngredientCatalog.hops.map(\.id)).count, IngredientCatalog.hops.count)
        XCTAssertEqual(Set(IngredientCatalog.yeasts.map(\.id)).count, IngredientCatalog.yeasts.count)
        XCTAssertEqual(Set(StyleCatalog.all.map(\.id)).count, StyleCatalog.all.count)
    }

    func testSampleRecipesFitTheirStyles() throws {
        for recipe in SampleRecipes.all {
            XCTAssertFalse(recipe.fermentables.isEmpty, recipe.name)
            XCTAssertFalse(recipe.yeasts.isEmpty, recipe.name)
            let style = try XCTUnwrap(recipe.style, recipe.name)
            for row in style.compare(recipe.stats) {
                XCTAssertEqual(row.fit, .inRange,
                               "\(recipe.name) \(row.label) \(row.formatted(row.value)) outside \(row.min)–\(row.max)")
            }
        }
    }
}

final class PersistenceTests: XCTestCase {
    func testRepositoryRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repo = RecipeRepository(directory: dir)

        let recipe = SampleRecipes.paleAle
        try repo.save(recipe)
        let loaded = repo.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, recipe.name)
        XCTAssertEqual(loaded.first?.hops.count, recipe.hops.count)
        XCTAssertEqual(loaded.first?.stats.og ?? 0, recipe.stats.og, accuracy: 0.00001)

        try repo.delete(id: recipe.id)
        XCTAssertTrue(repo.loadAll().isEmpty)
    }
}

final class ExportTests: XCTestCase {
    func testBeerXMLRoundTrip() throws {
        let original = SampleRecipes.paleAle
        let xml = BeerXML.export([original])
        XCTAssertTrue(xml.contains("<RECIPES>"))
        let imported = try BeerXML.importRecipes(from: Data(xml.utf8))
        let recipe = try XCTUnwrap(imported.first)

        XCTAssertEqual(recipe.name, original.name)
        XCTAssertEqual(recipe.styleId, original.styleId)
        XCTAssertEqual(recipe.fermentables.count, original.fermentables.count)
        XCTAssertEqual(recipe.hops.count, original.hops.count)
        XCTAssertEqual(recipe.hops.last?.use, .dryHop)
        XCTAssertEqual(recipe.hops.last?.time, 4)
        XCTAssertEqual(recipe.stats.og, original.stats.og, accuracy: 0.001)
        XCTAssertEqual(recipe.stats.ibu, original.stats.ibu, accuracy: 0.5)
        XCTAssertEqual(recipe.stats.srm, original.stats.srm, accuracy: 0.2)
    }

    func testBeerXMLRejectsGarbage() {
        XCTAssertThrowsError(try BeerXML.importRecipes(from: Data("not xml".utf8)))
        XCTAssertThrowsError(try BeerXML.importRecipes(from: Data("<HOPS></HOPS>".utf8)))
    }

    func testDocxIsAZipWithDocument() throws {
        var recipe = SampleRecipes.hazyIPA
        recipe.notes = "Fish & chips <pairing> \"test\""
        let data = DocxWriter.data(for: recipe, units: .metric)

        XCTAssertEqual(Array(data.prefix(4)), [0x50, 0x4B, 0x03, 0x04])  // "PK\u{3}\u{4}"
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("word/document.xml"))
        XCTAssertTrue(text.contains("Juicy Hazy IPA"))
        XCTAssertTrue(text.contains("Fish &amp; chips &lt;pairing&gt;"))

        // CI sets EXPORT_DIR to validate the file with an independent .docx reader.
        if let dir = ProcessInfo.processInfo.environment["EXPORT_DIR"] {
            try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("sample.docx"))
        }
    }

    func testCRC32() {
        XCTAssertEqual(CRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testReportIncludesAllSections() {
        let report = RecipeReport(recipe: SampleRecipes.paleAle, units: .imperial)
        let headings = report.blocks.compactMap { block -> String? in
            if case .heading(let h) = block { return h }
            return nil
        }
        XCTAssertTrue(headings.contains("Vital Statistics"))
        XCTAssertTrue(headings.contains("Fermentables"))
        XCTAssertTrue(headings.contains("Hops"))
        XCTAssertTrue(headings.contains("Yeast"))
        XCTAssertTrue(headings.contains { $0.hasPrefix("Style:") })
    }
}
