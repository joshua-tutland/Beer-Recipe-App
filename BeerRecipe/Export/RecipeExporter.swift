import Foundation
import BrewCore

/// Writes recipe exports to Documents/Exports (visible in the Files app) and returns the file URL.
enum RecipeExporter {
    enum Format {
        case pdf, word, beerXML

        var fileExtension: String {
            switch self {
            case .pdf: return "pdf"
            case .word: return "docx"
            case .beerXML: return "xml"
            }
        }
    }

    static var exportDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exports", isDirectory: true)
    }

    static func file(for recipe: Recipe, format: Format, units: UnitSystem) throws -> URL {
        let data: Data
        switch format {
        case .pdf:
            data = PDFRenderer.render(RecipeReport(recipe: recipe, units: units))
        case .word:
            data = DocxWriter.data(for: recipe, units: units)
        case .beerXML:
            data = Data(BeerXML.export([recipe]).utf8)
        }
        return try write(data, name: recipe.name, ext: format.fileExtension)
    }

    static func beerXMLFile(for recipes: [Recipe], name: String) throws -> URL {
        try write(Data(BeerXML.export(recipes).utf8), name: name, ext: "xml")
    }

    private static func write(_ data: Data, name: String, ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        let url = exportDirectory.appendingPathComponent(safeFileName(name)).appendingPathExtension(ext)
        try data.write(to: url, options: [.atomic])
        return url
    }

    static func safeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:").union(.newlines).union(.controlCharacters)
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Recipe" : String(cleaned.prefix(80))
    }
}
