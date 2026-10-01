import Foundation

// MARK: - Profiles

/// Brewing-relevant ions, in ppm (mg/L).
public struct WaterProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var calcium: Double
    public var magnesium: Double
    public var sodium: Double
    public var chloride: Double
    public var sulfate: Double
    public var bicarbonate: Double
    public var notes: String?

    public init(id: String = UUID().uuidString, name: String, calcium: Double = 0, magnesium: Double = 0,
                sodium: Double = 0, chloride: Double = 0, sulfate: Double = 0, bicarbonate: Double = 0,
                notes: String? = nil) {
        self.id = id
        self.name = name
        self.calcium = calcium
        self.magnesium = magnesium
        self.sodium = sodium
        self.chloride = chloride
        self.sulfate = sulfate
        self.bicarbonate = bicarbonate
        self.notes = notes
    }

    public static let distilled = WaterProfile(id: "distilled", name: "Distilled / RO")

    // MARK: Derived values

    /// Total alkalinity as CaCO3 (ppm).
    public var alkalinityAsCaCO3: Double { bicarbonate * 50.04 / 61.02 }

    /// Residual alkalinity (Kolbach), mEq/L. Positive values raise mash pH.
    public var residualAlkalinity: Double {
        bicarbonate / 61.02 - (calcium / 20.04) / 3.5 - (magnesium / 12.15) / 7
    }

    /// Residual alkalinity as CaCO3 (ppm), the unit most brewing books use.
    public var residualAlkalinityAsCaCO3: Double { residualAlkalinity * 50.04 }

    public var sulfateToChloride: Double? { chloride > 0 ? sulfate / chloride : nil }

    /// Cation/anion balance error (%): large values suggest a water report was entered wrong.
    public var ionBalanceError: Double {
        let cations = calcium / 20.04 + magnesium / 12.15 + sodium / 22.99
        let anions = chloride / 35.45 + sulfate / 48.03 + bicarbonate / 61.02
        let total = cations + anions
        return total > 0 ? abs(cations - anions) / total * 100 : 0
    }

    public subscript(ion: Ion) -> Double {
        get {
            switch ion {
            case .calcium: return calcium
            case .magnesium: return magnesium
            case .sodium: return sodium
            case .chloride: return chloride
            case .sulfate: return sulfate
            case .bicarbonate: return bicarbonate
            }
        }
        set {
            switch ion {
            case .calcium: calcium = newValue
            case .magnesium: magnesium = newValue
            case .sodium: sodium = newValue
            case .chloride: chloride = newValue
            case .sulfate: sulfate = newValue
            case .bicarbonate: bicarbonate = newValue
            }
        }
    }

    /// Mixes this water with distilled water; `fraction` is the share that is distilled (0…1).
    public func diluted(by fraction: Double) -> WaterProfile {
        var w = self
        let keep = 1 - min(max(fraction, 0), 1)
        for ion in Ion.allCases { w[ion] = self[ion] * keep }
        return w
    }
}

public enum Ion: String, CaseIterable, Codable, Sendable, Identifiable {
    case calcium, magnesium, sodium, chloride, sulfate, bicarbonate

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .calcium: return "Ca"
        case .magnesium: return "Mg"
        case .sodium: return "Na"
        case .chloride: return "Cl"
        case .sulfate: return "SO₄"
        case .bicarbonate: return "HCO₃"
        }
    }

    public var displayName: String { rawValue.capitalized }

    /// Typical recommended range for brewing water (ppm).
    public var recommendedRange: ClosedRange<Double> {
        switch self {
        case .calcium: return 50...150
        case .magnesium: return 0...30
        case .sodium: return 0...150
        case .chloride: return 0...250
        case .sulfate: return 0...350
        case .bicarbonate: return 0...250
        }
    }
}

public enum SulfateChlorideBalance: String, Sendable {
    case veryMalty, malty, balanced, bitter, veryBitter

    public init(ratio: Double) {
        switch ratio {
        case ..<0.4: self = .veryMalty
        case ..<0.8: self = .malty
        case ...1.5: self = .balanced
        case ...3: self = .bitter
        default: self = .veryBitter
        }
    }

    public var displayName: String {
        switch self {
        case .veryMalty: return "Very malty"
        case .malty: return "Malty"
        case .balanced: return "Balanced"
        case .bitter: return "Bitter / crisp"
        case .veryBitter: return "Very bitter"
        }
    }
}

