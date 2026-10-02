import Foundation

/// A gravity reading taken during fermentation.
public struct GravityReading: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var date: Date
    public var gravity: Double
    public var tempC: Double?
    public var note: String

    public init(id: UUID = UUID(), date: Date = Date(), gravity: Double, tempC: Double? = nil, note: String = "") {
        self.id = id
        self.date = date
        self.gravity = gravity
        self.tempC = tempC
        self.note = note
    }
}

/// One brew of a recipe: what was planned, and what was actually measured.
///
/// Measured values are optional; brewers fill them in as the day goes on.
public struct BrewSession: Codable, Hashable, Identifiable, Sendable {
    /// The recipe's predictions at the moment the brew day started, so later recipe edits
    /// don't change how this brew is evaluated.
    public struct Plan: Codable, Hashable, Sendable {
        public var batchSizeL: Double
        public var boilTimeMinutes: Double
        public var efficiency: Double
        public var og: Double
        public var fg: Double
        public var preBoilGravity: Double
        public var preBoilVolumeL: Double
        public var postBoilVolumeL: Double
        public var strikeTempC: Double
        /// Σ(lb × PPG) of mashed ingredients — their extract potential before efficiency.
        public var mashedPointGallons: Double
        /// Σ(lb × PPG) of extracts and sugars, which don't depend on efficiency.
        public var fixedPointGallons: Double

        public init(recipe: Recipe) {
            let stats = recipe.stats
            batchSizeL = recipe.equipment.batchSizeL
            boilTimeMinutes = recipe.equipment.boilTimeMinutes
            efficiency = recipe.equipment.efficiency
            og = stats.og
            fg = stats.fg
            preBoilGravity = stats.preBoilGravity
            preBoilVolumeL = stats.preBoilVolumeL
            postBoilVolumeL = stats.postBoilVolumeL
            strikeTempC = stats.strikeTempC
            var mashed = 0.0
            var fixed = 0.0
            for a in recipe.fermentables {
                let points = BrewMath.kgToLb(a.amountKg) * a.fermentable.potentialPPG
                if a.fermentable.type.isMashed { mashed += points } else { fixed += points }
            }
            mashedPointGallons = mashed
            fixedPointGallons = fixed
        }
    }

    public var id: UUID
    public var brewDate: Date
    public var name: String
    public var plan: Plan

    // Brew day
    public var mashTempC: Double?
    public var mashPH: Double?
    public var preBoilVolumeL: Double?
    public var preBoilGravity: Double?
    public var postBoilVolumeL: Double?
    public var og: Double?
    public var fermenterVolumeL: Double?

    // Fermentation & packaging
    public var readings: [GravityReading]
    public var fg: Double?
    public var packagedDate: Date?
    public var packagedVolumeL: Double?

    // Tasting
    public var rating: Int
    public var notes: String

    /// Brew-day checklist steps (and boil additions) that have been ticked off.
    /// Optional so sessions saved before the checklist existed still decode.
    public var completedStepIDs: [String]?

    /// Set once this brew's ingredients have been taken out of inventory, so it can't happen twice.
    public var inventoryDeductedAt: Date?

    /// BJCP-style tasting score.
    public var scoresheet: TastingScoresheet?

    /// The saved slurry this batch was pitched with, if any.
    public var pitchedHarvestID: UUID?
    /// Generation of the yeast pitched into this batch: nil for fresh yeast, otherwise the
    /// generation of the slurry that was used.
    public var yeastGeneration: Int?

    public init(id: UUID = UUID(), recipe: Recipe, brewDate: Date = Date(), name: String? = nil) {
        self.id = id
        self.brewDate = brewDate
        self.name = name ?? "Batch \(recipe.sessions.count + 1)"
        self.plan = Plan(recipe: recipe)
        self.readings = []
        self.rating = 0
        self.notes = ""
    }

    /// The most recent gravity: the final gravity if recorded, else the latest fermentation reading.
    public var currentGravity: Double? {
        fg ?? readings.max(by: { $0.date < $1.date })?.gravity
    }

    public var isComplete: Bool { fg != nil }

    public func isStepDone(_ id: String) -> Bool {
        completedStepIDs?.contains(id) ?? false
    }

    public mutating func setStep(_ id: String, done: Bool) {
        var ids = completedStepIDs ?? []
        ids.removeAll { $0 == id }
        if done { ids.append(id) }
        completedStepIDs = ids
    }

    public var results: BrewSessionResults { BrewSessionResults(session: self) }
}

/// Numbers derived from a brew session's measurements.
public struct BrewSessionResults: Hashable, Sendable {
    /// ABV from OG and the current gravity (final or latest reading).
    public var abv: Double?
    public var apparentAttenuation: Double?
    /// Brewhouse efficiency: extract that made it into the fermenter.
    public var brewhouseEfficiency: Double?
    /// Efficiency into the kettle, from pre-boil gravity and volume.
    public var kettleEfficiency: Double?
    /// Measured boil-off rate (L/hr).
    public var boilOffLPerHour: Double?
    public var ogDifference: Double?
    public var fgDifference: Double?

    public init(session s: BrewSession) {
        let plan = s.plan

        if let og = s.og, let current = s.currentGravity, og > 1 {
            abv = BrewMath.abv(og: og, fg: current)
            apparentAttenuation = BrewMath.apparentAttenuation(og: og, fg: current)
        }

        func efficiency(gravity: Double, volumeL: Double) -> Double? {
            guard plan.mashedPointGallons > 0, gravity > 1, volumeL > 0 else { return nil }
            let pointGallons = (gravity - 1) * 1000 * BrewMath.litersToGallons(volumeL)
            return (pointGallons - plan.fixedPointGallons) / plan.mashedPointGallons * 100
        }

        if let og = s.og {
            brewhouseEfficiency = efficiency(gravity: og, volumeL: s.fermenterVolumeL ?? plan.batchSizeL)
            ogDifference = og - plan.og
        }
        if let gravity = s.preBoilGravity, let volume = s.preBoilVolumeL {
            kettleEfficiency = efficiency(gravity: gravity, volumeL: volume)
        }
        if let pre = s.preBoilVolumeL, let post = s.postBoilVolumeL, plan.boilTimeMinutes > 0, pre > post {
            boilOffLPerHour = (pre - post) / (plan.boilTimeMinutes / 60)
        }
        if let fg = s.fg {
            fgDifference = fg - plan.fg
        }
    }
}
