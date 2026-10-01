import Foundation

// MARK: - Yeast starters

/// Yeast viability and starter growth.
///
/// Growth models: Kai Troester's (Braukaiser) stir-plate measurements, and Chris White's
/// inoculation-rate model (as popularized by Mr Malty / YeastCalc) for starters without a stir plate.
public enum YeastStarter {
    public enum Aeration: String, CaseIterable, Codable, Sendable, Identifiable {
        case stirPlate, none

        public var id: String { rawValue }
        public var displayName: String { self == .stirPlate ? "Stir Plate" : "No Stir Plate" }
    }

    public struct Step: Hashable, Sendable, Identifiable {
        public var id = UUID()
        public var volumeL: Double
        public var gravity: Double
        public var aeration: Aeration

        public init(volumeL: Double, gravity: Double = 1.036, aeration: Aeration = .stirPlate) {
            self.volumeL = volumeL
            self.gravity = gravity
            self.aeration = aeration
        }
    }

    public struct StepResult: Hashable, Sendable {
        public var dryMaltExtractGrams: Double
        public var startCellsBillions: Double
        public var endCellsBillions: Double
    }

    /// Billion cells in a fresh liquid pack or vial.
    public static let liquidPackCells = 100.0
    /// Billion viable cells per gram of dry yeast (a conservative figure for rehydrated dry yeast).
    public static let dryCellsPerGram = 10.0

    /// Viable cells in liquid packs of the given age: about 0.7% viability is lost per day.
    public static func liquidCells(packs: Double, ageDays: Double) -> Double {
        let viability = max(0, 1 - 0.007 * max(0, ageDays))
        return packs * liquidPackCells * viability
    }

    /// Grams of dry malt extract for a starter of `volumeL` at `gravity` (1 lb DME in 1 gal ≈ 44 points).
    public static func dryMaltExtractGrams(volumeL: Double, gravity: Double) -> Double {
        let points = max(0, (gravity - 1) * 1000)
        return points * BrewMath.litersToGallons(volumeL) / 44 * 453.592_37
    }

    /// Cells after one starter step.
    public static func grow(cellsBillions: Double, step: Step) -> StepResult {
        let extract = dryMaltExtractGrams(volumeL: step.volumeL, gravity: step.gravity)
        var newCells = 0.0
        if extract > 0 && cellsBillions > 0 {
            switch step.aeration {
            case .stirPlate:
                // Braukaiser: ~1.4 billion new cells per gram of extract up to an inoculation rate of
                // 1.4 B/g, then less, reaching zero around 3.5 B/g.
                let inoculation = cellsBillions / extract
                let rate = inoculation < 1.4 ? 1.4 : max(0, 2.33 - 0.67 * inoculation)
                newCells = rate * extract
            case .none:
                // White: growth factor from the inoculation rate in million cells per mL, capped at 6×.
                let inoculation = cellsBillions * 1000 / (step.volumeL * 1000)
                let factor = min(6, max(0, 12.547_937_76 * pow(inoculation, -0.459_485_832_4) - 0.999_499_490_6))
                newCells = cellsBillions * factor
            }
        }
        return StepResult(dryMaltExtractGrams: extract, startCellsBillions: cellsBillions,
                          endCellsBillions: cellsBillions + newCells)
    }

    /// Runs several steps in a row (each step's yeast seeds the next).
    public static func run(startingCells: Double, steps: [Step]) -> [StepResult] {
        var cells = startingCells
        return steps.map { step in
            let result = grow(cellsBillions: cells, step: step)
            cells = result.endCellsBillions
            return result
        }
    }
}

// MARK: - Kegging

public enum Carbonation {
    /// Regulator pressure (psi) to force-carbonate beer at `tempC` to `volumes` of CO₂.
    public static func forceCarbonationPSI(tempC: Double, volumes: Double) -> Double {
        let t = BrewMath.cToF(tempC)
        let v = volumes
        let psi = -16.6999 - 0.0101059 * t + 0.00116512 * t * t + 0.173354 * t * v + 4.24267 * v - 0.0684226 * v * v
        return max(0, psi)
    }

    public static func psiToKPa(_ psi: Double) -> Double { psi * 6.894_757 }

    /// Serving line tubing and its typical restriction (psi lost per foot).
    public enum Line: String, CaseIterable, Codable, Sendable, Identifiable {
        case vinyl3_16, vinyl1_4, vinyl5_16, barrier4mm

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .vinyl3_16: return "3/16\" ID vinyl"
            case .vinyl1_4: return "1/4\" ID vinyl"
            case .vinyl5_16: return "5/16\" ID vinyl"
            case .barrier4mm: return "4 mm ID barrier"
            }
        }

        public var psiPerFoot: Double {
            switch self {
            case .vinyl3_16: return 3.0
            case .vinyl1_4: return 0.85
            case .vinyl5_16: return 0.40
            case .barrier4mm: return 1.2
            }
        }
    }

    /// Line length (feet) that balances the system so beer pours at about 1 psi at the faucet.
    /// `riseFeet` is the height from the keg's middle to the faucet (0.5 psi per foot).
    public static func balancedLineFeet(kegPSI: Double, line: Line, riseFeet: Double = 1) -> Double {
        max(0, (kegPSI - 0.5 * riseFeet - 1) / line.psiPerFoot)
    }
}

// MARK: - Hop substitution

public enum HopSubstitution {
    /// Hops the catalog lists as substitutes for `hop`, in the order given.
    public static func suggestions(for hop: Hop, in catalog: [Hop]) -> [Hop] {
        guard let text = hop.substitutes else { return [] }
        let names = text.split(whereSeparator: { ",;/".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        return names.compactMap { name -> Hop? in
            let match = catalog.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
                ?? catalog.first { $0.name.range(of: name, options: .caseInsensitive) != nil }
            guard let match, match.id != hop.id, seen.insert(match.id).inserted else { return nil }
            return match
        }
    }

    /// Swaps the hop in an addition. Kettle additions (boil, first wort, mash, whirlpool) are
    /// re-weighed so the alpha acid, and therefore the bitterness, stays the same. Dry hops keep
    /// their weight, since they're about aroma rather than bitterness.
    public static func substitute(_ addition: HopAddition, with hop: Hop, alphaAcid: Double? = nil) -> HopAddition {
        var result = addition
        let newAlpha = alphaAcid ?? hop.alphaAcid
        if addition.use != .dryHop, newAlpha > 0 {
            result.amountGrams = addition.amountGrams * addition.alphaAcid / newAlpha
        }
        result.hop = hop
        result.alphaAcid = newAlpha
        return result
    }
}
