import Foundation

/// Reads brewing ions out of the text of a water quality report (typed, pasted or recognized
/// from a photo).
///
/// Reports vary a lot, so this looks for each ion's name (or its symbol at the start of a line)
/// and takes the first number after it, on the same line or the next. Units in µg/L, ppb or
/// mmol/L are converted to mg/L, and alkalinity reported as CaCO₃ is converted to bicarbonate.
public enum WaterReportParser {
    public struct Result: Hashable, Sendable {
        /// Values found, in mg/L (ppm).
        public var ions: [Ion: Double] = [:]
        /// Set when bicarbonate came from an alkalinity figure.
        public var bicarbonateFromAlkalinity = false
        public var pH: Double?
        /// Values given as a range ("40 – 60"), which use the midpoint.
        public var rangedIons: Set<Ion> = []

        public var isEmpty: Bool { ions.isEmpty }

        /// `base` with every value that was found replaced.
        public func applied(to base: WaterProfile) -> WaterProfile {
            var profile = base
            for (ion, value) in ions { profile[ion] = value }
            return profile
        }
    }

    private struct Pattern {
        var ion: Ion
        var names: [String]
        var symbols: [String]
        /// Lines containing any of these are something else (e.g. "calcium hardness").
        var excluding: [String] = []
        var molarMass: Double
    }

    private static let patterns: [Pattern] = [
        Pattern(ion: .calcium, names: ["calcium"], symbols: ["ca"],
                excluding: ["hardness", "alkalinity", "carbonate"], molarMass: 40.08),
        Pattern(ion: .magnesium, names: ["magnesium"], symbols: ["mg"], excluding: ["hardness"], molarMass: 24.305),
        Pattern(ion: .sodium, names: ["sodium"], symbols: ["na"], molarMass: 22.99),
        Pattern(ion: .chloride, names: ["chloride"], symbols: ["cl"], excluding: ["chlorine"], molarMass: 35.45),
        Pattern(ion: .sulfate, names: ["sulfate", "sulphate"], symbols: ["so4", "so₄"], molarMass: 96.06),
        Pattern(ion: .bicarbonate, names: ["bicarbonate", "hydrogen carbonate", "hydrogencarbonate"],
                symbols: ["hco3", "hco₃"], molarMass: 61.02),
    ]