/// Starting-water and target profiles bundled with the app (ppm).
public enum WaterProfiles {
    public static let sources: [WaterProfile] = [
        .distilled,
        WaterProfile(id: "pilsen", name: "Pilsen", calcium: 7, magnesium: 2, sodium: 2, chloride: 5, sulfate: 5, bicarbonate: 15,
                     notes: "Historical city water (approximate)"),
        WaterProfile(id: "munich", name: "Munich", calcium: 77, magnesium: 17, sodium: 4, chloride: 8, sulfate: 18, bicarbonate: 295,
                     notes: "Historical city water (approximate)"),
        WaterProfile(id: "dortmund", name: "Dortmund", calcium: 225, magnesium: 40, sodium: 60, chloride: 60, sulfate: 120, bicarbonate: 220,
                     notes: "Historical city water (approximate)"),
        WaterProfile(id: "vienna", name: "Vienna", calcium: 200, magnesium: 60, sodium: 8, chloride: 12, sulfate: 125, bicarbonate: 120,
                     notes: "Historical city water (approximate)"),
        WaterProfile(id: "burton", name: "Burton on Trent", calcium: 295, magnesium: 45, sodium: 55, chloride: 25, sulfate: 725, bicarbonate: 300,
                     notes: "Historical city water (approximate)"),
        WaterProfile(id: "london", name: "London", calcium: 52, magnesium: 32, sodium: 86, chloride: 34, sulfate: 32, bicarbonate: 104,
                     notes: "Historical city water (approximate)"),
        WaterProfile(id: "dublin", name: "Dublin", calcium: 118, magnesium: 4, sodium: 12, chloride: 19, sulfate: 55, bicarbonate: 319,
                     notes: "Historical city water (approximate)"),
        WaterProfile(id: "edinburgh", name: "Edinburgh", calcium: 125, magnesium: 25, sodium: 55, chloride: 65, sulfate: 140, bicarbonate: 225,
                     notes: "Historical city water (approximate)")
    ]

    public static let targets: [WaterProfile] = [
        WaterProfile(id: "t-light-soft", name: "Pale & Soft (Pilsner, Helles)", calcium: 25, magnesium: 3, sodium: 5,
                     chloride: 30, sulfate: 25, notes: "Delicate, lager-style water"),
        WaterProfile(id: "t-pale-balanced", name: "Pale Balanced", calcium: 60, magnesium: 7, sodium: 10,
                     chloride: 60, sulfate: 75, notes: "Blonde, Kölsch, Cream Ale"),
        WaterProfile(id: "t-pale-hoppy", name: "Pale Hoppy (West Coast IPA)", calcium: 110, magnesium: 15, sodium: 15,
                     chloride: 50, sulfate: 300, notes: "Crisp, dry, accentuates bitterness"),
        WaterProfile(id: "t-hazy", name: "Hazy / NEIPA", calcium: 100, magnesium: 12, sodium: 15,
                     chloride: 150, sulfate: 75, notes: "Soft, full mouthfeel"),
        WaterProfile(id: "t-amber-balanced", name: "Amber Balanced", calcium: 60, magnesium: 10, sodium: 15,
                     chloride: 65, sulfate: 75, bicarbonate: 40, notes: "Amber ale, Märzen, ESB"),
        WaterProfile(id: "t-amber-malty", name: "Amber Malty", calcium: 55, magnesium: 10, sodium: 15,
                     chloride: 100, sulfate: 45, bicarbonate: 40, notes: "Scottish, Bock, Irish Red"),
        WaterProfile(id: "t-dark", name: "Dark (Porter, Stout)", calcium: 60, magnesium: 10, sodium: 25,
                     chloride: 70, sulfate: 60, bicarbonate: 120, notes: "Alkalinity offsets roasted malt acidity")
    ]

    public static var all: [WaterProfile] { sources + targets }

    public static func profile(id: String) -> WaterProfile? { all.first { $0.id == id } }
}

// MARK: - Salts & acids

