import UIKit
import BrewCore

/// Lays out a `RecipeReport` on US Letter pages with UIKit's PDF renderer.
enum PDFRenderer {
    private static let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let margin: CGFloat = 48
    private static var contentWidth: CGFloat { pageRect.width - margin * 2 }

    private static let brown = UIColor(red: 0.54, green: 0.35, blue: 0.12, alpha: 1)
    private static let gold = UIColor(red: 0.78, green: 0.59, blue: 0.24, alpha: 1)
    private static let headerFill = UIColor(red: 0.95, green: 0.89, blue: 0.77, alpha: 1)

    static func render(_ report: RecipeReport) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: report.title,
            kCGPDFContextCreator as String: "Brew Recipe Builder"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        return renderer.pdfData { context in
            var layout = Layout(context: context)
            layout.newPage()
            layout.drawHeader(report)
            for block in report.blocks {
                switch block {
                case .heading(let text): layout.drawHeading(text)
                case .paragraph(let text): layout.drawParagraph(text)
                case .fields(let fields): layout.drawFields(fields)
                case .table(let table): layout.drawTable(table)
                }
            }
        }
    }

    private struct Layout {
        let context: UIGraphicsPDFRendererContext
        var y: CGFloat = 0
        var page = 0

        init(context: UIGraphicsPDFRendererContext) { self.context = context }

        // MARK: Text helpers

        func attributes(_ font: UIFont, _ color: UIColor = .black, alignment: NSTextAlignment = .left) -> [NSAttributedString.Key: Any] {
            let style = NSMutableParagraphStyle()
            style.alignment = alignment
            style.lineBreakMode = .byWordWrapping
            return [.font: font, .foregroundColor: color, .paragraphStyle: style]
        }

        func height(of text: String, width: CGFloat, attrs: [NSAttributedString.Key: Any]) -> CGFloat {
            ceil((text as NSString).boundingRect(with: CGSize(width: width, height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                 attributes: attrs, context: nil).height)
        }

        @discardableResult
        func draw(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, attrs: [NSAttributedString.Key: Any]) -> CGFloat {
            let h = height(of: text, width: width, attrs: attrs)
            (text as NSString).draw(with: CGRect(x: x, y: y, width: width, height: h),
                                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                                    attributes: attrs, context: nil)
            return h
        }

        // MARK: Pagination

        mutating func newPage() {
            context.beginPage()
            page += 1
            y = margin
            let footer = "Brew Recipe Builder · Page \(page)"
            draw(footer, x: margin, y: pageRect.height - margin + 16, width: contentWidth,
                 attrs: attributes(.systemFont(ofSize: 8), .gray, alignment: .center))
        }

        mutating func ensureSpace(_ needed: CGFloat) {
            if y + needed > pageRect.height - margin { newPage() }
        }

        // MARK: Blocks

        mutating func drawHeader(_ report: RecipeReport) {
            let swatchSize: CGFloat = 44
            let textX = margin + swatchSize + 14
            let textWidth = contentWidth - swatchSize - 14

            let swatch = UIBezierPath(roundedRect: CGRect(x: margin, y: y, width: swatchSize * 0.8, height: swatchSize),
                                      cornerRadius: 8)
            UIColor(hex: report.colorHex).setFill()
            swatch.fill()
            UIColor.black.withAlphaComponent(0.15).setStroke()
            swatch.stroke()

            let titleHeight = draw(report.title, x: textX, y: y, width: textWidth,
                                   attrs: attributes(.boldSystemFont(ofSize: 24), brown))
            var subtitleHeight: CGFloat = 0
            if !report.subtitle.isEmpty {
                subtitleHeight = draw(report.subtitle, x: textX, y: y + titleHeight + 2, width: textWidth,
                                      attrs: attributes(.systemFont(ofSize: 12), .darkGray))
            }
            y += max(swatchSize, titleHeight + subtitleHeight + 2) + 10
        }

        mutating func drawHeading(_ text: String) {
            let attrs = attributes(.boldSystemFont(ofSize: 14), brown)
            let h = height(of: text, width: contentWidth, attrs: attrs)
            ensureSpace(h + 60)  // keep headings with their content
            y += 10
            draw(text, x: margin, y: y, width: contentWidth, attrs: attrs)
            y += h + 3
            let line = UIBezierPath()
            line.move(to: CGPoint(x: margin, y: y))
            line.addLine(to: CGPoint(x: margin + contentWidth, y: y))
            line.lineWidth = 1
            gold.setStroke()
            line.stroke()
            y += 6
        }

        mutating func drawParagraph(_ text: String) {
            let attrs = attributes(.systemFont(ofSize: 10.5))
            let h = height(of: text, width: contentWidth, attrs: attrs)
            ensureSpace(h)
            draw(text, x: margin, y: y, width: contentWidth, attrs: attrs)
            y += h + 4
        }

        mutating func drawFields(_ fields: [RecipeReport.Field]) {
            let labelWidth = contentWidth * 0.36
            let labelAttrs = attributes(.boldSystemFont(ofSize: 10.5), .darkGray)
            let valueAttrs = attributes(.systemFont(ofSize: 10.5))
            // Two columns of label/value pairs when there's room.
            let columns = fields.count > 4 ? 2 : 1
            let columnWidth = (contentWidth - CGFloat(columns - 1) * 16) / CGFloat(columns)
            let rows = Int(ceil(Double(fields.count) / Double(columns)))
            for r in 0..<rows {
                var rowHeight: CGFloat = 0
                let items = (0..<columns).compactMap { c -> (Int, RecipeReport.Field)? in
                    let index = c * rows + r
                    return index < fields.count ? (c, fields[index]) : nil
                }
                let lw = columns == 1 ? labelWidth : columnWidth * 0.5
                for (_, field) in items {
                    rowHeight = max(rowHeight,
                                    height(of: field.label, width: lw, attrs: labelAttrs),
                                    height(of: field.value, width: columnWidth - lw, attrs: valueAttrs))
                }
                ensureSpace(rowHeight + 3)
                for (c, field) in items {
                    let x = margin + CGFloat(c) * (columnWidth + 16)
                    draw(field.label, x: x, y: y, width: lw, attrs: labelAttrs)
                    draw(field.value, x: x + lw, y: y, width: columnWidth - lw, attrs: valueAttrs)
                }
                y += rowHeight + 3
            }
            y += 4
        }

        mutating func drawTable(_ table: RecipeReport.Table) {
            let total = table.widths.reduce(0, +)
            let widths = table.widths.map { CGFloat($0 / max(total, 1)) * contentWidth }
            let padding: CGFloat = 4
            let headerAttrs = attributes(.boldSystemFont(ofSize: 9.5))
            let cellAttrs = attributes(.systemFont(ofSize: 9.5))

            func rowHeight(_ cells: [String], _ attrs: [NSAttributedString.Key: Any]) -> CGFloat {
                zip(cells, widths).map { height(of: $0, width: $1 - padding * 2, attrs: attrs) }.max() ?? 12
            }

            func drawRow(_ cells: [String], attrs: [NSAttributedString.Key: Any], fill: UIColor?) {
                let h = rowHeight(cells, attrs) + padding * 2
                if let fill {
                    fill.setFill()
                    UIRectFill(CGRect(x: margin, y: y, width: contentWidth, height: h))
                }
                var x = margin
                for (text, w) in zip(cells, widths) {
                    draw(text, x: x + padding, y: y + padding, width: w - padding * 2, attrs: attrs)
                    x += w
                }
                y += h
                let line = UIBezierPath()
                line.move(to: CGPoint(x: margin, y: y))
                line.addLine(to: CGPoint(x: margin + contentWidth, y: y))
                line.lineWidth = 0.5
                UIColor(white: 0.8, alpha: 1).setStroke()
                line.stroke()
            }

            ensureSpace(rowHeight(table.headers, headerAttrs) + rowHeight(table.rows.first ?? [], cellAttrs) + padding * 4)
            drawRow(table.headers, attrs: headerAttrs, fill: headerFill)
            for row in table.rows {
                let needed = rowHeight(row, cellAttrs) + padding * 2
                if y + needed > pageRect.height - margin {
                    newPage()
                    drawRow(table.headers, attrs: headerAttrs, fill: headerFill)
                }
                drawRow(row, attrs: cellAttrs, fill: nil)
            }
            y += 8
        }
    }
}

extension UIColor {
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }
}