    public static func parse(_ text: String) -> Result {
        let lines = text.lowercased()
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var result = Result()

        for pattern in patterns {
            let ion = pattern.ion
            for (index, line) in lines.enumerated() {
                guard let rest = remainder(of: line, after: pattern),
                      !pattern.excluding.contains(where: { line.contains($0) }) else { continue }
                let next = index + 1 < lines.count ? lines[index + 1] : nil
                guard let found = value(in: rest, orNextLine: next) else { continue }
                result.ions[ion] = convert(found.value, unitsIn: found.context, molarMass: pattern.molarMass)
                if found.isRange { result.rangedIons.insert(ion) }
                break
            }
        }

        // Alkalinity is usually reported as CaCO₃; 1 ppm as CaCO₃ = 1.22 ppm bicarbonate.
        if result.ions[.bicarbonate] == nil {
            for (index, line) in lines.enumerated() where line.contains("alkalinity") {
                let rest = String(line[line.range(of: "alkalinity")!.upperBound...])
                let next = index + 1 < lines.count ? lines[index + 1] : nil
                guard let found = value(in: rest, orNextLine: next) else { continue }
                let mgL = convert(found.value, unitsIn: found.context, molarMass: 100.09 / 2)
                let asBicarbonate = line.contains("hco3") || line.contains("bicarbonate")
                result.ions[.bicarbonate] = asBicarbonate ? mgL : mgL * 61.02 / 50.04
                result.bicarbonateFromAlkalinity = !asBicarbonate
                if found.isRange { result.rangedIons.insert(.bicarbonate) }
                break
            }
        }

        for (index, line) in lines.enumerated() {
            guard let range = line.range(of: #"\bph\b"#, options: .regularExpression) else { continue }
            let next = index + 1 < lines.count ? lines[index + 1] : nil
            if let found = value(in: String(line[range.upperBound...]), orNextLine: next),
               (4...11).contains(found.value) {
                result.pH = found.value
                break
            }
        }
        return result
    }

    // MARK: - Matching

    /// The text after the ion's name or symbol, if the line mentions it.
    private static func remainder(of line: String, after pattern: Pattern) -> String? {
        for name in pattern.names {
            if let range = line.range(of: name) { return String(line[range.upperBound...]) }
        }
        // Symbols only count at the start of a line ("Ca 45", "Na: 12"), since "mg" and "ca" turn
        // up inside units and other words.
        for symbol in pattern.symbols {
            let regex = "^" + NSRegularExpression.escapedPattern(for: symbol) + #"(?![a-z0-9])"#
            if let range = line.range(of: regex, options: .regularExpression) {
                let rest = String(line[range.upperBound...])
                // "mg/L" at the start of a line is a unit, not magnesium.
                if symbol == "mg", rest.hasPrefix("/") { continue }
                return rest
            }
        }
        return nil
    }

    private struct Found {
        var value: Double
        var isRange: Bool
        /// The text the number was found in, to read its units.
        var context: String
    }

    private static func value(in rest: String, orNextLine next: String?) -> Found? {
        if let found = firstNumber(in: rest) { return found }
        // Tables recognized from photos often put the value on the following line.
        if let next, let found = firstNumber(in: next), next.first.map({ $0.isNumber || $0 == "<" }) == true {
            return found
        }
        return nil
    }

    private static func firstNumber(in text: String) -> Found? {
        // Drop chemical formulas and charges so their digits aren't read as values:
        // "(SO4 2-)", "as CaCO3", "HCO3-".
        var cleaned = text.replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(caco3|caco₃|hco3|hco₃|so4|so₄|co3|co₃)[-+]*"#, with: " ",
                                               options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\b\d[+-](?!\d)"#, with: " ", options: .regularExpression)
        // European decimal commas: "12,5" → "12.5" (but leave thousands like "1,200" alone).
        cleaned = cleaned.replacingOccurrences(of: #"(\d),(\d{1,2})(?!\d)"#, with: "$1.$2", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"(\d),(\d{3})"#, with: "$1$2", options: .regularExpression)

        let number = #"(\d+(?:\.\d+)?)"#
        let regex = try? NSRegularExpression(pattern: number + #"(?:\s*(?:-|–|to)\s*"# + number + ")?")
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        guard let match = regex?.firstMatch(in: cleaned, range: range),
              let first = Range(match.range(at: 1), in: cleaned),
              let low = Double(cleaned[first]) else { return nil }
        let context = String(cleaned[first.lowerBound...])
        if let second = Range(match.range(at: 2), in: cleaned), let high = Double(cleaned[second]), high >= low {
            return Found(value: (low + high) / 2, isRange: true, context: context)
        }
        return Found(value: low, isRange: false, context: context)
    }

    /// Converts a value to mg/L from the units written after it.
    private static func convert(_ value: Double, unitsIn context: String, molarMass: Double) -> Double {
        let units = context.prefix(24)
        if units.contains("µg") || units.contains("μg") || units.contains("ug/") || units.contains("ppb") {
            return value / 1000
        }
        if units.contains("mmol") { return value * molarMass }
        if units.contains("meq") || units.contains("mval") {
            // Milliequivalents: molar mass ÷ charge. Calcium, magnesium and sulfate are ±2; the
            // alkalinity mass passed in is already per equivalent.
            let charge: Double = [40.08, 24.305, 96.06].contains(molarMass) ? 2 : 1
            return value * molarMass / charge
        }
        return value
    }
}
