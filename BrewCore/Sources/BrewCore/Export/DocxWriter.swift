import Foundation

/// Renders a `RecipeReport` as a Microsoft Word (.docx) document.
public enum DocxWriter {
    public static func data(for report: RecipeReport, date: Date = Date()) -> Data {
        var zip = ZipArchive(date: date)
        zip.addFile(path: "[Content_Types].xml", text: contentTypes)
        zip.addFile(path: "_rels/.rels", text: packageRels)
        zip.addFile(path: "docProps/core.xml", text: coreProperties(title: report.title, date: date))
        zip.addFile(path: "word/_rels/document.xml.rels", text: documentRels)
        zip.addFile(path: "word/styles.xml", text: styles)
        zip.addFile(path: "word/document.xml", text: document(for: report))
        return zip.data()
    }

    public static func data(for recipe: Recipe, units: UnitSystem) -> Data {
        data(for: RecipeReport(recipe: recipe, units: units))
    }

    // MARK: - Document body

    /// Usable page width in twentieths of a point (Letter, 0.75" margins).
    private static let contentWidth = 10_080

    static func document(for report: RecipeReport) -> String {
        var body = ""
        body += paragraph(report.title, style: "Title")
        if !report.subtitle.isEmpty {
            body += paragraph(report.subtitle, style: "Subtitle")
        }
        let color = report.colorHex.replacingOccurrences(of: "#", with: "")
        body += """
        <w:p><w:pPr><w:spacing w:after="120"/></w:pPr>\
        <w:r><w:rPr><w:color w:val="\(color)"/><w:sz w:val="32"/></w:rPr><w:t>■■■■■■</w:t></w:r>\
        <w:r><w:rPr><w:color w:val="666666"/></w:rPr><w:t xml:space="preserve">  Estimated color</w:t></w:r></w:p>
        """

        for block in report.blocks {
            switch block {
            case .heading(let text):
                body += paragraph(text, style: "Heading1")
            case .paragraph(let text):
                body += paragraph(text, style: nil)
            case .fields(let fields):
                body += fieldsTable(fields)
            case .table(let table):
                body += dataTable(table)
            }
        }

        body += paragraph("Created with Brew Recipe Builder", style: "Footer")

        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" \
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <w:body>\(body)<w:sectPr><w:pgSz w:w="12240" w:h="15840"/>\
        <w:pgMar w:top="1080" w:right="1080" w:bottom="1080" w:left="1080" w:header="720" w:footer="720" w:gutter="0"/>\
        </w:sectPr></w:body></w:document>
        """
    }

    private static func paragraph(_ text: String, style: String?, bold: Bool = false) -> String {
        let pPr = style.map { "<w:pPr><w:pStyle w:val=\"\($0)\"/></w:pPr>" } ?? ""
        return "<w:p>\(pPr)\(run(text, bold: bold))</w:p>"
    }

    private static func run(_ text: String, bold: Bool = false, color: String? = nil) -> String {
        var props = ""
        if bold { props += "<w:b/>" }
        if let color { props += "<w:color w:val=\"\(color)\"/>" }
        let rPr = props.isEmpty ? "" : "<w:rPr>\(props)</w:rPr>"
        return "<w:r>\(rPr)<w:t xml:space=\"preserve\">\(escape(text))</w:t></w:r>"
    }

    private static func cell(_ content: String, width: Int, shade: String? = nil, bold: Bool = false) -> String {
        let shading = shade.map { "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\($0)\"/>" } ?? ""
        return "<w:tc><w:tcPr><w:tcW w:w=\"\(width)\" w:type=\"dxa\"/>\(shading)</w:tcPr>"
            + "<w:p><w:pPr><w:spacing w:before=\"40\" w:after=\"40\"/></w:pPr>\(run(content, bold: bold))</w:p></w:tc>"
    }

    private static func tableStart(widths: [Int], borders: Bool) -> String {
        let grid = widths.map { "<w:gridCol w:w=\"\($0)\"/>" }.joined()
        let border = borders
            ? "<w:tblBorders><w:top w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:bottom w:val=\"single\" w:sz=\"4\" w:color=\"BFBFBF\"/><w:insideH w:val=\"single\" w:sz=\"4\" w:color=\"D9D9D9\"/></w:tblBorders>"
            : "<w:tblBorders><w:top w:val=\"nil\"/><w:left w:val=\"nil\"/><w:bottom w:val=\"nil\"/><w:right w:val=\"nil\"/><w:insideH w:val=\"nil\"/><w:insideV w:val=\"nil\"/></w:tblBorders>"
        return "<w:tbl><w:tblPr><w:tblW w:w=\"\(widths.reduce(0, +))\" w:type=\"dxa\"/>\(border)"
            + "<w:tblLayout w:type=\"fixed\"/></w:tblPr><w:tblGrid>\(grid)</w:tblGrid>"
    }

    private static func fieldsTable(_ fields: [RecipeReport.Field]) -> String {
        let widths = [contentWidth * 4 / 10, contentWidth * 6 / 10]
        var xml = tableStart(widths: widths, borders: false)
        for field in fields {
            xml += "<w:tr>" + cell(field.label, width: widths[0], bold: true) + cell(field.value, width: widths[1]) + "</w:tr>"
        }
        return xml + "</w:tbl>" + spacer
    }

    private static func dataTable(_ table: RecipeReport.Table) -> String {
        let total = table.widths.reduce(0, +)
        let widths = table.widths.map { Int(Double(contentWidth) * $0 / max(total, 1)) }
        var xml = tableStart(widths: widths, borders: true)
        xml += "<w:tr><w:trPr><w:tblHeader/></w:trPr>"
        for (i, header) in table.headers.enumerated() {
            xml += cell(header, width: widths[i], shade: "F2E2C4", bold: true)
        }
        xml += "</w:tr>"
        for row in table.rows {
            xml += "<w:tr>"
            for (i, value) in row.enumerated() where i < widths.count {
                xml += cell(value, width: widths[i])
            }
            xml += "</w:tr>"
        }
        return xml + "</w:tbl>" + spacer
    }

    private static let spacer = "<w:p><w:pPr><w:spacing w:after=\"0\"/></w:pPr></w:p>"

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default:
                // XML 1.0 forbids most control characters.
                if scalar.value < 0x20 && scalar != "\t" && scalar != "\n" && scalar != "\r" { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    // MARK: - Package parts

    private static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>\
    <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>\
    <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>\
    </Types>
    """

    private static let packageRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>\
    </Relationships>
    """

    private static let documentRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
    </Relationships>
    """

    private static func coreProperties(title: String, date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: date)
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" \
        xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">\
        <dc:title>\(escape(title))</dc:title><dc:creator>Brew Recipe Builder</dc:creator>\
        <dcterms:created xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:created>\
        <dcterms:modified xsi:type="dcterms:W3CDTF">\(stamp)</dcterms:modified>\
        </cp:coreProperties>
        """
    }

    private static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">\
    <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:cs="Calibri"/>\
    <w:sz w:val="21"/><w:szCs w:val="21"/></w:rPr></w:rPrDefault>\
    <w:pPrDefault><w:pPr><w:spacing w:after="80" w:line="264" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>\
    <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>\
    <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/>\
    <w:pPr><w:spacing w:after="40"/></w:pPr><w:rPr><w:b/><w:color w:val="5B3A1A"/><w:sz w:val="48"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Subtitle"><w:name w:val="Subtitle"/><w:basedOn w:val="Normal"/>\
    <w:rPr><w:color w:val="7F7F7F"/><w:sz w:val="24"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>\
    <w:next w:val="Normal"/><w:pPr><w:keepNext/><w:spacing w:before="240" w:after="80"/>\
    <w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="C8963E"/></w:pBdr><w:outlineLvl w:val="0"/></w:pPr>\
    <w:rPr><w:b/><w:color w:val="8A5A1F"/><w:sz w:val="28"/></w:rPr></w:style>\
    <w:style w:type="paragraph" w:styleId="Footer"><w:name w:val="footer"/><w:basedOn w:val="Normal"/>\
    <w:pPr><w:spacing w:before="360"/><w:jc w:val="center"/></w:pPr><w:rPr><w:color w:val="A6A6A6"/><w:sz w:val="16"/></w:rPr></w:style>\
    </w:styles>
    """
}
