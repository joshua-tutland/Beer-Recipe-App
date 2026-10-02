import Foundation

/// How thick a harvested yeast slurry is, with a typical cell density.
public enum SlurryConsistency: String, Codable, CaseIterable, Identifiable, Sendable {
    case thin, medium, thick

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .thin: return "Thin"
        case .medium: return "Medium"
        case .thick: return "Thick"
        }
    }

    public var detail: String {
        switch self {
        case .thin: return "Pourable, lots of beer on top"
        case .medium: return "Like yogurt"
        case .thick: return "Like peanut butter, settled and decanted"
        }
    }

    /// Billion cells per mL of slurry, before allowing for trub.
    public var billionCellsPerML: Double {
        switch self {
        case .thin: return 1.0
        case .medium: return 2.0
        case .thick: return 3.0
        }
    }
}

/// Yeast slurry saved from a finished batch to pitch into a later one.
///
/// Cell counts are estimates: slurry density varies a lot, so a hemocytometer count is the only
/// way to be sure. The defaults are deliberately conservative.
public struct YeastHarvest: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var yeast: Yeast
    /// 1 for slurry harvested from a batch that was pitched with fresh yeast; one more for each
    /// reuse after that.
    public var generation: Int
    public var harvestedOn: Date
    /// Slurry left in the jar.
    public var slurryML: Double
    public var consistency: SlurryConsistency
    /// Share of the slurry that's trub and dead cells rather than healthy yeast.
    public var trubPercent: Double
    /// Where it came from, e.g. "Pale Ale · Batch 2".
    public var source: String
    public var sourceSessionID: UUID?
    public var notes: String

    public init(id: UUID = UUID(), yeast: Yeast, generation: Int = 1, harvestedOn: Date = Date(),
                slurryML: Double, consistency: SlurryConsistency = .medium, trubPercent: Double = 25,
                source: String = "", sourceSessionID: UUID? = nil, notes: String = "") {
        self.id = id
        self.yeast = yeast
        self.generation = generation
        self.harvestedOn = harvestedOn
        self.slurryML = slurryML
        self.consistency = consistency
        self.trubPercent = trubPercent
        self.source = source
        self.sourceSessionID = sourceSessionID
        self.notes = notes
    }

    /// Viability of freshly harvested, healthy slurry.
    public static let initialViability = 0.9
    /// Viability lost per day in the fridge (the same rate commonly used for liquid yeast packs).
    public static let viabilityLossPerDay = 0.007
    /// Generations after which most brewers start again from fresh yeast, as mutations and
    /// contamination become more likely.
    public static let recommendedMaxGeneration = 6

    public func ageDays(on date: Date = Date()) -> Double {
        max(0, date.timeIntervalSince(harvestedOn) / 86_400)
    }

    public func viability(on date: Date = Date()) -> Double {
        max(0, Self.initialViability - Self.viabilityLossPerDay * ageDays(on: date))
    }

    /// Billion viable cells in each mL of slurry.
    public func billionViableCellsPerML(on date: Date = Date()) -> Double {
        consistency.billionCellsPerML * max(0, 1 - trubPercent / 100) * viability(on: date)
    }

    /// Billion viable cells in the whole jar.
    public func viableCells(on date: Date = Date()) -> Double {
        slurryML * billionViableCellsPerML(on: date)
    }

    /// mL of slurry holding `billionCells` viable cells, or nil if the yeast is no longer viable.
    public func slurryML(forCells billionCells: Double, on date: Date = Date()) -> Double? {
        let perML = billionViableCellsPerML(on: date)
        guard perML > 0 else { return nil }
        return max(0, billionCells) / perML
    }

    public var isPastRecommendedGenerations: Bool { generation > Self.recommendedMaxGeneration }

    /// Harvest from a brew session. The generation counts on from the slurry the batch was
    /// pitched with, if any.
    public static func harvest(from session: BrewSession, recipe: Recipe, slurryML: Double,
                               consistency: SlurryConsistency = .medium, date: Date = Date()) -> YeastHarvest? {
        guard let yeast = recipe.yeasts.first?.yeast else { return nil }
        return YeastHarvest(yeast: yeast, generation: (session.yeastGeneration ?? 0) + 1, harvestedOn: date,
                            slurryML: slurryML, consistency: consistency,
                            source: "\(recipe.name) · \(session.name)", sourceSessionID: session.id)
    }
}

public extension BrewSession {
    /// Records that this batch was pitched with saved slurry.
    mutating func pitch(from harvest: YeastHarvest) {
        pitchedHarvestID = harvest.id
        yeastGeneration = harvest.generation
    }
}

public extension Array where Element == YeastHarvest {
    /// Takes `ml` out of the jar with `id`; jars that are used up are removed.
    func removingSlurry(_ ml: Double, from id: UUID) -> [YeastHarvest] {
        compactMap { harvest in
            guard harvest.id == id else { return harvest }
            var updated = harvest
            updated.slurryML = Swift.max(0, harvest.slurryML - ml)
            return updated.slurryML < 1 ? nil : updated
        }
    }
}