public enum BrewingSalt: String, CaseIterable, Codable, Sendable, Identifiable {
    case gypsum, calciumChloride, epsom, tableSalt, bakingSoda, chalk, magnesiumChloride

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gypsum: return "Gypsum (CaSO₄·2H₂O)"
        case .calciumChloride: return "Calcium Chloride (CaCl₂·2H₂O)"
        case .epsom: return "Epsom Salt (MgSO₄·7H₂O)"
        case .tableSalt: return "Table Salt (NaCl)"
        case .bakingSoda: return "Baking Soda (NaHCO₃)"
        case .chalk: return "Chalk (CaCO₃)"
        case .magnesiumChloride: return "Magnesium Chloride (MgCl₂·6H₂O)"
        }
    }

    public var shortName: String {
        switch self {
        case .gypsum: return "Gypsum"
        case .calciumChloride: return "Calcium Chloride"
        case .epsom: return "Epsom Salt"
        case .tableSalt: return "Table Salt"
        case .bakingSoda: return "Baking Soda"
        case .chalk: return "Chalk"
        case .magnesiumChloride: return "Magnesium Chloride"
        }
    }

    /// ppm of each ion added by 1 g of the salt dissolved in 1 L of water.
    public var ppmPerGramPerLiter: [Ion: Double] {
        switch self {
        case .gypsum: return [.calcium: 232.8, .sulfate: 557.9]
        case .calciumChloride: return [.calcium: 272.6, .chloride: 482.3]
        case .epsom: return [.magnesium: 98.6, .sulfate: 389.7]
        case .tableSalt: return [.sodium: 393.4, .chloride: 606.6]
        case .bakingSoda: return [.sodium: 273.7, .bicarbonate: 726.4]
        // Chalk only dissolves fully with added CO₂ or acid; this assumes it does.
        case .chalk: return [.calcium: 400.4, .bicarbonate: 1219.3]
        case .magnesiumChloride: return [.magnesium: 119.5, .chloride: 348.8]
        }
    }

    /// Salts the automatic solver uses (chalk dissolves poorly; MgCl₂ is rarely on hand).
    public static let solverSalts: [BrewingSalt] = [.gypsum, .calciumChloride, .epsom, .tableSalt, .bakingSoda]
}

public struct SaltAddition: Codable, Hashable, Identifiable, Sendable {
    public var id: BrewingSalt { salt }
    public var salt: BrewingSalt
    public var grams: Double

    public init(salt: BrewingSalt, grams: Double) {
        self.salt = salt
        self.grams = grams
    }
}

public enum MashAcid: String, CaseIterable, Codable, Sendable {
    case lactic88, phosphoric10

    public var displayName: String {
        switch self {
        case .lactic88: return "Lactic Acid 88%"
        case .phosphoric10: return "Phosphoric Acid 10%"
        }
    }

    /// Acid strength at mash pH, mEq per mL.
    public var mEqPerML: Double {
        switch self {
        case .lactic88: return 11.8
        case .phosphoric10: return 1.1
        }
    }
}

// MARK: - Treatment

/// A recipe's water plan: starting water, optional dilution, salts, and mash acid.
public struct WaterTreatment: Codable, Hashable, Sendable {
    public var source: WaterProfile
    public var targetId: String?
    /// Share of the brewing water replaced with distilled/RO water (0…100 %).
    public var dilutionPercent: Double
    /// Salts for the total brewing water (spread evenly over mash and sparge water).
    public var salts: [SaltAddition]
    public var acid: MashAcid
    /// Acid added to the mash, mL.
    public var acidML: Double

    public init(source: WaterProfile = .distilled, targetId: String? = nil, dilutionPercent: Double = 0,
                salts: [SaltAddition] = [], acid: MashAcid = .lactic88, acidML: Double = 0) {
        self.source = source
        self.targetId = targetId
        self.dilutionPercent = dilutionPercent
        self.salts = salts
        self.acid = acid
        self.acidML = acidML
    }

    public var target: WaterProfile? { targetId.flatMap(WaterProfiles.profile(id:)) }

    public func grams(of salt: BrewingSalt) -> Double {
        salts.first { $0.salt == salt }?.grams ?? 0
    }

    public mutating func setGrams(_ grams: Double, of salt: BrewingSalt) {
        salts.removeAll { $0.salt == salt }
        if grams > 0 { salts.append(SaltAddition(salt: salt, grams: grams)) }
        salts.sort { BrewingSalt.allCases.firstIndex(of: $0.salt)! < BrewingSalt.allCases.firstIndex(of: $1.salt)! }
    }

    /// Water profile after dilution and salts, for `totalWaterL` liters of brewing water.
    public func resultingProfile(totalWaterL: Double) -> WaterProfile {
        var w = source.diluted(by: dilutionPercent / 100)
        w.id = "result"
        w.name = "Treated Water"
        guard totalWaterL > 0 else { return w }
        for addition in salts {
            for (ion, ppm) in addition.salt.ppmPerGramPerLiter {
                w[ion] += ppm * addition.grams / totalWaterL
            }
        }
        return w
    }
}

// MARK: - Mash pH

/// Estimates mash pH with a linear malt-buffering model (after Kai Troester): each mashed
/// ingredient has a distilled-water mash pH and a buffering capacity; the water's residual
/// alkalinity and any acid shift the balance.
///
/// Estimates are typically within ±0.1–0.2 pH. A pH meter reading always wins.
public enum MashPH {
    public enum MaltClass: String, Sendable {
        case base, crystal, roast, acidulated, adjunct
    }

    /// Lactic acid in acidulated malt (≈ 0.1 pH drop per 1 % of the grist).
    static let acidMaltMEqPerGram = 0.4

