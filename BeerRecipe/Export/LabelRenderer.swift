import UIKit
import BrewCore

/// Draws bottle labels: a beer-colored band on the left, then name, style, stats, date and tagline.
enum LabelRenderer {
    static func draw(_ label: BottleLabel, in rect: CGRect) {
        let inset = rect.insetBy(dx: rect.width * 0.03, dy: rect.height * 0.06)
        let band = CGRect(x: inset.minX, y: inset.minY, width: inset.width * 0.12, height: inset.height)
        let bandPath = UIBezierPath(roundedRect: band, cornerRadius: band.width * 0.25)
        UIColor(hex: label.colorHex).setFill()
        bandPath.fill()
        UIColor.black.withAlphaComponent(0.2).setStroke()
        bandPath.lineWidth = 0.5
        bandPath.stroke()

        let textRect = CGRect(x: band.maxX + inset.width * 0.05, y: inset.minY,
                              width: inset.maxX - band.maxX - inset.width * 0.05, height: inset.height)
        let scale = rect.height / 144  // relative to a 2-inch-tall label

        var lines: [(String, UIFont, UIColor)] = [
            (label.title, .systemFont(ofSize: 22 * scale, weight: .heavy), .black)
        ]
        if !label.subtitle.isEmpty { lines.append((label.subtitle, .systemFont(ofSize: 11 * scale, weight: .medium), .darkGray)) }
        if !label.statsLine.isEmpty { lines.append((label.statsLine, .monospacedDigitSystemFont(ofSize: 11 * scale, weight: .semibold), .black)) }
        if !label.dateLine.isEmpty { lines.append((label.dateLine, .systemFont(ofSize: 9 * scale), .darkGray)) }
        if !label.tagline.isEmpty { lines.append((label.tagline, .italicSystemFont(ofSize: 10 * scale), .darkGray)) }

        // Measure, then center the block vertically.
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        let measured = lines.map { line -> (NSAttributedString, CGFloat) in
            let (text, font, color) = line
            let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
            let height = ceil(string.boundingRect(with: CGSize(width: textRect.width, height: .greatestFiniteMagnitude),
                                                  options: [.usesLineFragmentOrigin], context: nil).height)
            return (string, min(height, font.lineHeight * 2.2))
        }
        let spacing = 4 * scale
        let total = measured.reduce(0) { $0 + $1.1 } + spacing * CGFloat(max(0, measured.count - 1))
        var y = textRect.minY + max(0, (textRect.height - total) / 2)
        for (string, height) in measured {
            string.draw(with: CGRect(x: textRect.minX, y: y, width: textRect.width, height: height),
                        options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            y += height + spacing
        }
    }

    /// A US Letter PDF with `count` copies laid out on `sheet`.
    static func pdf(_ label: BottleLabel, sheet: LabelSheet, count: Int, cutGuides: Bool) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "\(label.title) labels"]
        return UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { context in
            for index in 0..<max(1, count) {
                if index % sheet.perSheet == 0 { context.beginPage() }
                let f = sheet.frame(at: index)
                let rect = CGRect(x: f.x, y: f.y, width: f.width, height: f.height)
                if cutGuides {
                    let guide = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 9)
                    guide.setLineDash([3, 3], count: 2, phase: 0)
                    guide.lineWidth = 0.5
                    UIColor.lightGray.setStroke()
                    guide.stroke()
                }
                draw(label, in: rect)
            }
        }
    }

    /// A preview image of one label.
    static func image(_ label: BottleLabel, sheet: LabelSheet, scale: CGFloat = 1) -> UIImage {
        let size = CGSize(width: sheet.labelWidth * 72, height: sheet.labelHeight * 72)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            draw(label, in: CGRect(origin: .zero, size: size))
        }
    }
}