    public static func maltClass(_ f: Fermentable) -> MaltClass {
        let name = f.name.lowercased()
        if name.contains("acid") { return .acidulated }
        if f.type == .adjunct { return .adjunct }
        if name.contains("carafa") || name.contains("roast") || name.contains("black") || name.contains("chocolate")
            || f.colorLovibond >= 200 {
            return .roast
        }
        if name.contains("carapils") || name.contains("carafoam") { return .base }
        if name.contains("crystal") || name.contains("cara") || name.contains("caramel") || name.contains("special b") {
            return .crystal
        }
        return .base
    }

    /// Distilled-water mash pH and buffering capacity (mEq / kg·pH).
    static func parameters(_ f: Fermentable) -> (pH: Double, buffer: Double) {
        switch maltClass(f) {
        case .base: return (max(5.4, 5.72 - 0.0045 * f.colorLovibond), 40)
        case .crystal: return (5.22 - 0.00504 * f.colorLovibond, 45)
        case .roast: return (4.6, 45)
        case .acidulated: return (5.72, 40)  // its acid is accounted for separately
        case .adjunct: return (5.85, 25)
        }
    }

    public struct Estimate: Hashable, Sendable {
        /// Estimated room-temperature mash pH.
        public var pH: Double
        /// Distilled-water pH of the grist alone.
        public var gristPH: Double
        /// Acid (mEq) needed to reach the target pH; negative means base (alkalinity) is needed.
        public var acidNeededMEq: Double
    }

    /// - Parameters:
    ///   - water: profile of the mash water (after salts).
    ///   - mashWaterL: liters of water in the mash.
    ///   - acidMEq: acid added to the mash.
    public static func estimate(fermentables: [FermentableAddition], water: WaterProfile, mashWaterL: Double,
                                acidMEq: Double, targetPH: Double = 5.4) -> Estimate? {
        var weighted = 0.0
        var capacity = 0.0
        var maltAcid = 0.0
        for a in fermentables where a.fermentable.type.isMashed && a.amountKg > 0 {
            let p = parameters(a.fermentable)
            weighted += a.amountKg * p.buffer * p.pH
            capacity += a.amountKg * p.buffer
            if maltClass(a.fermentable) == .acidulated {
                maltAcid += a.amountKg * 1000 * acidMaltMEqPerGram
            }
        }
        guard capacity > 0 else { return nil }
        let alkalinity = water.residualAlkalinity * mashWaterL
        let gristPH = weighted / capacity
        let pH = (weighted + alkalinity - acidMEq - maltAcid) / capacity
        let needed = weighted + alkalinity - acidMEq - maltAcid - targetPH * capacity
        return Estimate(pH: pH, gristPH: gristPH, acidNeededMEq: needed)
    }
}

// MARK: - Salt solver

public enum WaterSolver {
    /// Finds non-negative salt amounts (grams for `totalWaterL`) that bring `start` closest to `target`,
    /// by coordinate descent on the squared ppm error.
    public static func salts(from start: WaterProfile, to target: WaterProfile, totalWaterL: Double,
                             using salts: [BrewingSalt] = BrewingSalt.solverSalts) -> [SaltAddition] {
        guard totalWaterL > 0 else { return [] }
        // Column j: ppm added per gram of salt j in this volume.
        let columns = salts.map { salt in
            Ion.allCases.map { (salt.ppmPerGramPerLiter[$0] ?? 0) / totalWaterL }
        }
        // Down-weight sodium so the solver doesn't chase it with table salt or baking soda.
        let weights = Ion.allCases.map { $0 == .sodium ? 0.3 : 1.0 }
        let desired = Ion.allCases.map { max(0, target[$0] - start[$0]) }

        var grams = Array(repeating: 0.0, count: salts.count)
        var added = Array(repeating: 0.0, count: Ion.allCases.count)
        for _ in 0..<500 {
            var changed = 0.0
            for j in salts.indices {
                let col = columns[j]
                var numerator = 0.0
                var denominator = 0.0
                for i in col.indices where col[i] > 0 {
                    numerator += weights[i] * col[i] * (desired[i] - added[i])
                    denominator += weights[i] * col[i] * col[i]
                }
                guard denominator > 0 else { continue }
                let updated = max(0, grams[j] + numerator / denominator)
                let delta = updated - grams[j]
                if delta != 0 {
                    for i in col.indices { added[i] += col[i] * delta }
                    grams[j] = updated
                    changed = max(changed, abs(delta))
                }
            }
            if changed < 1e-6 { break }
        }
        return zip(salts, grams)
            .map { SaltAddition(salt: $0, grams: ($1 * 10).rounded() / 10) }
            .filter { $0.grams > 0 }
    }
}
